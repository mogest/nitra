class Nitra::Configuration
  attr_accessor :load_schema, :migrate, :debug, :quiet, :print_failures, :fork_for_each_file
  attr_accessor :process_count, :environment, :slaves, :slave_mode

  def initialize
    self.environment = "nitra"
    self.fork_for_each_file = true
    self.slaves = []
  end

  def calculate_default_process_count
    self.process_count ||= Nitra::Utils.processor_count
  end

  def set_process_count(n)
    if slaves.empty?
      self.process_count = n
    else
      slaves.last[:cpus] = n
    end
  end
end
