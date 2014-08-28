require File.dirname(__FILE__) + '/test_helper.rb'

class TestGeoip < Minitest::Test

  def setup
    data = '/usr/share/GeoIP/GeoIP.dat'
    begin
      @g = GeoIP.new(data)
    rescue Errno::ENOENT => e
      skip e.message
    end
  end

  def test_constructor
    assert_instance_of GeoIP, @g
  end

end
