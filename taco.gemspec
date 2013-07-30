Gem::Specification.new do |s|
  s.name        = 'taco_it'
  s.version     = '1.4.0'
  s.date        = Time.now.strftime("%Y-%m-%d")
  s.summary     = "Taco Issue Tracker: A CLI Issue Tracker with JSON/filesystem backend"
  s.description = "A command line driven issue tracking system based on a JSON (text) file back-end"
  s.authors     = ["Mike Partelow"]
  s.email       = 'rubygems@shoehater.com'
  s.files       = Dir['lib/*'] + Dir['lib/taco/*'] + Dir['lib/taco/defaults/*']
  s.homepage    = 'http://github.com/mikepartelow/taco'
  
  s.required_ruby_version = '>= 1.9.3'
  
  s.executables << 'taco'
  s.add_runtime_dependency 'commander'
end
