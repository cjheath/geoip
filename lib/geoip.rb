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
  VERSION = "1.6.4"

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
  GEOIP_NETSPEED_EDITION_REV1 = 32

  # Editions list updated from the C API, August 2014:
  module Edition
    COUNTRY = 1
    REGION_REV0 = 7
    CITY_REV0 = 6
    ORG = 5
    ISP = 4
    CITY_REV1 = 2
    REGION_REV1 = 3
    PROXY = 8
    ASNUM = 9
    NETSPEED = 10
    DOMAIN = 11
    COUNTRY_V6 = 12
    LOCATIONA = 13
    ACCURACYRADIUS = 14
    CITYCONFIDENCE = 15             # unsupported
    CITYCONFIDENCEDIST = 16         # unsupported
    LARGE_COUNTRY = 17
    LARGE_COUNTRY_V6 = 18
    CITYCONFIDENCEDIST_ISP_ORG = 19 # unused, but gaps are not allowed
    CCM_COUNTRY = 20                # unused, but gaps are not allowed 
    ASNUM_V6 = 21
    ISP_V6 = 22
    ORG_V6 = 23
    DOMAIN_V6 = 24
    LOCATIONA_V6 = 25
    REGISTRAR = 26
    REGISTRAR_V6 = 27
    USERTYPE = 28
    USERTYPE_V6 = 29
    CITY_REV1_V6 = 30
    CITY_REV0_V6 = 31
    NETSPEED_REV1 = 32
    NETSPEED_REV1_V6 = 33
    COUNTRYCONF = 34
    CITYCONF = 35
    REGIONCONF = 36
    POSTALCONF = 37
    ACCURACYRADIUS_V6 = 38
  end

  # Numeric codes for NETSPEED (NETSPEED_REV1* is string-based):
  GEOIP_UNKNOWN_SPEED = 0
  GEOIP_DIALUP_SPEED = 1
  GEOIP_CABLEDSL_SPEED = 2
  GEOIP_CORPORATE_SPEED = 3

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
  # +options+ is a Hash allowing you to specify the caching options
  #
  def initialize(filename, options = {})
    if options[:preload] || !IO.respond_to?(:pread)
      @mutex = Mutex.new
    end

    @use_pread = IO.respond_to?(:pread) && !options[:preload]
    @contents = nil
    @iter_pos = nil
    @options = options
    @database_type = Edition::COUNTRY
    @record_length = STANDARD_RECORD_LENGTH
    @file = File.open(filename, 'rb')

    detect_database_type!

    preload_data if options[:preload]
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
    case @database_type
    when Edition::CITY_REV0, Edition::CITY_REV1, Edition::CITY_REV1_V6
      city(hostname)

    when Edition::REGION_REV0, Edition::REGION_REV1
      region(hostname)

    when Edition::NETSPEED, Edition::NETSPEED_REV1
      netspeed(hostname)

    when Edition::COUNTRY, Edition::PROXY, Edition::COUNTRY_V6
      ip = lookup_ip(hostname)
      if @ip_bits > 32
        ipaddr = IPAddr.new ip
        code = (seek_record(ipaddr.to_i) - COUNTRY_BEGIN)
      else
        # Convert numeric IP address to an integer
        ipnum = iptonum(ip)
        code = (seek_record(ipnum) - @database_segments[0])
      end
      read_country(code, hostname, ip)
    else
      throw "Invalid GeoIP database type #{@database_type}, can't look up Country by IP"
    end
  end

  # Search a GeoIP Connection Type (Netspeed) database for the specified host,
  # returning the speed code.
  #
  # +hostname+ is a String holding the host's DNS name or numeric IP address.
  def netspeed(hostname)
    unless (@database_type == Edition::NETSPEED ||
        @database_type == Edition::NETSPEED_REV1)
      throw "Invalid GeoIP database type #{@database_type}, can't look up Netspeed by IP"
    end
    # Convert numeric IP address to an integer
    ip = lookup_ip(hostname)
    ipnum = iptonum(ip)
    pos = seek_record(ipnum)
    read_netspeed(pos-@database_segments[0])
  end

  # Search the GeoIP database for the specified host, returning region info.
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
    if (@database_type == Edition::CITY_REV0 ||
        @database_type == Edition::CITY_REV1 ||
        @database_type == Edition::CITY_REV1_V6)
      return city(hostname)
    end

    if (@database_type == Edition::REGION_REV0 ||
        @database_type == Edition::REGION_REV1)
      ip = lookup_ip(hostname)
      ipnum = iptonum(ip)
      pos = seek_record(ipnum)
    else
      throw "Invalid GeoIP database type, can't look up Region by IP"
    end

    if pos == @database_segments[0]
      nil
    else
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

    if (@database_type == Edition::CITY_REV0 ||
        @database_type == Edition::CITY_REV1)
      # Convert numeric IP address to an integer
      ipnum = iptonum(ip)
      pos = seek_record(ipnum)
    elsif (@database_type == Edition::CITY_REV1_V6)
      ipaddr = IPAddr.new ip
      pos = seek_record(ipaddr.to_i)
    else
      throw "Invalid GeoIP database type, can't look up City by IP"
    end

    read_city(pos-@database_segments[0], hostname, ip)
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

    case @database_type
    when Edition::ORG,
     Edition::ISP,
     Edition::DOMAIN,
     Edition::ASNUM,
     Edition::ACCURACYRADIUS,
     Edition::NETSPEED,
     Edition::USERTYPE,
     Edition::REGISTRAR,
     Edition::LOCATIONA,
     Edition::CITYCONF,
     Edition::COUNTRYCONF,
     Edition::REGIONCONF,
     Edition::POSTALCONF
      pos = seek_record(ipnum)
      read_isp(pos-@database_segments[0])
    else
      throw "Invalid GeoIP database type, can't look up Organization/ISP by IP"
    end
  end

  # Search a ASN GeoIP database for the specified host, returning the AS
  # number and description.
  #
  # Many other types of GeoIP database (e.g. userType) mis-identify as ASN type,
  # and this can read those too.
  #
  # +hostname+ is a String holding the host's DNS name or numeric IP address.
  #
  # Returns the AS number and description.
  #
  # Source:
  # http://geolite.maxmind.com/download/geoip/database/asnum/GeoIPASNum.dat.gz
  #
  def asn(hostname)
    ip = lookup_ip(hostname)

    if (@database_type == Edition::ASNUM)
      # Convert numeric IP address to an integer
      ipnum = iptonum(ip)
      pos = seek_record(ipnum)
    elsif (@database_type == Edition::ASNUM_V6)
      ipaddr = IPAddr.new ip
      pos = seek_record(ipaddr.to_i)
    else
      throw "Invalid GeoIP database type #{@database_type}, can't look up ASN by IP"
    end

    read_asn(pos-@database_segments[0])
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

  # Iterate through a GeoIP city database by 
  def each
    return enum_for unless block_given?

    if (@database_type != Edition::CITY_REV0 &&
        @database_type != Edition::CITY_REV1)
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

  # Call like this, for example:
  # GeoIP.new('GeoIPNetSpeedCell.dat').each{|*a| puts("0x%08X\t%d" % a)}
  # or:
  # GeoIP.new('GeoIPv6.dat').each{|*a| puts("0x%032X\t%d" % a)}
  def each_by_ip offset = 0, ipnum = 0, mask = nil, &callback
    mask ||= 1 << (@ip_bits-1)

    # Read the two pointers and split them:
    record2 = atomic_read(@record_length*2, @record_length*2*offset)
    record1 = record2.slice!(0, @record_length)

    # Traverse the left tree
    off1 = le_to_ui(record1.unpack('C*'))
    val = off1 - @database_segments[0]
    if val >= 0
      yield(ipnum, val > 0 ? read_record(ipnum.to_s, ipnum, val) : nil) 
    elsif mask != 0
      each_by_ip(off1, ipnum, mask >> 1, &callback)
    end

    # Traverse the right tree
    off2 = le_to_ui(record2.unpack('C*'))
    val = off2 - @database_segments[0]
    if val >= 0
      yield(ipnum|mask, val > 0 ? read_record(ipnum.to_s, ipnum, val) : nil)
    elsif mask != 0
      each_by_ip(off2, ipnum|mask, mask >> 1, &callback)
    end
  end

  private

  def read_record hostname, ip, offset
    case @database_type
    when Edition::CITY_REV0, Edition::CITY_REV1, Edition::CITY_REV1_V6
      read_city(offset, hostname, ip)

    when Edition::REGION_REV0, Edition::REGION_REV1
      read_region(offset+@database_segments[0], hostname, ip)

    when Edition::NETSPEED, Edition::NETSPEED_REV1
      read_netspeed(offset)

    when Edition::COUNTRY, Edition::PROXY, Edition::COUNTRY_V6
      read_country(offset, hostname, ip)

    when Edition::ASNUM, Edition::ASNUM_V6
      read_asn(offset)

    # Add new types here
    when Edition::ISP, Edition::ORG
      read_isp offset

    else
      #raise "Unsupported GeoIP database type #{@database_type}"
      offset
    end
  end

  # Loads data into a StringIO which is Copy-on-write friendly
  def preload_data
    @file.seek(0)
    @contents = StringIO.new(@file.read)
    @file.close
  end

  # Detects the type of the database.
  def detect_database_type! # :nodoc:
    @file.seek(-3, IO::SEEK_END)
    @ip_bits = 32

    0.upto(STRUCTURE_INFO_MAX_SIZE - 1) do |i|
      if @file.read(3).bytes.all? { |byte| byte == 255 }
        @database_type =
          if @file.respond_to?(:getbyte)
            @file.getbyte
          else
            @file.getc
          end

        @database_type -= 105 if @database_type >= 106

        if (@database_type == Edition::REGION_REV0)
          # Region Edition, pre June 2003
          @database_segments = [STATE_BEGIN_REV0]
        elsif (@database_type == Edition::REGION_REV1)
          # Region Edition, post June 2003
          @database_segments = [STATE_BEGIN_REV1]
        elsif @database_type == Edition::CITY_REV0 ||
               @database_type == Edition::CITY_REV1 ||
               @database_type == Edition::ORG ||
               @database_type == Edition::ORG_V6 ||
               @database_type == Edition::ISP ||
               @database_type == Edition::ISP_V6 ||
               @database_type == Edition::REGISTRAR ||
               @database_type == Edition::REGISTRAR_V6 ||
               @database_type == Edition::USERTYPE ||     # Many of these files mis-identify as ASNUM files
               @database_type == Edition::USERTYPE_V6 ||
               @database_type == Edition::DOMAIN ||
               @database_type == Edition::DOMAIN_V6 ||
               @database_type == Edition::ASNUM ||
               @database_type == Edition::ASNUM_V6 ||
               @database_type == Edition::NETSPEED_REV1 ||
               @database_type == Edition::NETSPEED_REV1_V6 ||
               @database_type == Edition::LOCATIONA ||
               # @database_type == Edition::LOCATIONA_V6 ||
               @database_type == Edition::ACCURACYRADIUS ||
               @database_type == Edition::ACCURACYRADIUS_V6 ||
               @database_type == Edition::CITYCONF ||
               @database_type == Edition::COUNTRYCONF ||
               @database_type == Edition::REGIONCONF ||
               @database_type == Edition::POSTALCONF ||
               @database_type == Edition::CITY_REV0_V6 ||
               @database_type == Edition::CITY_REV1_V6

          # City/Org Editions have two segments, read offset of second segment
          @database_segments = [0]
          sr = @file.read(3).unpack("C*")
          @database_segments[0] += le_to_ui(sr)

        end

        case @database_type
        when Edition::COUNTRY
        when Edition::NETSPEED_REV1
        when Edition::ASNUM
        when Edition::CITY_REV0
        when Edition::CITY_REV1
        when Edition::REGION_REV0
        when Edition::REGION_REV1
          @ip_bits = 32
          @record_length = 3

        when Edition::ORG,
            Edition::DOMAIN,
            Edition::ISP
          @ip_bits = 32
          @record_length = 4

        when Edition::ASNUM_V6,
            Edition::CITY_REV0_V6,
            Edition::CITY_REV1_V6,
            Edition::NETSPEED_REV1_V6,
            Edition::COUNTRY_V6,
            Edition::PROXY
          @ip_bits = 128
          @record_length = 3

        when Edition::ACCURACYRADIUS_V6,
            Edition::DOMAIN_V6,
            Edition::ISP_V6,
            Edition::LARGE_COUNTRY_V6,
            Edition::LOCATIONA_V6,
            Edition::ORG_V6,
            Edition::REGISTRAR_V6,
            Edition::USERTYPE_V6
          @ip_bits = 128
          @record_length = 4

        else
          raise "unimplemented database type"
        end

        break
      else
        @file.seek(-4, IO::SEEK_CUR)
      end
    end

    if (@database_type == Edition::COUNTRY ||
        @database_type == Edition::PROXY ||
        @database_type == Edition::COUNTRY_V6 ||
        @database_type == Edition::NETSPEED)
      @database_segments = [COUNTRY_BEGIN]
    end

    # puts "Detected IPv#{@ip_bits == 32 ? '4' : '6'} database_type #{@database_type} with #{@database_segments[0]} records of length #{@record_length} (data starts at #{@database_segments[0]*@record_length*2})"
  end

  def read_country code, hostname, ip
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

  def read_region(pos, hostname = '', ip = '') #:nodoc:
    if (@database_type == Edition::REGION_REV0)
      pos -= STATE_BEGIN_REV0
      if (pos >= 1000)
        code = 225
        region_code = ((pos - 1000) / 26 + 65).chr + ((pos - 1000) % 26 + 65).chr
      else
        code = pos
        region_code = ''
      end
    elsif (@database_type == Edition::REGION_REV1)
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
      region_code,                # Unfortunately this is called region_name in the City structure
      lookup_region_name(CountryCode[code], region_code),
      (TimeZone["#{CountryCode[code]}#{region_code}"] || TimeZone["#{CountryCode[code]}"])
    )
  end

  def read_asn offset
    return nil if offset == 0
    record = atomic_read(MAX_ASN_RECORD_LENGTH, index_size+offset)
    record.slice!(record.index("\0")..-1)

    # AS####, Description
    if record =~ /^(AS\d+)(?:\s(.*))?$/
      # set the correct encoding in ruby 1.9 compatible environments:
      asn = $2.respond_to?(:force_encoding) ? $2.force_encoding('iso-8859-1').encode('utf-8') : $2
      ASN.new($1, asn)
    else
      record
    end
  end

  def read_netspeed(offset)
    return offset if @database_type == Edition::NETSPEED  # Numeric value
    return nil if offset == 0

    record = atomic_read(20, index_size+offset)
    record.slice!(record.index("\0")..-1)
    record
  end

  def read_isp offset
    record = atomic_read(MAX_ORG_RECORD_LENGTH, index_size+offset)
    record = record.sub(/\000.*/n, '')
    record = record.force_encoding('iso-8859-1').encode('utf-8') if record.respond_to?(:force_encoding)
    record.start_with?('*') ? nil : ISP.new(record)
  end

  # Size of the database index (a binary tree of depth <= @ip_bits)
  def index_size
    2 * @record_length * @database_segments[0]
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
  def read_city(offset, hostname = '', ip = '') #:nodoc:
    return nil if offset == 0
    record = atomic_read(FULL_RECORD_LENGTH, offset+index_size)
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
    city = city.force_encoding('iso-8859-1').encode('utf-8') if city.respond_to?(:force_encoding)

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
        @database_type == Edition::CITY_REV1 &&
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
    mask = 1 << (@ip_bits-1)

    @ip_bits.downto(1) do |depth|
      go_right = (ipnum & mask) != 0
      off = @record_length * (2 * offset + (go_right ? 1 : 0))
      offset = le_to_ui(atomic_read(@record_length, off).unpack('C*'))

      return offset if offset >= @database_segments[0]
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

  # reads +length+ bytes from +pos+ as atomically as possible
  # if IO.pread is available, it'll use that (making it both multithread
  # and multiprocess-safe). Otherwise we'll use a mutex to synchronize
  # access (only providing protection against multiple threads, but not
  # file descriptors shared across multiple processes).
  # If the contents of the database have been preloaded it'll work with
  # the StringIO object directly.
  def atomic_read(length, pos) #:nodoc:
    if @mutex
      @mutex.synchronize { atomic_read_unguarded(length, pos) }
    else
      atomic_read_unguarded(length, pos)
    end
  end

  def atomic_read_unguarded(length, pos)
    if @use_pread
      IO.pread(@file.fileno, length, pos)
    else
      io = @contents || @file
      io.seek(pos)
      io.read(length)
    end
  end
end
