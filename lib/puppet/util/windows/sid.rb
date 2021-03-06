require 'puppet/util/windows'

module Puppet::Util::Windows
  module SID
    require 'ffi'
    extend FFI::Library

    # missing from Windows::Error
    ERROR_NONE_MAPPED           = 1332
    ERROR_INVALID_SID_STRUCTURE = 1337

    # Convert an account name, e.g. 'Administrators' into a SID string,
    # e.g. 'S-1-5-32-544'. The name can be specified as 'Administrators',
    # 'BUILTIN\Administrators', or 'S-1-5-32-544', and will return the
    # SID. Returns nil if the account doesn't exist.
    def name_to_sid(name)
      sid = name_to_sid_object(name)

      sid ? sid.to_s : nil
    end

    # Convert an account name, e.g. 'Administrators' into a SID object,
    # e.g. 'S-1-5-32-544'. The name can be specified as 'Administrators',
    # 'BUILTIN\Administrators', or 'S-1-5-32-544', and will return the
    # SID object. Returns nil if the account doesn't exist.
    def name_to_sid_object(name)
      # Apparently, we accept a symbol..
      name = name.to_s.strip if name

      # if it's in SID string form, convert to user
      parsed_sid = Win32::Security::SID.string_to_sid(name) rescue nil

      parsed_sid ? Win32::Security::SID.new(parsed_sid) : Win32::Security::SID.new(name)
    rescue
      nil
    end

    # Converts an octet string array of bytes to a SID object,
    # e.g. [1, 1, 0, 0, 0, 0, 0, 5, 18, 0, 0, 0] is the representation for
    # S-1-5-18, the local 'SYSTEM' account.
    # Raises an Error for nil or non-array input.
    def octet_string_to_sid_object(bytes)
      if !bytes || !bytes.respond_to?('pack') || bytes.empty?
        raise Puppet::Util::Windows::Error.new("Octet string must be an array of bytes")
      end

      Win32::Security::SID.new(bytes.pack('C*'))
    end

    # Convert a SID string, e.g. "S-1-5-32-544" to a name,
    # e.g. 'BUILTIN\Administrators'. Returns nil if an account
    # for that SID does not exist.
    def sid_to_name(value)
      sid = Win32::Security::SID.new(Win32::Security::SID.string_to_sid(value))

      if sid.domain and sid.domain.length > 0
        "#{sid.domain}\\#{sid.account}"
      else
        sid.account
      end
    rescue
      nil
    end

    # http://stackoverflow.com/a/1792930 - 68 bytes, 184 characters in a string
    MAXIMUM_SID_STRING_LENGTH = 184

    # Convert a SID pointer to a SID string, e.g. "S-1-5-32-544".
    def sid_ptr_to_string(psid)
      if ! psid.instance_of?(FFI::Pointer) || IsValidSid(psid) == FFI::WIN32_FALSE
        raise Puppet::Util::Windows::Error.new("Invalid SID")
      end

      buffer_ptr = FFI::MemoryPointer.new(:pointer, 1)

      begin
        if ConvertSidToStringSidW(psid, buffer_ptr) == FFI::WIN32_FALSE
          raise Puppet::Util::Windows::Error.new("Failed to convert binary SID")
        end

        wide_string_ptr = buffer_ptr.read_pointer

        if wide_string_ptr.null?
          raise Puppet::Error.new("ConvertSidToStringSidW failed to allocate buffer for sid")
        end

        return wide_string_ptr.read_arbitrary_wide_string_up_to(MAXIMUM_SID_STRING_LENGTH)
      ensure
        if ! wide_string_ptr.nil? && ! wide_string_ptr.null?
          if LocalFree(wide_string_ptr.address) != FFI::Pointer::NULL_HANDLE
            Puppet.debug "LocalFree memory leak"
          end
        end
      end
    end

    # Convert a SID string, e.g. "S-1-5-32-544" to a pointer (containing the
    # address of the binary SID structure). The returned value can be used in
    # Win32 APIs that expect a PSID, e.g. IsValidSid. The account for this
    # SID may or may not exist.
    def string_to_sid_ptr(string_sid, &block)
      lpcwstr = FFI::MemoryPointer.from_string_to_wide_string(string_sid)
      sid_ptr_ptr = FFI::MemoryPointer.new(:pointer, 1)

      if ConvertStringSidToSidW(lpcwstr, sid_ptr_ptr) == FFI::WIN32_FALSE
        raise Puppet::Util::Windows::Error.new("Failed to convert string SID: #{string_sid}")
      end

      begin
        yield sid_ptr = sid_ptr_ptr.read_pointer
      ensure
        if LocalFree(sid_ptr.address) != FFI::Pointer::NULL_HANDLE
          Puppet.debug "LocalFree memory leak"
        end
      end
    end

    # Return true if the string is a valid SID, e.g. "S-1-5-32-544", false otherwise.
    def valid_sid?(string_sid)
      string_to_sid_ptr(string_sid) { |ptr| true }
    rescue Puppet::Util::Windows::Error => e
      if e.code == ERROR_INVALID_SID_STRUCTURE
        false
      else
        raise
      end
    end

    ffi_convention :stdcall

    # http://msdn.microsoft.com/en-us/library/windows/desktop/aa379151(v=vs.85).aspx
    # BOOL WINAPI IsValidSid(
    #   _In_  PSID pSid
    # );
    ffi_lib :advapi32
    attach_function_private :IsValidSid,
      [:pointer], :win32_bool

    # http://msdn.microsoft.com/en-us/library/windows/desktop/aa376399(v=vs.85).aspx
    # BOOL ConvertSidToStringSid(
    #   _In_   PSID Sid,
    #   _Out_  LPTSTR *StringSid
    # );
    ffi_lib :advapi32
    attach_function_private :ConvertSidToStringSidW,
      [:pointer, :pointer], :win32_bool

    # http://msdn.microsoft.com/en-us/library/windows/desktop/aa376402(v=vs.85).aspx
    # BOOL WINAPI ConvertStringSidToSid(
    #   _In_   LPCTSTR StringSid,
    #   _Out_  PSID *Sid
    # );
    ffi_lib :advapi32
    attach_function_private :ConvertStringSidToSidW,
      [:lpcwstr, :pointer], :win32_bool

    # http://msdn.microsoft.com/en-us/library/windows/desktop/aa366730(v=vs.85).aspx
    # HLOCAL WINAPI LocalFree(
    #   _In_  HLOCAL hMem
    # );
    ffi_lib :kernel32
    attach_function_private :LocalFree, [:handle], :handle
  end
end
