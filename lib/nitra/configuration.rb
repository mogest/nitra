class Nitra::Configuration
  attr_accessor :load_schema, :migrate, :debug, :quiet, :print_failures, :fork_for_each_file
  attr_accessor :process_count, :environment

  def initialize
    self.process_count = 4
    self.environment = "nitra"
    self.fork_for_each_file = true
  end
end
