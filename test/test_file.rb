#
# This program walks the specified file and dumps it in IP order
#
require 'geoip'

ARGV.each do |file|
  g = GeoIP.new(file)
  g.each_by_ip do |ip, val|
    ip_str =
      if ip >= (1<<32)
	(('%032X'%ip).scan(/..../)*':').sub(/\A(0000:)+/, '::')	  # An IPv6 address
      else
	'%d.%d.%d.%d' % [ip].pack('N').unpack('C4')
      end
    puts "#{ip_str}\t#{val ? val.to_hash.to_a.sort.map{|n,v| "#{n}=#{v.inspect}"}*', ' : 'Unassigned'}"
  end
end
