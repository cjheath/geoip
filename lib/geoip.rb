$:.unshift File.dirname(__FILE__)
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

class GeoIP
    VERSION = "0.8.9"
    private
    CountryCode = [
        "--","AP","EU","AD","AE","AF","AG","AI","AL","AM","AN",
        "AO","AQ","AR","AS","AT","AU","AW","AZ","BA","BB",
        "BD","BE","BF","BG","BH","BI","BJ","BM","BN","BO",
        "BR","BS","BT","BV","BW","BY","BZ","CA","CC","CD",
        "CF","CG","CH","CI","CK","CL","CM","CN","CO","CR",
        "CU","CV","CX","CY","CZ","DE","DJ","DK","DM","DO",
        "DZ","EC","EE","EG","EH","ER","ES","ET","FI","FJ",
        "FK","FM","FO","FR","FX","GA","GB","GD","GE","GF",
        "GH","GI","GL","GM","GN","GP","GQ","GR","GS","GT",
        "GU","GW","GY","HK","HM","HN","HR","HT","HU","ID",
        "IE","IL","IN","IO","IQ","IR","IS","IT","JM","JO",
        "JP","KE","KG","KH","KI","KM","KN","KP","KR","KW",
        "KY","KZ","LA","LB","LC","LI","LK","LR","LS","LT",
        "LU","LV","LY","MA","MC","MD","MG","MH","MK","ML",
        "MM","MN","MO","MP","MQ","MR","MS","MT","MU","MV",
        "MW","MX","MY","MZ","NA","NC","NE","NF","NG","NI",
        "NL","NO","NP","NR","NU","NZ","OM","PA","PE","PF",
        "PG","PH","PK","PL","PM","PN","PR","PS","PT","PW",
        "PY","QA","RE","RO","RU","RW","SA","SB","SC","SD",
        "SE","SG","SH","SI","SJ","SK","SL","SM","SN","SO",
        "SR","ST","SV","SY","SZ","TC","TD","TF","TG","TH",
        "TJ","TK","TM","TN","TO","TL","TR","TT","TV","TW",
        "TZ","UA","UG","UM","US","UY","UZ","VA","VC","VE",
        "VG","VI","VN","VU","WF","WS","YE","YT","RS","ZA",
        "ZM","ME","ZW","A1","A2","O1","AX","GG","IM","JE",
        "BL","MF"
    ]

    CountryCode3 = [
        "--","AP","EU","AND","ARE","AFG","ATG","AIA","ALB","ARM","ANT",
        "AGO","AQ","ARG","ASM","AUT","AUS","ABW","AZE","BIH","BRB",
        "BGD","BEL","BFA","BGR","BHR","BDI","BEN","BMU","BRN","BOL",
        "BRA","BHS","BTN","BV","BWA","BLR","BLZ","CAN","CC","COD",
        "CAF","COG","CHE","CIV","COK","CHL","CMR","CHN","COL","CRI",
        "CUB","CPV","CX","CYP","CZE","DEU","DJI","DNK","DMA","DOM",
        "DZA","ECU","EST","EGY","ESH","ERI","ESP","ETH","FIN","FJI",
        "FLK","FSM","FRO","FRA","FX","GAB","GBR","GRD","GEO","GUF",
        "GHA","GIB","GRL","GMB","GIN","GLP","GNQ","GRC","GS","GTM",
        "GUM","GNB","GUY","HKG","HM","HND","HRV","HTI","HUN","IDN",
        "IRL","ISR","IND","IO","IRQ","IRN","ISL","ITA","JAM","JOR",
        "JPN","KEN","KGZ","KHM","KIR","COM","KNA","PRK","KOR","KWT",
        "CYM","KAZ","LAO","LBN","LCA","LIE","LKA","LBR","LSO","LTU",
        "LUX","LVA","LBY","MAR","MCO","MDA","MDG","MHL","MKD","MLI",
        "MMR","MNG","MAC","MNP","MTQ","MRT","MSR","MLT","MUS","MDV",
        "MWI","MEX","MYS","MOZ","NAM","NCL","NER","NFK","NGA","NIC",
        "NLD","NOR","NPL","NRU","NIU","NZL","OMN","PAN","PER","PYF",
        "PNG","PHL","PAK","POL","SPM","PCN","PRI","PSE","PRT","PLW",
        "PRY","QAT","REU","ROU","RUS","RWA","SAU","SLB","SYC","SDN",
        "SWE","SGP","SHN","SVN","SJM","SVK","SLE","SMR","SEN","SOM",
        "SUR","STP","SLV","SYR","SWZ","TCA","TCD","TF","TGO","THA",
        "TJK","TKL","TKM","TUN","TON","TLS","TUR","TTO","TUV","TWN",
        "TZA","UKR","UGA","UM","USA","URY","UZB","VAT","VCT","VEN",
        "VGB","VIR","VNM","VUT","WLF","WSM","YEM","YT","SRB","ZAF",
        "ZMB","MNE","ZWE","A1","A2","O1","ALA","GGY","IMN","JEY",
        "BLM","MAF"
    ]

    CountryName = [
        "N/A",
        "Asia/Pacific Region",
        "Europe",
        "Andorra",
        "United Arab Emirates",
        "Afghanistan",
        "Antigua and Barbuda",
        "Anguilla",
        "Albania",
        "Armenia",
        "Netherlands Antilles",
        "Angola",
        "Antarctica",
        "Argentina",
        "American Samoa",
        "Austria",
        "Australia",
        "Aruba",
        "Azerbaijan",
        "Bosnia and Herzegovina",
        "Barbados",
        "Bangladesh",
        "Belgium",
        "Burkina Faso",
        "Bulgaria",
        "Bahrain",
        "Burundi",
        "Benin",
        "Bermuda",
        "Brunei Darussalam",
        "Bolivia",
        "Brazil",
        "Bahamas",
        "Bhutan",
        "Bouvet Island",
        "Botswana",
        "Belarus",
        "Belize",
        "Canada",
        "Cocos (Keeling) Islands",
        "Congo, the Democratic Republic of the",
        "Central African Republic",
        "Congo",
        "Switzerland",
        "Cote D'Ivoire",
        "Cook Islands",
        "Chile",
        "Cameroon",
        "China",
        "Colombia",
        "Costa Rica",
        "Cuba",
        "Cape Verde",
        "Christmas Island",
        "Cyprus",
        "Czech Republic",
        "Germany",
        "Djibouti",
        "Denmark",
        "Dominica",
        "Dominican Republic",
        "Algeria",
        "Ecuador",
        "Estonia",
        "Egypt",
        "Western Sahara",
        "Eritrea",
        "Spain",
        "Ethiopia",
        "Finland",
        "Fiji",
        "Falkland Islands (Malvinas)",
        "Micronesia, Federated States of",
        "Faroe Islands",
        "France",
        "France, Metropolitan",
        "Gabon",
        "United Kingdom",
        "Grenada",
        "Georgia",
        "French Guiana",
        "Ghana",
        "Gibraltar",
        "Greenland",
        "Gambia",
        "Guinea",
        "Guadeloupe",
        "Equatorial Guinea",
        "Greece",
        "South Georgia and the South Sandwich Islands",
        "Guatemala",
        "Guam",
        "Guinea-Bissau",
        "Guyana",
        "Hong Kong",
        "Heard Island and McDonald Islands",
        "Honduras",
        "Croatia",
        "Haiti",
        "Hungary",
        "Indonesia",
        "Ireland",
        "Israel",
        "India",
        "British Indian Ocean Territory",
        "Iraq",
        "Iran, Islamic Republic of",
        "Iceland",
        "Italy",
        "Jamaica",
        "Jordan",
        "Japan",
        "Kenya",
        "Kyrgyzstan",
        "Cambodia",
        "Kiribati",
        "Comoros",
        "Saint Kitts and Nevis",
        "Korea, Democratic People's Republic of",
        "Korea, Republic of",
        "Kuwait",
        "Cayman Islands",
        "Kazakhstan",
        "Lao People's Democratic Republic",
        "Lebanon",
        "Saint Lucia",
        "Liechtenstein",
        "Sri Lanka",
        "Liberia",
        "Lesotho",
        "Lithuania",
        "Luxembourg",
        "Latvia",
        "Libyan Arab Jamahiriya",
        "Morocco",
        "Monaco",
        "Moldova, Republic of",
        "Madagascar",
        "Marshall Islands",
        "Macedonia, the Former Yugoslav Republic of",
        "Mali",
        "Myanmar",
        "Mongolia",
        "Macau",
        "Northern Mariana Islands",
        "Martinique",
        "Mauritania",
        "Montserrat",
        "Malta",
        "Mauritius",
        "Maldives",
        "Malawi",
        "Mexico",
        "Malaysia",
        "Mozambique",
        "Namibia",
        "New Caledonia",
        "Niger",
        "Norfolk Island",
        "Nigeria",
        "Nicaragua",
        "Netherlands",
        "Norway",
        "Nepal",
        "Nauru",
        "Niue",
        "New Zealand",
        "Oman",
        "Panama",
        "Peru",
        "French Polynesia",
        "Papua New Guinea",
        "Philippines",
        "Pakistan",
        "Poland",
        "Saint Pierre and Miquelon",
        "Pitcairn",
        "Puerto Rico",
        "Palestinian Territory, Occupied",
        "Portugal",
        "Palau",
        "Paraguay",
        "Qatar",
        "Reunion",
        "Romania",
        "Russian Federation",
        "Rwanda",
        "Saudi Arabia",
        "Solomon Islands",
        "Seychelles",
        "Sudan",
        "Sweden",
        "Singapore",
        "Saint Helena",
        "Slovenia",
        "Svalbard and Jan Mayen",
        "Slovakia",
        "Sierra Leone",
        "San Marino",
        "Senegal",
        "Somalia",
        "Suriname",
        "Sao Tome and Principe",
        "El Salvador",
        "Syrian Arab Republic",
        "Swaziland",
        "Turks and Caicos Islands",
        "Chad",
        "French Southern Territories",
        "Togo",
        "Thailand",
        "Tajikistan",
        "Tokelau",
        "Turkmenistan",
        "Tunisia",
        "Tonga",
        "Timor-Leste",
        "Turkey",
        "Trinidad and Tobago",
        "Tuvalu",
        "Taiwan, Province of China",
        "Tanzania, United Republic of",
        "Ukraine",
        "Uganda",
        "United States Minor Outlying Islands",
        "United States",
        "Uruguay",
        "Uzbekistan",
        "Holy See (Vatican City State)",
        "Saint Vincent and the Grenadines",
        "Venezuela",
        "Virgin Islands, British",
        "Virgin Islands, U.S.",
        "Viet Nam",
        "Vanuatu",
        "Wallis and Futuna",
        "Samoa",
        "Yemen",
        "Mayotte",
        "Serbia",
        "South Africa",
        "Zambia",
        "Montenegro",
        "Zimbabwe",
        "Anonymous Proxy",
        "Satellite Provider",
        "Other",
        "Aland Islands",
        "Guernsey",
        "Isle of Man",
        "Jersey",
        "Saint Barthelemy",
        "Saint Martin"
    ]

    CountryContinent = [
        "--","AS","EU","EU","AS","AS","SA","SA","EU","AS","SA",
        "AF","AN","SA","OC","EU","OC","SA","AS","EU","SA",
        "AS","EU","AF","EU","AS","AF","AF","SA","AS","SA",
        "SA","SA","AS","AF","AF","EU","SA","NA","AS","AF",
        "AF","AF","EU","AF","OC","SA","AF","AS","SA","SA",
        "SA","AF","AS","AS","EU","EU","AF","EU","SA","SA",
        "AF","SA","EU","AF","AF","AF","EU","AF","EU","OC",
        "SA","OC","EU","EU","EU","AF","EU","SA","AS","SA",
        "AF","EU","SA","AF","AF","SA","AF","EU","SA","SA",
        "OC","AF","SA","AS","AF","SA","EU","SA","EU","AS",
        "EU","AS","AS","AS","AS","AS","EU","EU","SA","AS",
        "AS","AF","AS","AS","OC","AF","SA","AS","AS","AS",
        "SA","AS","AS","AS","SA","EU","AS","AF","AF","EU",
        "EU","EU","AF","AF","EU","EU","AF","OC","EU","AF",
        "AS","AS","AS","OC","SA","AF","SA","EU","AF","AS",
        "AF","NA","AS","AF","AF","OC","AF","OC","AF","SA",
        "EU","EU","AS","OC","OC","OC","AS","SA","SA","OC",
        "OC","AS","AS","EU","SA","OC","SA","AS","EU","OC",
        "SA","AS","AF","EU","AS","AF","AS","OC","AF","AF",
        "EU","AS","AF","EU","EU","EU","AF","EU","AF","AF",
        "SA","AF","SA","AS","AF","SA","AF","AF","AF","AS",
        "AS","OC","AS","AF","OC","AS","AS","SA","OC","AS",
        "AF","EU","AF","OC","NA","SA","AS","EU","SA","SA",
        "SA","SA","AS","OC","OC","OC","AS","AF","EU","AF",
        "AF","EU","AF","--","--","--","EU","EU","EU","EU",
        "SA","SA"
    ]

    TimeZone = {
        "USAL" => "America/Chicago", "USAK" => "America/Anchorage", "USAZ" => "America/Phoenix",
        "USAR" => "America/Chicago", "USCA" => "America/Los_Angeles", "USCO" => "America/Denver",
        "USCT" => "America/New_York", "USDE" => "America/New_York", "USDC" => "America/New_York",
        "USFL" => "America/New_York", "USGA" => "America/New_York", "USHI" => "Pacific/Honolulu",
        "USID" => "America/Denver", "USIL" => "America/Chicago", "USIN" => "America/Indianapolis",
        "USIA" => "America/Chicago", "USKS" => "America/Chicago", "USKY" => "America/New_York",
        "USLA" => "America/Chicago", "USME" => "America/New_York", "USMD" => "America/New_York",
        "USMA" => "America/New_York", "USMI" => "America/New_York", "USMN" => "America/Chicago",
        "USMS" => "America/Chicago", "USMO" => "America/Chicago", "USMT" => "America/Denver",
        "USNE" => "America/Chicago", "USNV" => "America/Los_Angeles", "USNH" => "America/New_York",
        "USNJ" => "America/New_York", "USNM" => "America/Denver", "USNY" => "America/New_York",
        "USNC" => "America/New_York", "USND" => "America/Chicago", "USOH" => "America/New_York",
        "USOK" => "America/Chicago", "USOR" => "America/Los_Angeles", "USPA" => "America/New_York",
        "USRI" => "America/New_York", "USSC" => "America/New_York", "USSD" => "America/Chicago",
        "USTN" => "America/Chicago", "USTX" => "America/Chicago", "USUT" => "America/Denver",
        "USVT" => "America/New_York", "USVA" => "America/New_York", "USWA" => "America/Los_Angeles",
        "USWV" => "America/New_York", "USWI" => "America/Chicago", "USWY" => "America/Denver",
        "CAAB" => "America/Edmonton", "CABC" => "America/Vancouver", "CAMB" => "America/Winnipeg",
        "CANB" => "America/Halifax", "CANL" => "America/St_Johns", "CANT" => "America/Yellowknife",
        "CANS" => "America/Halifax", "CANU" => "America/Rankin_Inlet", "CAON" => "America/Rainy_River",
        "CAPE" => "America/Halifax", "CAQC" => "America/Montreal", "CASK" => "America/Regina",
        "CAYT" => "America/Whitehorse", "AU01" => "Australia/Canberra", "AU02" => "Australia/NSW",
        "AU03" => "Australia/North", "AU04" => "Australia/Queensland", "AU05" => "Australia/South",
        "AU06" => "Australia/Tasmania", "AU07" => "Australia/Victoria", "AU08" => "Australia/West",
        "AS" => "US/Samoa", "CI" => "Africa/Abidjan", "GH" => "Africa/Accra",
        "DZ" => "Africa/Algiers", "ER" => "Africa/Asmera", "ML" => "Africa/Bamako",
        "CF" => "Africa/Bangui", "GM" => "Africa/Banjul", "GW" => "Africa/Bissau",
        "CG" => "Africa/Brazzaville", "BI" => "Africa/Bujumbura", "EG" => "Africa/Cairo",
        "MA" => "Africa/Casablanca", "GN" => "Africa/Conakry", "SN" => "Africa/Dakar",
        "DJ" => "Africa/Djibouti", "SL" => "Africa/Freetown", "BW" => "Africa/Gaborone",
        "ZW" => "Africa/Harare", "ZA" => "Africa/Johannesburg", "UG" => "Africa/Kampala",
        "SD" => "Africa/Khartoum", "RW" => "Africa/Kigali", "NG" => "Africa/Lagos",
        "GA" => "Africa/Libreville", "TG" => "Africa/Lome", "AO" => "Africa/Luanda",
        "ZM" => "Africa/Lusaka", "GQ" => "Africa/Malabo", "MZ" => "Africa/Maputo",
        "LS" => "Africa/Maseru", "SZ" => "Africa/Mbabane", "SO" => "Africa/Mogadishu",
        "LR" => "Africa/Monrovia", "KE" => "Africa/Nairobi", "TD" => "Africa/Ndjamena",
        "NE" => "Africa/Niamey", "MR" => "Africa/Nouakchott", "BF" => "Africa/Ouagadougou",
        "ST" => "Africa/Sao_Tome", "LY" => "Africa/Tripoli", "TN" => "Africa/Tunis",
        "AI" => "America/Anguilla", "AG" => "America/Antigua", "AW" => "America/Aruba",
        "BB" => "America/Barbados", "BZ" => "America/Belize", "CO" => "America/Bogota",
        "VE" => "America/Caracas", "KY" => "America/Cayman", "CR" => "America/Costa_Rica",
        "DM" => "America/Dominica", "SV" => "America/El_Salvador", "GD" => "America/Grenada",
        "FR" => "Europe/Paris", "GP" => "America/Guadeloupe", "GT" => "America/Guatemala",
        "GY" => "America/Guyana", "CU" => "America/Havana", "JM" => "America/Jamaica",
        "BO" => "America/La_Paz", "PE" => "America/Lima", "NI" => "America/Managua",
        "MQ" => "America/Martinique", "UY" => "America/Montevideo", "MS" => "America/Montserrat",
        "BS" => "America/Nassau", "PA" => "America/Panama", "SR" => "America/Paramaribo",
        "PR" => "America/Puerto_Rico", "KN" => "America/St_Kitts", "LC" => "America/St_Lucia",
        "VC" => "America/St_Vincent", "HN" => "America/Tegucigalpa", "YE" => "Asia/Aden",
        "JO" => "Asia/Amman", "TM" => "Asia/Ashgabat", "IQ" => "Asia/Baghdad",
        "BH" => "Asia/Bahrain", "AZ" => "Asia/Baku", "TH" => "Asia/Bangkok",
        "LB" => "Asia/Beirut", "KG" => "Asia/Bishkek", "BN" => "Asia/Brunei",
        "IN" => "Asia/Calcutta", "MN" => "Asia/Choibalsan", "LK" => "Asia/Colombo",
        "BD" => "Asia/Dhaka", "AE" => "Asia/Dubai", "TJ" => "Asia/Dushanbe",
        "HK" => "Asia/Hong_Kong", "TR" => "Asia/Istanbul", "IL" => "Asia/Jerusalem",
        "AF" => "Asia/Kabul", "PK" => "Asia/Karachi", "NP" => "Asia/Katmandu",
        "KW" => "Asia/Kuwait", "MO" => "Asia/Macao", "PH" => "Asia/Manila",
        "OM" => "Asia/Muscat", "CY" => "Asia/Nicosia", "KP" => "Asia/Pyongyang",
        "QA" => "Asia/Qatar", "MM" => "Asia/Rangoon", "SA" => "Asia/Riyadh",
        "KR" => "Asia/Seoul", "SG" => "Asia/Singapore", "TW" => "Asia/Taipei",
        "GE" => "Asia/Tbilisi", "BT" => "Asia/Thimphu", "JP" => "Asia/Tokyo",
        "LA" => "Asia/Vientiane", "AM" => "Asia/Yerevan", "BM" => "Atlantic/Bermuda",
        "CV" => "Atlantic/Cape_Verde", "FO" => "Atlantic/Faeroe", "IS" => "Atlantic/Reykjavik",
        "GS" => "Atlantic/South_Georgia", "SH" => "Atlantic/St_Helena", "CL" => "Chile/Continental",
        "NL" => "Europe/Amsterdam", "AD" => "Europe/Andorra", "GR" => "Europe/Athens",
        "YU" => "Europe/Belgrade", "DE" => "Europe/Berlin", "SK" => "Europe/Bratislava",
        "BE" => "Europe/Brussels", "RO" => "Europe/Bucharest", "HU" => "Europe/Budapest",
        "DK" => "Europe/Copenhagen", "IE" => "Europe/Dublin", "GI" => "Europe/Gibraltar",
        "FI" => "Europe/Helsinki", "SI" => "Europe/Ljubljana", "GB" => "Europe/London",
        "LU" => "Europe/Luxembourg", "MT" => "Europe/Malta", "BY" => "Europe/Minsk",
        "MC" => "Europe/Monaco", "NO" => "Europe/Oslo", "CZ" => "Europe/Prague",
        "LV" => "Europe/Riga", "IT" => "Europe/Rome", "SM" => "Europe/San_Marino",
        "BA" => "Europe/Sarajevo", "MK" => "Europe/Skopje", "BG" => "Europe/Sofia",
        "SE" => "Europe/Stockholm", "EE" => "Europe/Tallinn", "AL" => "Europe/Tirane",
        "LI" => "Europe/Vaduz", "VA" => "Europe/Vatican", "AT" => "Europe/Vienna",
        "LT" => "Europe/Vilnius", "PL" => "Europe/Warsaw", "HR" => "Europe/Zagreb",
        "IR" => "Asia/Tehran", "MG" => "Indian/Antananarivo", "CX" => "Indian/Christmas",
        "CC" => "Indian/Cocos", "KM" => "Indian/Comoro", "MV" => "Indian/Maldives",
        "MU" => "Indian/Mauritius", "YT" => "Indian/Mayotte", "RE" => "Indian/Reunion",
        "FJ" => "Pacific/Fiji", "TV" => "Pacific/Funafuti", "GU" => "Pacific/Guam",
        "NR" => "Pacific/Nauru", "NU" => "Pacific/Niue", "NF" => "Pacific/Norfolk",
        "PW" => "Pacific/Palau", "PN" => "Pacific/Pitcairn", "CK" => "Pacific/Rarotonga",
        "WS" => "Pacific/Samoa", "KI" => "Pacific/Tarawa", "TO" => "Pacific/Tongatapu",
        "WF" => "Pacific/Wallis", "TZ" => "Africa/Dar_es_Salaam", "VN" => "Asia/Phnom_Penh",
        "KH" => "Asia/Phnom_Penh", "CM" => "Africa/Lagos", "DO" => "America/Santo_Domingo",
        "ET" => "Africa/Addis_Ababa", "FX" => "Europe/Paris", "HT" => "America/Port-au-Prince",
        "CH" => "Europe/Zurich", "AN" => "America/Curacao", "BJ" => "Africa/Porto-Novo",
        "EH" => "Africa/El_Aaiun", "FK" => "Atlantic/Stanley", "GF" => "America/Cayenne",
        "IO" => "Indian/Chagos", "MD" => "Europe/Chisinau", "MP" => "Pacific/Saipan",
        "MW" => "Africa/Blantyre", "NA" => "Africa/Windhoek", "NC" => "Pacific/Noumea",
        "PG" => "Pacific/Port_Moresby", "PM" => "America/Miquelon", "PS" => "Asia/Gaza",
        "PY" => "America/Asuncion", "SB" => "Pacific/Guadalcanal", "SC" => "Indian/Mahe",
        "SJ" => "Arctic/Longyearbyen", "SY" => "Asia/Damascus", "TC" => "America/Grand_Turk",
        "TF" => "Indian/Kerguelen", "TK" => "Pacific/Fakaofo", "TT" => "America/Port_of_Spain",
        "VG" => "America/Tortola", "VI" => "America/St_Thomas", "VU" => "Pacific/Efate",
        "RS" => "Europe/Belgrade", "ME" => "Europe/Podgorica", "AX" => "Europe/Mariehamn",
        "GG" => "Europe/Guernsey", "IM" => "Europe/Isle_of_Man", "JE" => "Europe/Jersey",
        "BL" => "America/St_Barthelemy", "MF" => "America/Marigot", "AR01" => "America/Argentina/Buenos_Aires",
        "AR02" => "America/Argentina/Catamarca", "AR03" => "America/Argentina/Tucuman", "AR04" => "America/Argentina/Rio_Gallegos",
        "AR05" => "America/Argentina/Cordoba", "AR06" => "America/Argentina/Tucuman", "AR07" => "America/Argentina/Buenos_Aires",
        "AR08" => "America/Argentina/Buenos_Aires", "AR09" => "America/Argentina/Tucuman", "AR10" => "America/Argentina/Jujuy",
        "AR11" => "America/Argentina/San_Luis", "AR12" => "America/Argentina/La_Rioja", "AR13" => "America/Argentina/Mendoza",
        "AR14" => "America/Argentina/Buenos_Aires", "AR15" => "America/Argentina/San_Luis", "AR16" => "America/Argentina/Buenos_Aires",
        "AR17" => "America/Argentina/Salta", "AR18" => "America/Argentina/San_Juan", "AR19" => "America/Argentina/San_Luis",
        "AR20" => "America/Argentina/Rio_Gallegos", "AR21" => "America/Argentina/Buenos_Aires", "AR22" => "America/Argentina/Catamarca",
        "AR23" => "America/Argentina/Ushuaia", "AR24" => "America/Argentina/Tucuman", "BR01" => "America/Rio_Branco",
        "BR02" => "America/Maceio", "BR03" => "America/Sao_Paulo", "BR04" => "America/Manaus",
        "BR05" => "America/Bahia", "BR06" => "America/Fortaleza", "BR07" => "America/Sao_Paulo",
        "BR08" => "America/Sao_Paulo", "BR11" => "America/Campo_Grande", "BR13" => "America/Belem",
        "BR14" => "America/Cuiaba", "BR15" => "America/Sao_Paulo", "BR16" => "America/Belem",
        "BR17" => "America/Recife", "BR18" => "America/Sao_Paulo", "BR20" => "America/Fortaleza",
        "BR21" => "America/Sao_Paulo", "BR22" => "America/Recife", "BR23" => "America/Sao_Paulo",
        "BR24" => "America/Porto_Velho", "BR25" => "America/Boa_Vista", "BR26" => "America/Sao_Paulo",
        "BR27" => "America/Sao_Paulo", "BR28" => "America/Maceio", "BR29" => "America/Sao_Paulo",
        "BR30" => "America/Recife", "BR31" => "America/Araguaina", "CD02" => "Africa/Kinshasa",
        "CD05" => "Africa/Lubumbashi", "CD06" => "Africa/Kinshasa", "CD08" => "Africa/Kinshasa",
        "CD10" => "Africa/Lubumbashi", "CD11" => "Africa/Lubumbashi", "CD12" => "Africa/Lubumbashi",
        "CN01" => "Asia/Shanghai", "CN02" => "Asia/Shanghai", "CN03" => "Asia/Shanghai",
        "CN04" => "Asia/Shanghai", "CN05" => "Asia/Harbin", "CN06" => "Asia/Chongqing",
        "CN07" => "Asia/Shanghai", "CN08" => "Asia/Harbin", "CN09" => "Asia/Shanghai",
        "CN10" => "Asia/Shanghai", "CN11" => "Asia/Chongqing", "CN12" => "Asia/Shanghai",
        "CN13" => "Asia/Urumqi", "CN14" => "Asia/Chongqing", "CN15" => "Asia/Chongqing",
        "CN16" => "Asia/Chongqing", "CN18" => "Asia/Chongqing", "CN19" => "Asia/Harbin",
        "CN20" => "Asia/Harbin", "CN21" => "Asia/Chongqing", "CN22" => "Asia/Harbin",
        "CN23" => "Asia/Shanghai", "CN24" => "Asia/Chongqing", "CN25" => "Asia/Shanghai",
        "CN26" => "Asia/Chongqing", "CN28" => "Asia/Shanghai", "CN29" => "Asia/Chongqing",
        "CN30" => "Asia/Chongqing", "CN31" => "Asia/Chongqing", "CN32" => "Asia/Chongqing",
        "CN33" => "Asia/Chongqing", "EC01" => "Pacific/Galapagos", "EC02" => "America/Guayaquil",
        "EC03" => "America/Guayaquil", "EC04" => "America/Guayaquil", "EC05" => "America/Guayaquil",
        "EC06" => "America/Guayaquil", "EC07" => "America/Guayaquil", "EC08" => "America/Guayaquil",
        "EC09" => "America/Guayaquil", "EC10" => "America/Guayaquil", "EC11" => "America/Guayaquil",
        "EC12" => "America/Guayaquil", "EC13" => "America/Guayaquil", "EC14" => "America/Guayaquil",
        "EC15" => "America/Guayaquil", "EC17" => "America/Guayaquil", "EC18" => "America/Guayaquil",
        "EC19" => "America/Guayaquil", "EC20" => "America/Guayaquil", "EC22" => "America/Guayaquil",
        "ES07" => "Europe/Madrid", "ES27" => "Europe/Madrid", "ES29" => "Europe/Madrid",
        "ES31" => "Europe/Madrid", "ES32" => "Europe/Madrid", "ES34" => "Europe/Madrid",
        "ES39" => "Europe/Madrid", "ES51" => "Africa/Ceuta", "ES52" => "Europe/Madrid",
        "ES53" => "Atlantic/Canary", "ES54" => "Europe/Madrid", "ES55" => "Europe/Madrid",
        "ES56" => "Europe/Madrid", "ES57" => "Europe/Madrid", "ES58" => "Europe/Madrid",
        "ES59" => "Europe/Madrid", "ES60" => "Europe/Madrid", "GL01" => "America/Thule",
        "GL02" => "America/Godthab", "GL03" => "America/Godthab", "ID01" => "Asia/Pontianak",
        "ID02" => "Asia/Makassar", "ID03" => "Asia/Jakarta", "ID04" => "Asia/Jakarta",
        "ID05" => "Asia/Jakarta", "ID06" => "Asia/Jakarta", "ID07" => "Asia/Jakarta",
        "ID08" => "Asia/Jakarta", "ID09" => "Asia/Jayapura", "ID10" => "Asia/Jakarta",
        "ID11" => "Asia/Pontianak", "ID12" => "Asia/Makassar", "ID13" => "Asia/Makassar",
        "ID14" => "Asia/Makassar", "ID15" => "Asia/Jakarta", "ID16" => "Asia/Makassar",
        "ID17" => "Asia/Makassar", "ID18" => "Asia/Makassar", "ID19" => "Asia/Pontianak",
        "ID20" => "Asia/Makassar", "ID21" => "Asia/Makassar", "ID22" => "Asia/Makassar",
        "ID23" => "Asia/Makassar", "ID24" => "Asia/Jakarta", "ID25" => "Asia/Pontianak",
        "ID26" => "Asia/Pontianak", "ID30" => "Asia/Jakarta", "ID31" => "Asia/Makassar",
        "ID33" => "Asia/Jakarta", "KZ01" => "Asia/Almaty", "KZ02" => "Asia/Almaty",
        "KZ03" => "Asia/Qyzylorda", "KZ04" => "Asia/Aqtobe", "KZ05" => "Asia/Qyzylorda",
        "KZ06" => "Asia/Aqtau", "KZ07" => "Asia/Oral", "KZ08" => "Asia/Qyzylorda",
        "KZ09" => "Asia/Aqtau", "KZ10" => "Asia/Qyzylorda", "KZ11" => "Asia/Almaty",
        "KZ12" => "Asia/Qyzylorda", "KZ13" => "Asia/Aqtobe", "KZ14" => "Asia/Qyzylorda",
        "KZ15" => "Asia/Almaty", "KZ16" => "Asia/Aqtobe", "KZ17" => "Asia/Almaty",
        "MX01" => "America/Mexico_City", "MX02" => "America/Tijuana", "MX03" => "America/Hermosillo",
        "MX04" => "America/Merida", "MX05" => "America/Mexico_City", "MX06" => "America/Chihuahua",
        "MX07" => "America/Monterrey", "MX08" => "America/Mexico_City", "MX09" => "America/Mexico_City",
        "MX10" => "America/Mazatlan", "MX11" => "America/Mexico_City", "MX12" => "America/Mexico_City",
        "MX13" => "America/Mexico_City", "MX14" => "America/Mazatlan", "MX15" => "America/Chihuahua",
        "MX16" => "America/Mexico_City", "MX17" => "America/Mexico_City", "MX18" => "America/Mazatlan",
        "MX19" => "America/Monterrey", "MX20" => "America/Mexico_City", "MX21" => "America/Mexico_City",
        "MX22" => "America/Mexico_City", "MX23" => "America/Cancun", "MX24" => "America/Mexico_City",
        "MX25" => "America/Mazatlan", "MX26" => "America/Hermosillo", "MX27" => "America/Merida",
        "MX28" => "America/Monterrey", "MX29" => "America/Mexico_City", "MX30" => "America/Mexico_City",
        "MX31" => "America/Merida", "MX32" => "America/Monterrey", "MY01" => "Asia/Kuala_Lumpur",
        "MY02" => "Asia/Kuala_Lumpur", "MY03" => "Asia/Kuala_Lumpur", "MY04" => "Asia/Kuala_Lumpur",
        "MY05" => "Asia/Kuala_Lumpur", "MY06" => "Asia/Kuala_Lumpur", "MY07" => "Asia/Kuala_Lumpur",
        "MY08" => "Asia/Kuala_Lumpur", "MY09" => "Asia/Kuala_Lumpur", "MY11" => "Asia/Kuching",
        "MY12" => "Asia/Kuala_Lumpur", "MY13" => "Asia/Kuala_Lumpur", "MY14" => "Asia/Kuala_Lumpur",
        "MY15" => "Asia/Kuching", "MY16" => "Asia/Kuching", "NZ85" => "Pacific/Auckland",
        "NZE7" => "Pacific/Auckland", "NZE8" => "Pacific/Auckland", "NZE9" => "Pacific/Auckland",
        "NZF1" => "Pacific/Auckland", "NZF2" => "Pacific/Auckland", "NZF3" => "Pacific/Auckland",
        "NZF4" => "Pacific/Auckland", "NZF5" => "Pacific/Auckland", "NZF7" => "Pacific/Chatham",
        "NZF8" => "Pacific/Auckland", "NZF9" => "Pacific/Auckland", "NZG1" => "Pacific/Auckland",
        "NZG2" => "Pacific/Auckland", "NZG3" => "Pacific/Auckland", "PT02" => "Europe/Lisbon",
        "PT03" => "Europe/Lisbon", "PT04" => "Europe/Lisbon", "PT05" => "Europe/Lisbon",
        "PT06" => "Europe/Lisbon", "PT07" => "Europe/Lisbon", "PT08" => "Europe/Lisbon",
        "PT09" => "Europe/Lisbon", "PT10" => "Atlantic/Madeira", "PT11" => "Europe/Lisbon",
        "PT13" => "Europe/Lisbon", "PT14" => "Europe/Lisbon", "PT16" => "Europe/Lisbon",
        "PT17" => "Europe/Lisbon", "PT18" => "Europe/Lisbon", "PT19" => "Europe/Lisbon",
        "PT20" => "Europe/Lisbon", "PT21" => "Europe/Lisbon", "PT22" => "Europe/Lisbon",
        "RU01" => "Europe/Volgograd", "RU02" => "Asia/Irkutsk", "RU03" => "Asia/Novokuznetsk",
        "RU04" => "Asia/Novosibirsk", "RU05" => "Asia/Vladivostok", "RU06" => "Europe/Moscow",
        "RU07" => "Europe/Volgograd", "RU08" => "Europe/Samara", "RU09" => "Europe/Moscow",
        "RU10" => "Europe/Moscow", "RU11" => "Asia/Irkutsk", "RU13" => "Asia/Yekaterinburg",
        "RU14" => "Asia/Irkutsk", "RU15" => "Asia/Anadyr", "RU16" => "Europe/Samara",
        "RU17" => "Europe/Volgograd", "RU18" => "Asia/Krasnoyarsk", "RU20" => "Asia/Irkutsk",
        "RU21" => "Europe/Moscow", "RU22" => "Europe/Volgograd", "RU23" => "Europe/Kaliningrad",
        "RU24" => "Europe/Volgograd", "RU25" => "Europe/Moscow", "RU26" => "Asia/Kamchatka",
        "RU27" => "Europe/Volgograd", "RU28" => "Europe/Moscow", "RU29" => "Asia/Novokuznetsk",
        "RU30" => "Asia/Vladivostok", "RU31" => "Asia/Krasnoyarsk", "RU32" => "Asia/Omsk",
        "RU33" => "Asia/Yekaterinburg", "RU34" => "Asia/Yekaterinburg", "RU35" => "Asia/Yekaterinburg",
        "RU36" => "Asia/Anadyr", "RU37" => "Europe/Moscow", "RU38" => "Europe/Volgograd",
        "RU39" => "Asia/Krasnoyarsk", "RU40" => "Asia/Yekaterinburg", "RU41" => "Europe/Moscow",
        "RU42" => "Europe/Moscow", "RU43" => "Europe/Moscow", "RU44" => "Asia/Magadan",
        "RU45" => "Europe/Samara", "RU46" => "Europe/Samara", "RU47" => "Europe/Moscow",
        "RU48" => "Europe/Moscow", "RU49" => "Europe/Moscow", "RU50" => "Asia/Yekaterinburg",
        "RU51" => "Europe/Moscow", "RU52" => "Europe/Moscow", "RU53" => "Asia/Novosibirsk",
        "RU54" => "Asia/Omsk", "RU55" => "Europe/Samara", "RU56" => "Europe/Moscow",
        "RU57" => "Europe/Samara", "RU58" => "Asia/Yekaterinburg", "RU59" => "Asia/Vladivostok",
        "RU60" => "Europe/Kaliningrad", "RU61" => "Europe/Volgograd", "RU62" => "Europe/Moscow",
        "RU63" => "Asia/Yakutsk", "RU64" => "Asia/Sakhalin", "RU65" => "Europe/Samara",
        "RU66" => "Europe/Moscow", "RU67" => "Europe/Samara", "RU68" => "Europe/Volgograd",
        "RU69" => "Europe/Moscow", "RU70" => "Europe/Volgograd", "RU71" => "Asia/Yekaterinburg",
        "RU72" => "Europe/Moscow", "RU73" => "Europe/Samara", "RU74" => "Asia/Krasnoyarsk",
        "RU75" => "Asia/Novosibirsk", "RU76" => "Europe/Moscow", "RU77" => "Europe/Moscow",
        "RU78" => "Asia/Yekaterinburg", "RU79" => "Asia/Irkutsk", "RU80" => "Asia/Yekaterinburg",
        "RU81" => "Europe/Samara", "RU82" => "Asia/Irkutsk", "RU83" => "Europe/Moscow",
        "RU84" => "Europe/Volgograd", "RU85" => "Europe/Moscow", "RU86" => "Europe/Moscow",
        "RU87" => "Asia/Novosibirsk", "RU88" => "Europe/Moscow", "RU89" => "Asia/Vladivostok",
        "UA01" => "Europe/Kiev", "UA02" => "Europe/Kiev", "UA03" => "Europe/Uzhgorod",
        "UA04" => "Europe/Zaporozhye", "UA05" => "Europe/Zaporozhye", "UA06" => "Europe/Uzhgorod",
        "UA07" => "Europe/Zaporozhye", "UA08" => "Europe/Simferopol", "UA09" => "Europe/Kiev",
        "UA10" => "Europe/Zaporozhye", "UA11" => "Europe/Simferopol", "UA13" => "Europe/Kiev",
        "UA14" => "Europe/Zaporozhye", "UA15" => "Europe/Uzhgorod", "UA16" => "Europe/Zaporozhye",
        "UA17" => "Europe/Simferopol", "UA18" => "Europe/Zaporozhye", "UA19" => "Europe/Kiev",
        "UA20" => "Europe/Simferopol", "UA21" => "Europe/Kiev", "UA22" => "Europe/Uzhgorod",
        "UA23" => "Europe/Kiev", "UA24" => "Europe/Uzhgorod", "UA25" => "Europe/Uzhgorod",
        "UA26" => "Europe/Zaporozhye", "UA27" => "Europe/Kiev", "UZ01" => "Asia/Tashkent",
        "UZ02" => "Asia/Samarkand", "UZ03" => "Asia/Tashkent", "UZ06" => "Asia/Tashkent",
        "UZ07" => "Asia/Samarkand", "UZ08" => "Asia/Samarkand", "UZ09" => "Asia/Samarkand",
        "UZ10" => "Asia/Samarkand", "UZ12" => "Asia/Samarkand", "UZ13" => "Asia/Tashkent",
        "UZ14" => "Asia/Tashkent", "TL" => "Asia/Dili", "PF" => "Pacific/Marquesas"
    }

    public
    # Edition enumeration:
    (GEOIP_COUNTRY_EDITION,
    GEOIP_CITY_EDITION_REV1,
    GEOIP_REGION_EDITION_REV1,
    GEOIP_ISP_EDITION,
    GEOIP_ORG_EDITION,
    GEOIP_CITY_EDITION_REV0,
    GEOIP_REGION_EDITION_REV0,
    GEOIP_PROXY_EDITION,
    GEOIP_ASNUM_EDITION,
    GEOIP_NETSPEED_EDITION,
    ) = *1..10

    private
    COUNTRY_BEGIN = 16776960
    STATE_BEGIN_REV0 = 16700000
    STATE_BEGIN_REV1 = 16000000
    STRUCTURE_INFO_MAX_SIZE = 20
    DATABASE_INFO_MAX_SIZE = 100
    MAX_ORG_RECORD_LENGTH = 300
    MAX_ASN_RECORD_LENGTH = 300 # unverified
    US_OFFSET = 1
    CANADA_OFFSET = 677
    WORLD_OFFSET = 1353
    FIPS_RANGE = 360
    FULL_RECORD_LENGTH = 50

    STANDARD_RECORD_LENGTH = 3
    SEGMENT_RECORD_LENGTH = 3

    public
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
    # Return an array of seven elements:
    # * The host or IP address string as requested
    # * The IP address string after looking up the host
    # * The GeoIP country-ID as an integer
    # * The ISO3166-1 two-character country code
    # * The ISO3166-2 three-character country code
    # * The ISO3166 English-language name of the country
    # * The two-character continent code
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
            CountryCode[code],          # ISO3166-1 code
            CountryCode3[code],         # ISO3166-2 code
            CountryName[code],          # Country name, per IS03166
            CountryContinent[code] ]    # Continent code.
    end

    # Search the GeoIP database for the specified host, returning city info
    #
    # +hostname+ is a String holding the host's DNS name or numeric IP address
    # Return an array of twelve or fourteen elements:
    # * All elements from the country query
    # * The region (state or territory) name
    # * The city name
    # * The postal code (zipcode)
    # * The latitude
    # * The longitude
    # * The dma_code and area_code, if available (REV1 City database)
    # * The timezone name, if known
    private

    def read_city(pos, hostname = '', ip = '')
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

        us_area_codes = []
        if (record &&
                record[0,3] &&
                @databaseType == GEOIP_CITY_EDITION_REV1 &&
                CountryCode[code] == "US")      # UNTESTED
            dmaarea_combo = le_to_ui(record[0,3].unpack('C*'))
            dma_code = dmaarea_combo / 1000;
            area_code = dmaarea_combo % 1000;
            us_area_codes = [ dma_code, area_code ]
            @iter_pos += 3 unless @iter_pos.nil?
        else
            us_area_codes = [ nil, nil ]  # Ensure that TimeZone is always at the same offset
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
        ] +
            us_area_codes +
            [ TimeZone["#{CountryCode[code]}#{region}"] || TimeZone["#{CountryCode[code]}"] ]
    end

    public

    # Search the GeoIP database for the specified host, returning city info.
    #
    # +hostname+ is a String holding the host's DNS name or numeric IP address.
    # Return an array of twelve or fourteen elements:
    # * The host or IP address string as requested
    # * The IP address string after looking up the host
    # * The GeoIP country-ID as an integer
    # * The ISO3166-1 two-character country code
    # * The ISO3166-2 three-character country code
    # * The ISO3166 English-language name of the country
    # * The two-character continent code
    # * The region name
    # * The city name
    # * The postal code
    # * The latitude
    # * The longitude
    # * The USA dma_code and area_code, if available (REV1 City database)
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
        read_city(pos, hostname, ip)
    end

    # Search a ISP GeoIP database for the specified host, returning the ISP
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
        if @databaseType != GEOIP_ISP_EDITION
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
          return [$1, $2]
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
      
    def iptonum(ip)     # Convert numeric IP address to integer
        if ip.kind_of?(String) &&
            ip =~ /^([0-9]+)\.([0-9]+)\.([0-9]+)\.([0-9]+)$/
            ip = be_to_ui(Regexp.last_match().to_a.slice(1..4))
        end
        ip
    end

    def seek_record(ipnum)
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
    def be_to_ui(s)
        s.inject(0) { |m, o|
            (m << 8) + o.to_i
        }
    end

    # Same for little-endian
    def le_to_ui(s)
        be_to_ui(s.reverse)
    end

    # reads +length+ bytes from +offset+ as atomically as possible
    # if IO.pread is available, it'll use that (making it both multithread
    # and multiprocess-safe).  Otherwise we'll use a mutex to synchronize
    # access (only providing protection against multiple threads, but not
    # file descriptors shared across multiple processes).
    def atomic_read(length, offset)
        if @mutex
            @mutex.synchronize {
                @file.seek(offset)
                @file.read(length)
            }
        else
            IO.pread(@file.fileno, length, offset)
        end
    end
end

if $0 == __FILE__
    data = '/usr/share/GeoIP/GeoIP.dat'
    data = ARGV.shift if ARGV[0] =~ /\.dat\Z/
    g = GeoIP.new data

    req = ([GeoIP::GEOIP_CITY_EDITION_REV1, GeoIP::GEOIP_CITY_EDITION_REV0].include?(g.databaseType)) ? :city : :country
    ARGV.each { |a|
        p g.send(req, a)
    }
end

