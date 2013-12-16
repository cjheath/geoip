require 'rubygems'
require 'rake'

require 'jeweler'
require './lib/geoip'

Jeweler::Tasks.new do |gem|
  # gem is a Gem::Specification... see http://docs.rubygems.org/read/chapter/20 for more options
  gem.name = "geoip"
  gem.version = GeoIP::VERSION
  gem.homepage = "http://github.com/cjheath/geoip"
  gem.license = "LGPL"
  gem.summary = %Q{GeoIP searches a GeoIP database for a given host or IP address, and returns information about the country where the IP address is allocated, and the city, ISP and other information, if you have that database version.}
  gem.description = %Q{GeoIP searches a GeoIP database for a given host or IP address, and
returns information about the country where the IP address is allocated,
and the city, ISP and other information, if you have that database version.}
  gem.email = %w[clifford.heath@gmail.com rmoriz@gmail.com]
  gem.authors = ["Clifford Heath", "Roland Moriz"]
  # Include your dependencies below. Runtime dependencies are required when using your gem,
  # and development dependencies are only needed for development (ie running rake tasks, tests, etc)
  #  gem.add_runtime_dependency 'jabber4r', '> 0.1'
  #  gem.add_development_dependency 'rspec', '> 1.2.3'
  gem.files.exclude "website/**/*.*", "script/*", "config/*"
end
Jeweler::RubygemsDotOrgTasks.new

require 'rake/testtask'
Rake::TestTask.new(:test) do |test|
  test.libs << 'lib' << 'test'
  test.pattern = 'test/**/test_*.rb'
  test.verbose = true
end
task :default => :test

require 'rdoc/task'
Rake::RDocTask.new do |rdoc|
  rdoc.rdoc_dir = 'rdoc'
  rdoc.title = "geoip #{GeoIP::VERSION}"
  rdoc.rdoc_files.include('README.rdoc')
  rdoc.rdoc_files.include('History.rdoc')
  rdoc.rdoc_files.include('lib/**/*.rb')
end

desc 'Generate website files'
task :website_generate do
  sh %q{ruby script/txt2html website/index.txt > website/index.html}
end

desc 'Upload website files via rsync'
task :website_upload do
  local_dir  = 'website'
  website_config = YAML.load(File.read("config/website.yml"))
  host       = website_config["host"]
  host       = host ? "#{host}:" : ""
  remote_dir = website_config["remote_dir"]
  sh %{rsync -aCv #{local_dir}/ #{host}#{remote_dir}}
end

