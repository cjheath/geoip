#
# Native Ruby reader for the GeoIP database
# Lookup the country where IP address is allocated
#
# = COPYRIGHT
#
# This version Copyright (C) 2005 Clifford Heath
# Derived from the C version, Copyright (C) 2003 MaxMind LLC
#
# This library is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public
# License as published by the Free Software Foundation; either
# version 2.1 of the License, or (at your option) any later version.
#
# This library is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public
# License along with this library; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
# = SYNOPSIS
#
#   require 'geoip'
#   p GeoIP.new('/usr/share/GeoIP/GeoIP.dat').country("www.netscape.sk")
#
# = DESCRIPTION
#
# GeoIP searches a GeoIP database for a given host or IP address, and
# returns information about the country where the IP address is allocated.
#
# = PREREQUISITES
#
# You need at least the free GeoIP.dat, for which the last known download
# location is <http://www.maxmind.com/download/geoip/database/GeoIP.dat.gz>
# This API requires the file to be decompressed for searching. Other versions
# of this database are available for purchase which contain more detailed
# information, but this information is not returned by this implementation.
# See www.maxmind.com for more information.
#

require 'thread' # Needed for Mutex
require 'socket'
begin
  require 'io/extra' # for IO.pread
rescue LoadError
  # oh well, hope they're not forking after initializing
end
begin
  require 'ipaddr'  # Needed for IPv6 support
rescue LoadError
  # Won't work for an IPv6 database
end

require 'yaml'

class GeoIP

  # The GeoIP GEM version number
  VERSION = "1.3.5"

  # The +data/+ directory for geoip
  DATA_DIR = File.expand_path(File.join(File.dirname(__FILE__),'..','data','geoip'))

  # Ordered list of the ISO3166 2-character country codes, ordered by
  # GeoIP ID
  CountryCode = YAML.load_file(File.join(DATA_DIR,'country_code.yml'))

  # Ordered list of the ISO3166 3-character country codes, ordered by
  # GeoIP ID
  CountryCode3 = YAML.load_file(File.join(DATA_DIR,'country_code3.yml'))

  # Ordered list of the English names of the countries, ordered by GeoIP ID
  CountryName = YAML.load_file(File.join(DATA_DIR,'country_name.yml'))

  # Ordered list of the ISO3166 2-character continent code of the countries,
  # ordered by GeoIP ID
  CountryContinent = YAML.load_file(File.join(DATA_DIR,'country_continent.yml'))

  # Load a hash of region names by region code
  RegionName = YAML.load_file(File.join(DATA_DIR,'region.yml'))

  # Hash of the timezone codes mapped to timezone name, per zoneinfo
  TimeZone = YAML.load_file(File.join(DATA_DIR,'time_zone.yml'))

  GEOIP_COUNTRY_EDITION = 1
  GEOIP_CITY_EDITION_REV1 = 2
  GEOIP_REGION_EDITION_REV1 = 3
  GEOIP_ISP_EDITION = 4
  GEOIP_ORG_EDITION = 5
  GEOIP_CITY_EDITION_REV0 = 6
  GEOIP_REGION_EDITION_REV0 = 7
  GEOIP_PROXY_EDITION = 8
  GEOIP_ASNUM_EDITION = 9
  GEOIP_NETSPEED_EDITION = 10
  GEOIP_COUNTRY_EDITION_V6 = 12
  GEOIP_CITY_EDITION_REV1_V6 = 30

  COUNTRY_BEGIN = 16776960          #:nodoc:
  STATE_BEGIN_REV0 = 16700000       #:nodoc:
  STATE_BEGIN_REV1 = 16000000       #:nodoc:
  STRUCTURE_INFO_MAX_SIZE = 20      #:nodoc:
  DATABASE_INFO_MAX_SIZE = 100      #:nodoc:
  MAX_ORG_RECORD_LENGTH = 300       #:nodoc:
  MAX_ASN_RECORD_LENGTH = 300       #:nodoc: unverified
  US_OFFSET = 1                     #:nodoc:
  CANADA_OFFSET = 677               #:nodoc:
  WORLD_OFFSET = 1353               #:nodoc:
  FIPS_RANGE = 360                  #:nodoc:
  FULL_RECORD_LENGTH = 50           #:nodoc:

  STANDARD_RECORD_LENGTH = 3        #:nodoc:
  SEGMENT_RECORD_LENGTH = 3         #:nodoc:

  class Country < Struct.new(:request, :ip, :country_code, :country_code2, :country_code3, :country_name, :continent_code)

    def to_hash
      Hash[each_pair.to_a]
    end

  end

  class Region < Struct.new(:request, :ip, :country_code2, :country_code3, :country_name, :continent_code,
                            :region_code, :region_name, :timezone)

    def to_hash
      Hash[each_pair.to_a]
    end

  end

  # Warning: for historical reasons the region code is mis-named region_name here
  class City < Struct.new(:request, :ip, :country_code2, :country_code3, :country_name, :continent_code,
                          :region_name, :city_name, :postal_code, :latitude, :longitude, :dma_code, :area_code, :timezone, :real_region_name)

    def to_hash
      Hash[each_pair.to_a]
    end

    def region_code
      self.region_name
    end

  end

  class ASN < Struct.new(:number, :asn)

    alias as_num number

    def to_hash
      Hash[each_pair.to_a]
    end

  end

  class ISP < Struct.new(:isp)
    def to_hash
      Hash[each_pair.to_a]
    end
  end

  # The Edition number that identifies which kind of database you've opened
  attr_reader :database_type

  # An IP that is used instead of local IPs
  attr_accessor :local_ip_alias

  alias databaseType database_type

  # Open the GeoIP database and determine the file format version.
  #
  # +filename+ is a String holding the path to the GeoIP.dat file
  # +options+ is an integer holding caching flags (unimplemented)
  #
  def initialize(filename, flags = 0)
    @mutex = unless IO.respond_to?(:pread)
               Mutex.new
             end

    @flags = flags
    @database_type = GEOIP_COUNTRY_EDITION
    @record_length = STANDARD_RECORD_LENGTH
    @file = File.open(filename, 'rb')

    detect_database_type!
  end

  # Search the GeoIP database for the specified host, returning country
  # info.
  #
  # +hostname+ is a String holding the host's DNS name or numeric IP
  # address.
  #
  # If the database is a City database (normal), return the result that
  # +city+ would return.
  #
  # Otherwise, return a Country object with the seven elements:
  # * The host or IP address string as requested
  # * The IP address string after looking up the host
  # * The GeoIP country-ID as an integer (N.B. this is excluded from the
  #   city results!)
  # * The two-character country code (ISO 3166-1 alpha-2)
  # * The three-character country code (ISO 3166-2 alpha-3)
  # * The ISO 3166 English-language name of the country
  # * The two-character continent code
  #
  def country(hostname)
    if (@database_type == GEOIP_CITY_EDITION_REV0 ||
        @database_type == GEOIP_CITY_EDITION_REV1 ||
        @database_type == GEOIP_CITY_EDITION_REV1_V6)
      return city(hostname)
    end

    if (@database_type == GEOIP_REGION_EDITION_REV0 ||
        @database_type == GEOIP_REGION_EDITION_REV1)
      return region(hostname)
    end

    ip = lookup_ip(hostname)
    if (@database_type == GEOIP_COUNTRY_EDITION ||
        @database_type == GEOIP_PROXY_EDITION ||
        @database_type == GEOIP_NETSPEED_EDITION)
        # Convert numeric IP address to an integer
        ipnum = iptonum(ip)
        code = (seek_record(ipnum) - COUNTRY_BEGIN)
    elsif @database_type == GEOIP_COUNTRY_EDITION_V6
      ipaddr = IPAddr.new ip
      code = (seek_record_v6(ipaddr.to_i) - COUNTRY_BEGIN)
    else
      throw "Invalid GeoIP database type, can't look up Country by IP"
    end

    Country.new(
      hostname,                   # Requested hostname
      ip,                         # Ip address as dotted quad
      code,                       # GeoIP's country code
      CountryCode[code],          # ISO3166-1 alpha-2 code
      CountryCode3[code],         # ISO3166-2 alpha-3 code
      CountryName[code],          # Country name, per ISO 3166
      CountryContinent[code]      # Continent code.
    )
  end

  # Search the GeoIP database for the specified host, retuning region info.
  #
  # +hostname+ is a String holding the hosts's DNS name or numeric IP
  # address.
  #
  # Returns a Region object with the nine elements:
  # * The host or IP address string as requested
  # * The IP address string after looking up the host
  # * The two-character country code (ISO 3166-1 alpha-2)
  # * The three-character country code (ISO 3166-2 alpha-3)
  # * The ISO 3166 English-language name of the country
  # * The two-character continent code
  # * The region name (state or territory)
  # * The timezone name, if known
  #
  def region(hostname)
    if (@database_type == GEOIP_CITY_EDITION_REV0 ||
        @database_type == GEOIP_CITY_EDITION_REV1 ||
        @database_type == GEOIP_CITY_EDITION_REV1_V6)
      return city(hostname)
    end

    if (@database_type == GEOIP_REGION_EDITION_REV0 ||
        @database_type == GEOIP_REGION_EDITION_REV1)
      ip = lookup_ip(hostname)
      ipnum = iptonum(ip)
      pos = seek_record(ipnum)
    else
      throw "Invalid GeoIP database type, can't look up Region by IP"
    end

    unless pos == @database_segments[0]
      read_region(pos, hostname, ip)
    end
  end

  # Search the GeoIP database for the specified host, returning city info.
  #
  # +hostname+ is a String holding the host's DNS name or numeric IP
  # address.
  #
  # Returns a City object with the fourteen elements:
  # * The host or IP address string as requested
  # * The IP address string after looking up the host
  # * The two-character country code (ISO 3166-1 alpha-2)
  # * The three-character country code (ISO 3166-2 alpha-3)
  # * The ISO 3166 English-language name of the country
  # * The two-character continent code
  # * The region name (state or territory)
  # * The city name
  # * The postal code (zipcode)
  # * The latitude
  # * The longitude
  # * The USA dma_code if known (only REV1 City database)
  # * The USA area_code if known (only REV1 City database)
  # * The timezone name, if known
  #
  def city(hostname)
    ip = lookup_ip(hostname)

    if (@database_type == GEOIP_CITY_EDITION_REV0 ||
        @database_type == GEOIP_CITY_EDITION_REV1)
      # Convert numeric IP address to an integer
      ipnum = iptonum(ip)
      pos = seek_record(ipnum)
    elsif (@database_type == GEOIP_CITY_EDITION_REV1_V6)
      ipaddr = IPAddr.new ip
      pos = seek_record_v6(ipaddr.to_i)
    else
      throw "Invalid GeoIP database type, can't look up City by IP"
    end

    # This next statement was added to MaxMind's C version after it was
    # rewritten in Ruby. It prevents unassigned IP addresses from returning
    # bogus data.  There was concern over whether the changes to an
    # application's behaviour were always correct, but this has been tested
    # using an exhaustive search of the top 16 bits of the IP address space.
    # The records where the change takes effect contained *no* valid data. 
    # If you're concerned, email me, and I'll send you the test program so
    # you can test whatever IP range you think is causing problems,
    # as I don't care to undertake an exhaustive search of the 32-bit space.
    unless pos == @database_segments[0]
      read_city(pos, hostname, ip)
    end
  end

  # Search a ISP GeoIP database for the specified host, returning the ISP
  # Not all GeoIP databases contain ISP information.
  # Check http://maxmind.com
  #
  # +hostname+ is a String holding the host's DNS name or numeric IP
  # address.
  #
  # Returns the ISP name.
  #
  def isp(hostname)
    ip = lookup_ip(hostname)

    # Convert numeric IP address to an integer
    ipnum = iptonum(ip)

    if (@database_type != GEOIP_ISP_EDITION &&
        @database_type != GEOIP_ORG_EDITION)
      throw "Invalid GeoIP database type, can't look up Organization/ISP by IP"
    end

    pos = seek_record(ipnum)
    off = pos + (2*@record_length - 1) * @database_segments[0]

    record = atomic_read(MAX_ORG_RECORD_LENGTH, off)
    record = record.sub(/\000.*/n, '')
    record.start_with?('*') ? nil : ISP.new(record)
  end

  # Search a ASN GeoIP database for the specified host, returning the AS
  # number and description.
  #
  # +hostname+ is a String holding the host's DNS name or numeric
  # IP address.
  #
  # Returns the AS number and description.
  #
  # Source:
  # http://geolite.maxmind.com/download/geoip/database/asnum/GeoIPASNum.dat.gz
  #
  def asn(hostname)
    ip = lookup_ip(hostname)

    # Convert numeric IP address to an integer
    ipnum = iptonum(ip)

    if (@database_type != GEOIP_ASNUM_EDITION)
      throw "Invalid GeoIP database type, can't look up ASN by IP"
    end

    pos = seek_record(ipnum)
    off = pos + (2*@record_length - 1) * @database_segments[0]

    record = atomic_read(MAX_ASN_RECORD_LENGTH, off)
    record = record.sub(/\000.*/n, '')

    # AS####, Description
    ASN.new($1, $2) if record =~ /^(AS\d+)\s(.*)$/
  end

  # Search a ISP GeoIP database for the specified host, returning the
  # organization.
  #
  # +hostname+ is a String holding the host's DNS name or numeric
  # IP address.
  #
  # Returns the organization associated with it.
  #
  alias_method(:organization, :isp)  # Untested, according to Maxmind docs this should work

  # Iterate through a GeoIP city database
  def each
    return enum_for unless block_given?

    if (@database_type != GEOIP_CITY_EDITION_REV0 &&
        @database_type != GEOIP_CITY_EDITION_REV1)
      throw "Invalid GeoIP database type, can't iterate thru non-City database"
    end

    @iter_pos = @database_segments[0] + 1
    num = 0

    until ((rec = read_city(@iter_pos)).nil?)
      yield rec
      print "#{num}: #{@iter_pos}\n" if((num += 1) % 1000 == 0)
    end

    @iter_pos = nil
    return self
  end

  private

  # Detects the type of the database.
  def detect_database_type! # :nodoc:
    @file.seek(-3, IO::SEEK_END)

    0.upto(STRUCTURE_INFO_MAX_SIZE - 1) do |i|
      if @file.read(3).bytes.all? { |byte| byte == 255 }
        @database_type = if @file.respond_to?(:getbyte)
                           @file.getbyte
                         else
                           @file.getc
                         end

        @database_type -= 105 if @database_type >= 106

        if (@database_type == GEOIP_REGION_EDITION_REV0)
          # Region Edition, pre June 2003
          @database_segments = [STATE_BEGIN_REV0]
        elsif (@database_type == GEOIP_REGION_EDITION_REV1)
          # Region Edition, post June 2003
          @database_segments = [STATE_BEGIN_REV1]
        elsif (@database_type == GEOIP_CITY_EDITION_REV0 ||
               @database_type == GEOIP_CITY_EDITION_REV1 ||
               @database_type == GEOIP_CITY_EDITION_REV1_V6 ||
               @database_type == GEOIP_ORG_EDITION ||
               @database_type == GEOIP_ISP_EDITION ||
               @database_type == GEOIP_ASNUM_EDITION)

          # City/Org Editions have two segments, read offset of second segment
          @database_segments = [0]
          sr = @file.read(3).unpack("C*")
          @database_segments[0] += le_to_ui(sr)

          if (@database_type == GEOIP_ORG_EDITION ||
              @database_type == GEOIP_ISP_EDITION)
            @record_length = 4
          end
        end

        break
      else
        @file.seek(-4, IO::SEEK_CUR)
      end
    end

    if (@database_type == GEOIP_COUNTRY_EDITION ||
        @database_type == GEOIP_PROXY_EDITION ||
        @database_type == GEOIP_COUNTRY_EDITION_V6 ||
        @database_type == GEOIP_NETSPEED_EDITION)
      @database_segments = [COUNTRY_BEGIN]
    end
  end

  def read_region(pos, hostname = '', ip = '') #:nodoc:
    if (@database_type == GEOIP_REGION_EDITION_REV0)
      pos -= STATE_BEGIN_REV0
      if (pos >= 1000)
        code = 225
        region_code = ((pos - 1000) / 26 + 65).chr + ((pos - 1000) % 26 + 65).chr
      else
        code = pos
        region_code = ''
      end
    elsif (@database_type == GEOIP_REGION_EDITION_REV1)
      pos -= STATE_BEGIN_REV1
      if (pos < US_OFFSET)
        code = 0
        region_code = ''
      elsif (pos < CANADA_OFFSET)
        code = 225
        region_code = ((pos - US_OFFSET) / 26 + 65).chr + ((pos - US_OFFSET) % 26 + 65).chr
      elsif (pos < WORLD_OFFSET)
        code = 38
        region_code = ((pos - CANADA_OFFSET) / 26 + 65).chr + ((pos - CANADA_OFFSET) % 26 + 65).chr
      else
        code = (pos - WORLD_OFFSET) / FIPS_RANGE
        region_code = ''
      end
    end

    Region.new(
      hostname,
      ip,
      CountryCode[code],          # ISO3166-1 alpha-2 code
      CountryCode3[code],         # ISO3166-2 alpha-3 code
      CountryName[code],          # Country name, per ISO 3166
      CountryContinent[code],     # Continent code.
      region_code,		  # Unfortunately this is called region_name in the City structure
      lookup_region_name(CountryCode[code], region_code),
      (TimeZone["#{CountryCode[code]}#{region_code}"] || TimeZone["#{CountryCode[code]}"])
    )
  end

  def lookup_region_name(country_iso2, region_code)
    country_regions = RegionName[country_iso2]
    country_regions && country_regions[region_code]
  end

  # Search the GeoIP database for the specified host, returning city info.
  #
  # +hostname+ is a String holding the host's DNS name or numeric
  # IP address.
  #
  # Returns an array of fourteen elements:
  # * All elements from the country query (except GeoIP's country code,
  #   bah!)
  # * The region (state or territory) name
  # * The city name
  # * The postal code (zipcode)
  # * The latitude
  # * The longitude
  # * The dma_code and area_code, if available (REV1 City database)
  # * The timezone name, if known
  #
  def read_city(pos, hostname = '', ip = '') #:nodoc:
    off = pos + (2*@record_length - 1) * @database_segments[0]
    record = atomic_read(FULL_RECORD_LENGTH, off)

    return unless (record && record.size == FULL_RECORD_LENGTH)

    # The country code is the first byte:
    code = record[0]
    code = code.ord if code.respond_to?(:ord)
    record = record[1..-1]
    @iter_pos += 1 unless @iter_pos.nil?

    spl = record.split("\x00", 4)
    # Get the region code:
    region_code = spl[0]
    @iter_pos += (region_code.size + 1) unless @iter_pos.nil?

    # Get the city:
    city = spl[1]
    @iter_pos += (city.size + 1) unless @iter_pos.nil?
    # set the correct encoding in ruby 1.9 compatible environments:
    city.force_encoding('iso-8859-1') if city.respond_to?(:force_encoding)

    # Get the postal code:
    postal_code = spl[2]
    @iter_pos += (postal_code.size + 1) unless @iter_pos.nil? || postal_code.nil?

    record = spl[3]

    # Get the latitude/longitude:
    if (record && record[0,3])
      latitude  = (le_to_ui(record[0,3].unpack('C*')) / 10000.0) - 180
      record = record[3..-1]

      @iter_pos += 3 unless @iter_pos.nil?
    else
      latitude = ''
    end

    if (record && record[0,3])
      longitude = le_to_ui(record[0,3].unpack('C*')) / 10000.0 - 180
      record = record[3..-1]

      @iter_pos += 3 unless @iter_pos.nil?
    else
      longitude = ''
    end

    # UNTESTED
    if (record &&
        record[0,3] &&
        @database_type == GEOIP_CITY_EDITION_REV1 &&
        CountryCode[code] == "US")

      dmaarea_combo = le_to_ui(record[0,3].unpack('C*'))
      dma_code = (dmaarea_combo / 1000)
      area_code = (dmaarea_combo % 1000)

      @iter_pos += 3 unless @iter_pos.nil?
    else
      dma_code, area_code = nil, nil
    end

    City.new(
      hostname,                   # Requested hostname
      ip,                         # Ip address as dotted quad
      CountryCode[code],          # ISO3166-1 code
      CountryCode3[code],         # ISO3166-2 code
      CountryName[code],          # Country name, per IS03166
      CountryContinent[code],     # Continent code.
      region_code,                # Region code (called region_name, unfortunately)
      city,                       # City name
      postal_code,                # Postal code
      latitude,
      longitude,
      dma_code,
      area_code,
      (TimeZone["#{CountryCode[code]}#{region_code}"] || TimeZone["#{CountryCode[code]}"]),
      lookup_region_name(CountryCode[code], region_code)  # Real region name
    )
  end

  def lookup_ip(ip_or_hostname) # :nodoc:
    if is_local?(ip_or_hostname) && @local_ip_alias
      ip_or_hostname = @local_ip_alias
    end

    if !ip_or_hostname.kind_of?(String) or ip_or_hostname =~ /^[0-9.]+$/
      return ip_or_hostname
    end

    # Lookup IP address, we were given a name or IPv6 address
    ip = IPSocket.getaddress(ip_or_hostname)
    ip = '0.0.0.0' if ip == '::1'
    ip
  end

  def is_local?(ip_or_hostname) #:nodoc:
    ["127.0.0.1", "localhost", "::1", "0000::1", "0:0:0:0:0:0:0:1"].include? ip_or_hostname
  end

  # Convert numeric IP address to Integer.
  def iptonum(ip) #:nodoc:
    if (ip.kind_of?(String) &&
        ip =~ /^([0-9]+)\.([0-9]+)\.([0-9]+)\.([0-9]+)$/)
      ip = be_to_ui(Regexp.last_match().to_a.slice(1..4))
    else
      ip = ip.to_i
    end

    return ip
  end

  def seek_record(ipnum) #:nodoc:
    # Binary search in the file.
    # Records are pairs of little-endian integers, each of @record_length.
    offset = 0
    mask = 0x80000000

    31.downto(0) do |depth|
      off = (@record_length * 2 * offset)
      buf = atomic_read(@record_length * 2, off)

      buf.slice!(0...@record_length) if ((ipnum & mask) != 0)
      offset = le_to_ui(buf[0...@record_length].unpack("C*"))

      if (offset >= @database_segments[0])
        return offset
      end

      mask >>= 1
    end
  end

  def seek_record_v6(ipnum)

    # Binary search in the file.
    # Records are pairs of little-endian integers, each of @record_length.
    offset = 0
    mask = 1 << 127

    127.downto(0) do |depth|
      off = (@record_length * 2 * offset)
      buf = atomic_read(@record_length * 2, off)

      buf.slice!(0...@record_length) if ((ipnum & mask) != 0)
      offset = le_to_ui(buf[0...@record_length].unpack("C*"))

      if (offset >= @database_segments[0])
        return offset
      end

      mask >>= 1
    end

  end

  # Convert a big-endian array of numeric bytes to unsigned int.
  #
  # Returns the unsigned Integer.
  #
  def be_to_ui(s) #:nodoc:
    i = 0

    s.each { |b| i = ((i << 8) | (b.to_i & 0x0ff)) }
    return i
  end

  # Same for little-endian
  def le_to_ui(s) #:nodoc:
    be_to_ui(s.reverse)
  end

  # reads +length+ bytes from +offset+ as atomically as possible
  # if IO.pread is available, it'll use that (making it both multithread
  # and multiprocess-safe). Otherwise we'll use a mutex to synchronize
  # access (only providing protection against multiple threads, but not
  # file descriptors shared across multiple processes).
  def atomic_read(length, offset) #:nodoc:
    if @mutex
      @mutex.synchronize do
        @file.seek(offset)
        @file.read(length)
      end
    else
      IO.pread(@file.fileno, length, offset)
    end
  end

end
