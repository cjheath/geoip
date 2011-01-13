# -*- encoding: utf-8 -*-

Gem::Specification.new do |s|
  s.name = %q{geoip}
  s.version = "0.8.9"

  s.required_rubygems_version = Gem::Requirement.new(">= 0") if s.respond_to? :required_rubygems_version=
  s.authors = ["Clifford Heath", "Roland Moriz"]
  s.date = %q{2011-01-13}
  s.description = %q{GeoIP searches a GeoIP database for a given host or IP address, and
returns information about the country where the IP address is allocated,
and the city, ISP and other information, if you have that database version.}
  s.email = ["clifford.heath@gmail.com", "rmoriz@gmail.com"]
  s.extra_rdoc_files = ["History.txt", "Manifest.txt"]
  s.files = ["History.txt", "Manifest.txt", "README.rdoc", "Rakefile", "lib/geoip.rb", "test/test_geoip.rb", "test/test_helper.rb"]
  s.homepage = %q{http://github.com/cjheath/geoip}
  s.rdoc_options = ["--main", "README.rdoc"]
  s.require_paths = ["lib"]
  s.rubyforge_project = %q{geoip}
  s.rubygems_version = %q{1.3.7}
  s.summary = %q{GeoIP searches a GeoIP database for a given host or IP address, and returns information about the country where the IP address is allocated, and the city, ISP and other information, if you have that database version.}
  s.test_files = ["test/test_geoip.rb", "test/test_helper.rb"]

  if s.respond_to? :specification_version then
    current_version = Gem::Specification::CURRENT_SPECIFICATION_VERSION
    s.specification_version = 3

    if Gem::Version.new(Gem::VERSION) >= Gem::Version.new('1.2.0') then
      s.add_development_dependency(%q<rubyforge>, [">= 2.0.4"])
      s.add_development_dependency(%q<hoe>, [">= 2.6.2"])
    else
      s.add_dependency(%q<rubyforge>, [">= 2.0.4"])
      s.add_dependency(%q<hoe>, [">= 2.6.2"])
    end
  else
    s.add_dependency(%q<rubyforge>, [">= 2.0.4"])
    s.add_dependency(%q<hoe>, [">= 2.6.2"])
  end
end
