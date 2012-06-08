require 'optparse'

class Nitra::CommandLine
  attr_reader :configuration

  def initialize(configuration, argv)
    @configuration = configuration

    OptionParser.new(argv) do |opts|
      opts.banner = "Usage: nitra [options] [spec_filename [...]]"

      opts.on("-c", "--cpus NUMBER", Integer, "Specify the number of CPUs to use, defaults to 4") do |n|
        configuration.process_count = n
      end

      opts.on("-e", "--environment STRING", String, "The Rails environment to use, defaults to 'nitra'") do |environment|
        configuration.environment = environment
      end

      opts.on("--load", "Load schema into database before running specs") do
        configuration.load_schema = true
      end

      opts.on("--migrate", "Migrate database before running specs") do
        configuration.migrate = true
      end

      opts.on("-q", "--quiet", "Quiet; don't display progress bar") do
        configuration.quiet = true
      end

      opts.on("-p", "--print-failures", "Print failures immediately when they occur") do
        configuration.print_failures = true
      end

      opts.on("--debug", "Print debug output") do
        configuration.debug = true
      end

      opts.on_tail("-h", "--help", "Show this message") do
        puts opts
        exit
      end
    end.parse!
  end
end
