require 'optparse'

class Nitra::CommandLine
  attr_reader :configuration

  def initialize(configuration, argv)
    @configuration = configuration
    configuration.framework = :rspec

    OptionParser.new(argv) do |opts|
      opts.banner = "Usage: nitra [options] [spec_filename [...]]"

      opts.on("-c", "--cpus NUMBER", Integer, "Specify the number of CPUs to use on the host, or if specified after a --slave, on the slave") do |n|
        configuration.set_process_count n
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

      opts.on("--slave CONNECTION_COMMAND", String, "Provide a command that executes \"nitra --slave-mode\" on another host") do |connection_command|
        configuration.slaves << {:command => connection_command, :cpus => nil}
      end

      opts.on("--slave-mode", "Run in slave mode; ignores all other command-line options") do
        configuration.slave_mode = true
      end

      opts.on("--debug", "Print debug output") do
        configuration.debug = true
      end

      opts.on("--cucumber", "Switch test framework from rspec to cucumber") do
        configuration.framework = :cucumber
      end

      opts.on_tail("-h", "--help", "Show this message") do
        puts opts
        exit
      end
    end.parse!
  end
end
