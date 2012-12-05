require 'optparse'

module Nitra
  class CommandLine
    attr_reader :configuration

    def initialize(configuration, argv)
      @configuration = configuration

      OptionParser.new do |opts|
        opts.banner = "Usage: nitra [options] [spec_filename [...]]"

        opts.on("-c", "--cpus NUMBER", Integer, "Specify the number of CPUs to use on the host, or if specified after a --slave, on the slave") do |n|
          configuration.set_process_count n
        end

        opts.on("--cucumber", "Add full cucumber run, causes any files you list manually to be ignored") do
          configuration.add_framework "cucumber"
        end

        opts.on("--debug", "Print debug output") do
          configuration.debug = true
        end

        opts.on("-p", "--print-failures", "Print failures immediately when they occur") do
          configuration.print_failures = true
        end

        opts.on("-q", "--quiet", "Quiet; don't display progress bar") do
          configuration.quiet = true
        end

        opts.on("--rake-after-runner task:1,task:2,task:3", Array, "The list of rake tasks to run, once per runner, in the runner's environment, just before the runner exits") do |rake_tasks|
          configuration.add_rake_task(:after_runner, rake_tasks)
        end

        opts.on("--rake-before-runner task:1,task:2,task:3", Array, "The list of rake tasks to run, once per runner, in the runner's environment, after the runner starts") do |rake_tasks|
          configuration.add_rake_task(:before_runner, rake_tasks)
        end

        opts.on("--rake-before-worker task:1,task:2,task:3", Array, "The list of rake tasks to run, once per worker, in the worker's environment, before the worker starts") do |rake_tasks|
          configuration.add_rake_task(:before_worker, rake_tasks)
        end

        opts.on("--slave-mode", "Run in slave mode; ignores all other command-line options") do
          configuration.slave_mode = true
        end

        opts.on("--slave CONNECTION_COMMAND", String, "Provide a command that executes \"nitra --slave-mode\" on another host") do |connection_command|
          configuration.add_slave connection_command
        end

        opts.on("--rspec", "Add full rspec run, causes any files you list manually to be ignored") do
          configuration.add_framework "rspec"
        end

        opts.on("-e", "--environment ENV", String, "Set the RAILS_ENV to load") do |env|
          configuration.environment = env
        end

        opts.on_tail("-h", "--help", "Show this message") do
          puts opts
          exit
        end
      end.parse!(argv)

      configuration.set_default_framework
    end
  end
end
