require 'rspec/core/rake_task'

task :default => :spec

RSpec::Core::RakeTask.new(:spec) do |t|
  t.fail_on_error = false
end

task :release, [:version] do |t, args|
  GEM_DIR = 'gem'
  GEMSPEC_FILE = 'taco.gemspec'
  GEMSPEC_PATH = GEM_DIR + '/' + GEMSPEC_FILE
  
  new_version = args[:version]
  
  abort "Error: expecting X.Y.Z for version" unless new_version =~ /^\d+\.\d+\.\d+$/
  
  puts "Building gem for version: #{new_version}"
  gemspec = open(GEMSPEC_PATH) { |f| f.read }
  
  gemspec =~ /s\.version\s+=\s+'(\d+\.\d+\.\d+)'/
  old_version = $1
  
  puts "Old gem version: #{old_version}"
  gemspec.gsub! /(s\.version\s+=\s+)'(\d+\.\d+\.\d+)'/, "\\1'#{new_version}'"
  
  open(GEMSPEC_PATH, 'w') { |f| f.write(gemspec) }
  
  sh "cd #{GEM_DIR} && gem build #{GEMSPEC_FILE}"
end

