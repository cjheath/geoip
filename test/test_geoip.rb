require File.dirname(__FILE__) + '/test_helper.rb'

class TestGeoip < Test::Unit::TestCase

  def setup
  end
  
  def test_truth
    assert true
  end

  def test_geoip_result
    result = GeoIP::Result[[
      [:a, "a"],
      [:b, "b"],
      [:c, "c"]
    ]]

    # hash access
    assert_equal "a", result[:a]
    assert_equal "b", result[:b]
    assert_equal "c", result[:c]

    # numeric array access
    assert_equal "a", result[0]
    assert_equal "b", result[1]
    assert_equal "c", result[2]

    # Result#to_a
    assert_equal %w{a b c}, result.to_a
  end
end
