# Test host job creation, modification, and destruction

if __FILE__ == $0
    $:.unshift '..'
    $:.unshift '../../lib'
    $puppetbase = "../.."
end

require 'puppettest'
require 'puppet'
require 'test/unit'
require 'facter'

class TestPort < Test::Unit::TestCase
	include TestPuppet

    def setup
        super
        @porttype = Puppet.type(:port)

        @provider = @porttype.defaultprovider

        # Make sure they aren't using something funky like netinfo
        unless @provider.name == :parsed
            @porttype.defaultprovider = @porttype.provider(:parsed)
        end

        cleanup do @porttype.defaultprovider = nil end

        oldpath = @provider.path
        cleanup do
            @provider.path = oldpath
        end
        @provider.path = tempfile()
    end

    def mkport
        port = nil

        if defined? @pcount
            @pcount += 1
        else
            @pcount = 1
        end
        assert_nothing_raised {
            port = Puppet.type(:port).create(
                :name => "puppet%s" % @pcount,
                :number => "813%s" % @pcount,
                :protocols => "tcp",
                :description => "The port that Puppet runs on",
                :alias => "coolness%s" % @pcount
            )
        }

        return port
    end

    def test_simpleport
        host = nil
        assert_nothing_raised {
            Puppet.type(:port).defaultprovider.retrieve

            count = 0
            @porttype.each do |h|
                count += 1
            end

            assert_equal(0, count, "Found hosts in empty file somehow")
        }

        port = mkport

        assert_apply(port)
        assert_nothing_raised {
            port.retrieve
        }

        assert(port.exists?, "Port did not get created")
    end

    def test_moddingport
        port = nil
        port = mkport

        assert_events([:port_created], port)

        port.retrieve

        port[:protocols] = %w{tcp udp}

        assert_events([:port_changed], port)
    end

    def test_multivalues
        port = mkport
        assert_raise(Puppet::Error) {
            port[:protocols] = "udp tcp"
        }
        assert_raise(Puppet::Error) {
            port[:alias] = "puppetmasterd yayness"
        }
    end

    def test_removal
        port = mkport()
        assert_nothing_raised {
            port[:ensure] = :present
        }
        assert_events([:port_created], port)
        assert_events([], port)

        assert(port.exists?, "port was not created")
        assert_nothing_raised {
            port[:ensure] = :absent
        }

        assert_events([:port_deleted], port)
        assert(! port.exists?, "port was not removed")
        assert_events([], port)
    end

    def test_addingstates
        port = mkport()
        assert_events([:port_created], port)

        port.delete(:alias)
        assert(! port.state(:alias))
        assert_events([:port_changed], port)

        assert_nothing_raised {
            port.retrieve
        }

        assert_equal(:present, port.is(:ensure))

        assert_equal(:absent, port.retrieve[:alias])

        port[:alias] = "yaytest"
        assert_events([:port_changed], port)
        port.retrieve
        assert(port.state(:alias).is == ["yaytest"])
    end
end

# $Id$
