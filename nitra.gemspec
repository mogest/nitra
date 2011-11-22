spec = Gem::Specification.new do |s|
  s.name = 'nitra'
  s.version = '0.9.1'
  s.summary = "Multi-process rspec runner"
  s.description = "Multi-process rspec runner"
  s.files = %w(README lib/nitra.rb bin/nitra)
  s.executables << "nitra"
  s.has_rdoc = false
  s.author = "Roger Nesbitt"
  s.email = "roger@youdo.co.nz"
end
