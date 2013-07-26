require 'rspec/core/rake_task'

task :default => :spec

RSpec::Core::RakeTask.new(:spec) do |t|
  t.fail_on_error = false
end

task :release, [:version] do |t, args|
  GEMSPEC_PATH = 'taco.gemspec'
  TACO_RB_PATH = 'lib/taco.rb'
  
  new_version = args[:version]
  
  abort "Error: expecting X.Y.Z for version" unless new_version =~ /^\d+\.\d+\.\d+$/

  puts "Modifying #{TACO_RB_PATH}"
  old_taco_rb = open(TACO_RB_PATH) { |f| f.read }
  new_taco_rb = old_taco_rb.gsub /program :version, '\d+\.\d+\.\d+'/, "program :version, '#{new_version}'"
  open(TACO_RB_PATH, 'w') { |f| f.write(new_taco_rb) }
  
  puts "Building gem for version: #{new_version}"
  gemspec = open(GEMSPEC_PATH) { |f| f.read }
  
  gemspec =~ /s\.version\s+=\s+'(\d+\.\d+\.\d+)'/
  old_version = $1
  
  puts "Old gem version: #{old_version}"
  gemspec.gsub! /(s\.version\s+=\s+)'(\d+\.\d+\.\d+)'/, "\\1'#{new_version}'"
  
  open(GEMSPEC_PATH, 'w') { |f| f.write(gemspec) }
  
  sh "gem build #{GEMSPEC_PATH}"
end

