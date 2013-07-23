Gem::Specification.new do |s|
  s.name        = 'taco'
  s.version     = '1.1.0'
  s.date        = Time.now.strftime("%Y-%m-%d")
  s.summary     = "A very simple issue tracking system with a commandline interface"
  s.description = "A command line driven issue tracking system based on a JSON (text) file back-end"
  s.authors     = ["Mike Partelow"]
  s.email       = 'rubygems@shoehater.com'
  s.files       = ['lib/taco.rb']
  s.homepage    = 'http://github.com/mikepartelow/taco'
  
  s.required_ruby_version = '>= 1.9.3'
  
  s.executables << 'taco'
  s.add_runtime_dependency 'commander'
end