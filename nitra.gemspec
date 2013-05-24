spec = Gem::Specification.new do |s|
  s.name = 'nitra'
  s.version = '0.9.5'
  s.platform = Gem::Platform::RUBY
  s.license = "MIT"
  s.homepage = "http://github.com/powershop/nitra"
  s.summary = "Multi-process rspec runner"
  s.description = "Multi-process rspec runner"
  s.authors = ["Roger Nesbitt", "Andy Newport", "Jeremy Wells", "Will Bryant"]
  s.email = "roger@youdo.co.nz"

  s.bindir = 'bin'
  s.executables = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_path     = "lib"
  s.files = %w(README.md lib/nitra.rb bin/nitra) + Dir['lib/**/*.rb']
  s.test_files = `git ls-files -- {spec,features}/*`.split("\n")

  s.add_dependency('cucumber', '>= 1.1.9')
  s.add_dependency('rspec', '~> 2.12')

  s.has_rdoc = false
end
