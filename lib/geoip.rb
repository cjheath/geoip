#
# Native Ruby reader for the GeoIP database
# Lookup the country where IP address is allocated
#
#= COPYRIGHT
# This version Copyright (C) 2005 Clifford Heath
# Derived from the C version, Copyright (C) 2003 MaxMind LLC
#
# This library is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public
# License as published by the Free Software Foundation; either
# version 2.1 of the License, or (at your option) any later version.
#
# This library is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public
# License along with this library; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
#
#= SYNOPSIS
#
#   require 'geoip'
#   p GeoIP.new('/usr/share/GeoIP/GeoIP.dat').country("www.netscape.sk")
#
#= DESCRIPTION
#
# GeoIP searches a GeoIP database for a given host or IP address, and
# returns information about the country where the IP address is allocated.
#
#= PREREQUISITES
#
# You need at least the free GeoIP.dat, for which the last known download
# location is <http://www.maxmind.com/download/geoip/database/GeoIP.dat.gz>
# This API requires the file to be decompressed for searching. Other versions
# of this database are available for purchase which contain more detailed
# information, but this information is not returned by this implementation.
# See www.maxmind.com for more information.
#
#=end
require 'thread'  # Needed for Mutex
require 'socket'
begin
  require 'io/extra' # for IO.pread
rescue LoadError
  # oh well, hope they're not forking after initializing
end

require 'yaml'

class GeoIP
    # The GeoIP GEM version number
    VERSION = "1.0.0"

    # The data/ directory for geoip
    DATA_DIR = File.expand_path(File.join(File.dirname(__FILE__),'..','data','geoip'))

    # Ordered list of the ISO3166 2-character country codes, ordered by GeoIP ID
    CountryCode = YAML.load_file(File.join(DATA_DIR,'country_code.yml'))

    # Ordered list of the ISO3166 3-character country codes, ordered by GeoIP ID
    CountryCode3 = YAML.load_file(File.join(DATA_DIR,'country_code3.yml'))

    # Ordered list of the English names of the countries, ordered by GeoIP ID
    CountryName = YAML.load_file(File.join(DATA_DIR,'country_name.yml'))

    # Ordered list of the ISO3166 2-character continent code of the countries, ordered by GeoIP ID
    CountryContinent = YAML.load_file(File.join(DATA_DIR,'country_continent.yml'))

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

    # The Edition number that identifies which kind of database you've opened
    attr_reader :databaseType

    # Open the GeoIP database and determine the file format version
    #
    # +filename+ is a String holding the path to the GeoIP.dat file
    # +options+ is an integer holding caching flags (unimplemented)
    def initialize(filename, flags = 0)
        @mutex = IO.respond_to?(:pread) ? false : Mutex.new
        @flags = flags
        @databaseType = GEOIP_COUNTRY_EDITION
        @record_length = STANDARD_RECORD_LENGTH
        @file = File.open(filename, 'rb')
        @file.seek(-3, IO::SEEK_END)
        0.upto(STRUCTURE_INFO_MAX_SIZE-1) { |i|
            if @file.read(3).bytes.all?{|byte| 255 == byte}
                @databaseType = @file.respond_to?(:getbyte) ? @file.getbyte : @file.getc
                @databaseType -= 105 if @databaseType >= 106

                if (@databaseType == GEOIP_REGION_EDITION_REV0)
                    # Region Edition, pre June 2003
                    @databaseSegments = [ STATE_BEGIN_REV0 ]
                elsif (@databaseType == GEOIP_REGION_EDITION_REV1)
                    # Region Edition, post June 2003
                    @databaseSegments = [ STATE_BEGIN_REV1 ]
                elsif (@databaseType == GEOIP_CITY_EDITION_REV0 ||
                       @databaseType == GEOIP_CITY_EDITION_REV1 ||
                       @databaseType == GEOIP_ORG_EDITION ||
                       @databaseType == GEOIP_ISP_EDITION ||
                       @databaseType == GEOIP_ASNUM_EDITION)
                    # City/Org Editions have two segments, read offset of second segment
                    @databaseSegments = [ 0 ]
                    sr = @file.read(3).unpack("C*")
                    @databaseSegments[0] += le_to_ui(sr)

                    if (@databaseType == GEOIP_ORG_EDITION ||
                        @databaseType == GEOIP_ISP_EDITION)
                        @record_length = 4
                    end
                end
                break

            else
                @file.seek(-4, IO::SEEK_CUR)
            end
        }
        if (@databaseType == GEOIP_COUNTRY_EDITION ||
            @databaseType == GEOIP_PROXY_EDITION ||
            @databaseType == GEOIP_NETSPEED_EDITION)
            @databaseSegments = [ COUNTRY_BEGIN ]
        end
    end

    # Search the GeoIP database for the specified host, returning country info
    #
    # +hostname+ is a String holding the host's DNS name or numeric IP address.
    # If the database is a City database (normal), return the result that +city+ would return.
    # Otherwise, return an array of seven elements:
    # * The host or IP address string as requested
    # * The IP address string after looking up the host
    # * The GeoIP country-ID as an integer (N.B. this is excluded from the city results!)
    # * The two-character country code (ISO 3166-1 alpha-2)
    # * The three-character country code (ISO 3166-2 alpha-3)
    # * The ISO 3166 English-language name of the country
    # * The two-character continent code
    #
    # The array has been extended with methods listed in GeoIP::CountryAccessors.ACCESSORS:
    # request, ip, country_code, country_code2, country_code3, country_name, continent_code.
    # In addition, +to_hash+ provides a symbol-keyed hash for the above values.
    #
    def country(hostname)
        if (@databaseType == GEOIP_CITY_EDITION_REV0 ||
            @databaseType == GEOIP_CITY_EDITION_REV1)
            return city(hostname)
        end

        ip = hostname
        if ip.kind_of?(String) && ip !~ /^[0-9.]*$/
            # Lookup IP address, we were given a name
            ip = IPSocket.getaddress(hostname)
            ip = '0.0.0.0' if ip == '::1'
        end

        # Convert numeric IP address to an integer
        ipnum = iptonum(ip)
        if (@databaseType != GEOIP_COUNTRY_EDITION &&
            @databaseType != GEOIP_PROXY_EDITION &&
            @databaseType != GEOIP_NETSPEED_EDITION)
            throw "Invalid GeoIP database type, can't look up Country by IP"
        end
        code = seek_record(ipnum) - COUNTRY_BEGIN;
        [   hostname,                   # Requested hostname
            ip,                         # Ip address as dotted quad
            code,                       # GeoIP's country code
            CountryCode[code],          # ISO3166-1 alpha-2 code
            CountryCode3[code],         # ISO3166-2 alpha-3 code
            CountryName[code],          # Country name, per ISO 3166
            CountryContinent[code]      # Continent code.
        ].extend(CountryAccessors)
    end

    # Search the GeoIP database for the specified host, returning city info.
    #
    # +hostname+ is a String holding the host's DNS name or numeric IP address.
    # Return an array of fourteen elements:
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
    # The array has been extended with methods listed in GeoIP::CityAccessors.ACCESSORS:
    # request, ip, country_code2, country_code3, country_name, continent_code,
    # region_name, city_name, postal_code, latitude, longitude, dma_code, area_code, timezone.
    # In addition, +to_hash+ provides a symbol-keyed hash for the above values.
    #
    def city(hostname)
        ip = hostname
        if ip.kind_of?(String) && ip !~ /^[0-9.]*$/
            # Lookup IP address, we were given a name
            ip = IPSocket.getaddress(hostname)
            ip = '0.0.0.0' if ip == '::1'
        end

        # Convert numeric IP address to an integer
        ipnum = iptonum(ip)
        if (@databaseType != GEOIP_CITY_EDITION_REV0 &&
            @databaseType != GEOIP_CITY_EDITION_REV1)
            throw "Invalid GeoIP database type, can't look up City by IP"
        end
        pos = seek_record(ipnum);
        # This next statement was added to MaxMind's C version after it was rewritten in Ruby.
        # It prevents unassigned IP addresses from returning bogus data.  There was concern over
        # whether the changes to an application's behaviour were always correct, but this has been
        # tested using an exhaustive search of the top 16 bits of the IP address space.  The records
        # where the change takes effect contained *no* valid data.  If you're concerned, email me,
        # and I'll send you the test program so you can test whatever IP range you think is causing
        # problems, as I don't care to undertake an exhaustive search of the 32-bit space.
        return nil if pos == @databaseSegments[0]
        read_city(pos, hostname, ip).extend(CityAccessors)
    end

    # Search a ISP GeoIP database for the specified host, returning the ISP
    # Not all GeoIP databases contain ISP information. Check http://maxmind.com
    #
    # +hostname+ is a String holding the host's DNS name or numeric IP address.
    # Return the ISP name
    #
    def isp(hostname)
        ip = hostname
        if ip.kind_of?(String) && ip !~ /^[0-9.]*$/
            # Lookup IP address, we were given a name
            ip = IPSocket.getaddress(hostname)
            ip = '0.0.0.0' if ip == '::1'
        end

        # Convert numeric IP address to an integer
        ipnum = iptonum(ip)
        if (@databaseType != GEOIP_ISP_EDITION &&
            @databaseType != GEOIP_ORG_EDITION)
            throw "Invalid GeoIP database type, can't look up Organization/ISP by IP"
        end
        pos = seek_record(ipnum);
        off = pos + (2*@record_length-1) * @databaseSegments[0]
        record = atomic_read(MAX_ORG_RECORD_LENGTH, off)
        record = record.sub(/\000.*/n, '')
        record
    end

    # Search a ASN GeoIP database for the specified host, returning the AS number + description
    #
    # +hostname+ is a String holding the host's DNS name or numeric IP address.
    # Return the AS number + description
    #
    # Source:
    # http://geolite.maxmind.com/download/geoip/database/asnum/GeoIPASNum.dat.gz
    #
    def asn(hostname)
        ip = hostname
        if ip.kind_of?(String) && ip !~ /^[0-9.]*$/
            # Lookup IP address, we were given a name
            ip = IPSocket.getaddress(hostname)
            ip = '0.0.0.0' if ip == '::1'
        end

        # Convert numeric IP address to an integer
        ipnum = iptonum(ip)
        if (@databaseType != GEOIP_ASNUM_EDITION)
            throw "Invalid GeoIP database type, can't look up ASN by IP"
        end
        pos = seek_record(ipnum);
        off = pos + (2*@record_length-1) * @databaseSegments[0]
        record = atomic_read(MAX_ASN_RECORD_LENGTH, off)
        record = record.sub(/\000.*/n, '')

        if record =~ /^(AS\d+)\s(.*)$/
          # AS####, Description
          return [$1, $2].extend(ASNAccessors)
        end
    end

    # Search a ISP GeoIP database for the specified host, returning the organization
    #
    # +hostname+ is a String holding the host's DNS name or numeric IP address.
    # Return the organization associated with it
    #
    alias_method(:organization, :isp)     # Untested, according to Maxmind docs this should work

    # Iterate through a GeoIP city database
    def each
        if (@databaseType != GEOIP_CITY_EDITION_REV0 &&
            @databaseType != GEOIP_CITY_EDITION_REV1)
            throw "Invalid GeoIP database type, can't iterate thru non-City database"
        end

        @iter_pos = @databaseSegments[0] + 1
        num = 0
        until((rec = read_city(@iter_pos)).nil?)
            yield(rec)
            print "#{num}: #{@iter_pos}\n" if((num += 1) % 1000 == 0)
        end
        @iter_pos = nil
        self
    end

    private

    # Search the GeoIP database for the specified host, returning city info
    #
    # +hostname+ is a String holding the host's DNS name or numeric IP address
    # Return an array of fourteen elements:
    # * All elements from the country query (except GeoIP's country code, bah!)
    # * The region (state or territory) name
    # * The city name
    # * The postal code (zipcode)
    # * The latitude
    # * The longitude
    # * The dma_code and area_code, if available (REV1 City database)
    # * The timezone name, if known
    def read_city(pos, hostname = '', ip = '')  #:nodoc:
        off = pos + (2*@record_length-1) * @databaseSegments[0]
        record = atomic_read(FULL_RECORD_LENGTH, off)
        return nil unless record && record.size == FULL_RECORD_LENGTH

        # The country code is the first byte:
        code = record[0]
        code = code.ord if code.respond_to?(:ord)
        record = record[1..-1]
        @iter_pos += 1 unless @iter_pos.nil?

        spl = record.split("\x00", 4)
        # Get the region:
        region = spl[0]
        @iter_pos += (region.size + 1) unless @iter_pos.nil?

        # Get the city:
        city = spl[1]
        @iter_pos += (city.size + 1) unless @iter_pos.nil?
        # set the correct encoding in ruby 1.9 compatible environments:
        city.force_encoding('iso-8859-1') if city.respond_to?(:force_encoding)

        # Get the postal code:
        postal_code = spl[2]
        @iter_pos += (postal_code.size + 1) unless @iter_pos.nil?

        record = spl[3]
        # Get the latitude/longitude:
        if(record && record[0,3]) then
            latitude  = le_to_ui(record[0,3].unpack('C*')) / 10000.0 - 180
            record = record[3..-1]
            @iter_pos += 3 unless @iter_pos.nil?
        else
            latitude = ''
        end
        if(record && record[0,3]) then
            longitude = le_to_ui(record[0,3].unpack('C*')) / 10000.0 - 180
            record = record[3..-1]
            @iter_pos += 3 unless @iter_pos.nil?
        else
            longitude = ''
        end

        if (record &&
                record[0,3] &&
                @databaseType == GEOIP_CITY_EDITION_REV1 &&
                CountryCode[code] == "US")      # UNTESTED
            dmaarea_combo = le_to_ui(record[0,3].unpack('C*'))
            dma_code = dmaarea_combo / 1000;
            area_code = dmaarea_combo % 1000;
            @iter_pos += 3 unless @iter_pos.nil?
        else
            dma_code, area_code = nil, nil
        end

        [   hostname,                   # Requested hostname
            ip,                         # Ip address as dotted quad
            CountryCode[code],          # ISO3166-1 code
            CountryCode3[code],         # ISO3166-2 code
            CountryName[code],          # Country name, per IS03166
            CountryContinent[code],     # Continent code.
            region,                     # Region name
            city,                       # City name
            postal_code,                # Postal code
            latitude,
            longitude,
            dma_code,
            area_code
        ] +
            [ TimeZone["#{CountryCode[code]}#{region}"] || TimeZone["#{CountryCode[code]}"] ]
    end

    def iptonum(ip)     #:nodoc: Convert numeric IP address to integer
        if ip.kind_of?(String) &&
            ip =~ /^([0-9]+)\.([0-9]+)\.([0-9]+)\.([0-9]+)$/
            ip = be_to_ui(Regexp.last_match().to_a.slice(1..4))
        end
        ip
    end

    def seek_record(ipnum)    #:nodoc:
        # Binary search in the file.
        # Records are pairs of little-endian integers, each of @record_length.
        offset = 0
        mask = 0x80000000
        31.downto(0) { |depth|
            off = @record_length * 2 * offset
            buf = atomic_read(@record_length * 2, off)
            buf.slice!(0...@record_length) if ((ipnum & mask) != 0)
            offset = le_to_ui(buf[0...@record_length].unpack("C*"))
            return offset if (offset >= @databaseSegments[0])
            mask >>= 1
        }
    end

    # Convert a big-endian array of numeric bytes to unsigned int
    def be_to_ui(s)   #:nodoc:
        s.inject(0) { |m, o|
            (m << 8) + o.to_i
        }
    end

    # Same for little-endian
    def le_to_ui(s)   #:nodoc:
        be_to_ui(s.reverse)
    end

    # reads +length+ bytes from +offset+ as atomically as possible
    # if IO.pread is available, it'll use that (making it both multithread
    # and multiprocess-safe).  Otherwise we'll use a mutex to synchronize
    # access (only providing protection against multiple threads, but not
    # file descriptors shared across multiple processes).
    def atomic_read(length, offset)   #:nodoc:
        if @mutex
            @mutex.synchronize {
                @file.seek(offset)
                @file.read(length)
            }
        else
            IO.pread(@file.fileno, length, offset)
        end
    end

    module CountryAccessors   #:nodoc:
      ACCESSORS = [
        :request, :ip, :country_code, :country_code2, :country_code3, :country_name, :continent_code
      ]
      ACCESSORS.each_with_index do |method, i|
        define_method(method) { self[i] }
      end

      def to_hash
        ACCESSORS.inject({}) do |hash, key|
          hash[key] = self.send(key)
          hash
        end
      end
    end

    module CityAccessors    #:nodoc:
      ACCESSORS = [
        :request, :ip, :country_code2, :country_code3, :country_name, :continent_code,
        :region_name, :city_name, :postal_code, :latitude, :longitude, :dma_code, :area_code, :timezone
      ]
      ACCESSORS.each_with_index do |method, i|
        define_method(method) { self[i] }
      end

      def to_hash
        ACCESSORS.inject({}) do |hash, key|
          hash[key] = self.send(key)
          hash
        end
      end
    end

    module ASNAccessors   #:nodoc:
      def as_num
        self[0]
      end

      def asn
        self[1]
      end
    end
end
