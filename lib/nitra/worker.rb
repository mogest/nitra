require 'stringio'
require 'tempfile'

module Nitra::Workers
  class Worker
    attr_reader :runner_id, :worker_number, :configuration, :channel, :io

    def initialize(runner_id, worker_number, configuration)
      @runner_id = runner_id
      @worker_number = worker_number
      @configuration = configuration
      @forked_worker_pid = nil

      ENV["TEST_ENV_NUMBER"] = worker_number.to_s

      # Frameworks don't like it when you change the IO between invocations.
      # So we make one object and flush it after every invocation.
      @io = StringIO.new
    end


    def fork_and_run
      client, server = Nitra::Channel.pipe

      pid = fork do
        # This is important. We don't want anything bubbling up to the master that we didn't send there.
        # We reopen later to get the output from the framework run.
        $stdout.reopen('/dev/null', 'a')
        $stderr.reopen('/dev/null', 'a')

        trap("USR1") { interrupt_forked_worker_and_exit }

        server.close
        @channel = client
        run
      end

      client.close

      [pid, server]
    end

    protected
    def load_environment
      raise 'Subclasses must impliment this method.'
    end

    def minimal_file
      raise 'Subclasses must impliment this method.'
    end

    def run_file(filename, preload = false)
      raise 'Subclasses must impliment this method.'
    end

    def clean_up
      raise 'Subclasses must impliment this method.'
    end

    def run
      trap("SIGTERM") { Process.kill("SIGKILL", Process.pid) }
      trap("SIGINT") { Process.kill("SIGKILL", Process.pid) }

      debug "Started, using TEST_ENV_NUMBER #{ENV['TEST_ENV_NUMBER']}"
      connect_to_database
      preload_framework

      # Loop until our runner passes us a message from the master to tells us we're finished.
      loop do
        debug "Announcing availability"
        channel.write("command" => "ready", "framework" => framework_name, "worker_number" => worker_number)
        debug "Waiting for next job"
        data = channel.read
        if data.nil? || data["command"] == "close"
          debug "Channel closed, exiting"
          exit
        elsif data['command'] == "process"
          filename = data["filename"].chomp
          process_file(filename)
        end
      end
    end

    def preload_framework
      debug "running empty spec/feature to make framework run its initialisation"
      file = Tempfile.new("nitra")
      begin
        load_environment
        file.write(minimal_file)
        file.close

        output = Nitra::Utils.capture_output do
          run_file(file.path, true)
        end

        channel.write("command" => "stdout", "process" => "init framework", "text" => output, "worker_number" => worker_number) unless output.empty?
      ensure
        file.close unless file.closed?
        file.unlink
        io.string = ""
      end
      clean_up
    end

  ##
  # Find the database config for this TEST_ENV_NUMBER and manually initialise a connection.
  #
  def connect_to_database
    ## Config files are read at load time. Since we load rails in one env then change some flags to get different
    ## environments through forking we need always reload our database config...
    ActiveRecord::Base.configurations = YAML.load(ERB.new(IO.read("#{Rails.root}/config/database.yml")).result)

    ActiveRecord::Base.establish_connection
    debug("Connected to database #{ActiveRecord::Base.connection.current_database}")

    Rails.cache.reset if Rails.cache.respond_to?(:reset)
  end

    ##
    # Process the file, forking before hand.
    #
    # There's two sets of data we're interested in, the output from the test framework, and any other output.
    # 1) We capture the framework's output in the @io object and send that up to the runner in a results message.
    # This happens in the run_x_file methods.
    # 2) Anything else we capture off the stdout/stderr using the pipe and fire off in the stdout message.
    #
    def process_file(filename)
      debug "Starting to process #{filename}"

      rd, wr = IO.pipe
      @forked_worker_pid = fork do
        trap('USR1') { exit! }  # at_exit hooks will be run in the parent.
        $stdout.reopen(wr)
        $stderr.reopen(wr)
        rd.close
        run_file(filename)
        wr.close
        exit!  # at_exit hooks will be run in the parent.
      end
      wr.close
      output = ""
      loop do
        IO.select([rd])
        text = rd.read
        break if text.nil? || text.length.zero?
        output << text
      end
      rd.close
      Process.wait(@forked_worker_pid) if @forked_worker_pid

      @forked_worker_pid = nil

      channel.write("command" => "stdout", "process" => "test framework", "filename" => filename, "text" => output, "worker_number" => worker_number) unless output.empty?
      debug "#{filename} processed"
    end

    ##
    # Return the framework name of this worker
    #
    def framework_name
      self.class.name.split("::").last.downcase
    end

    ##
    # Interrupts the forked worker cleanly and exits
    #
    def interrupt_forked_worker_and_exit
      Process.kill('USR1', @forked_worker_pid) if @forked_worker_pid
      Process.waitall
      exit
    end

    ##
    # Sends debug data up to the runner.
    #
    def debug(*text)
      if configuration.debug
        channel.write("command" => "debug", "text" => "worker #{runner_id}.#{worker_number}: #{text.join}", "worker_number" => worker_number)
      end
    end
  end

  class Cucumber < Worker
    def self.files
      Dir["features/**/*.feature"].sort_by {|f| File.size(f)}.reverse
    end

    def self.filename_match?(filename)
      filename =~ /\.feature/
    end

    def initialize(runner_id, worker_number, configuration)
      super(runner_id, worker_number, configuration)
    end

    def load_environment
      require 'cucumber'
      require 'nitra/ext/cucumber'
    end

    def minimal_file
      <<-EOS
      Feature: cucumber preloading
        Scenario: a fake scenario
          Given every step is unimplemented
          When we run this file
          Then Cucumber will load it's environment
      EOS
    end

    ##
    # Run a Cucumber file and write the results back to the runner.
    #
    # Doesn't write back to the runner if we mark the run as preloading.
    #
    def run_file(filename, preloading = false)
      @cuke_runtime ||= ::Cucumber::ResetableRuntime.new  # This runtime gets reused, this is important as it's the part that loads the steps...
      begin
        result = 1
        cuke_config = ::Cucumber::Cli::Configuration.new(io, io)
        cuke_config.parse!(["--no-color", "--require", "features", filename])
        @cuke_runtime.configure(cuke_config)
        @cuke_runtime.run!
        result = 0 unless @cuke_runtime.results.failure?
      rescue LoadError
        io << "\nCould not load file #{filename}\n\n"
      end
      if preloading
        puts(io.string)
      else
        channel.write("command" => "result", "filename" => filename, "return_code" => result.to_i, "text" => io.string, "worker_number" => worker_number)
      end
    end

    def clean_up
      @cuke_runtime.reset
    end
  end

  class Rspec < Worker
    def self.files
      Dir["spec/**/*_spec.rb"].sort_by {|f| File.size(f)}.reverse
    end

    def self.filename_match?(filename)
      filename =~ /_spec\.rb/
    end

    def initialize(runner_id, worker_number, configuration)
      super(runner_id, worker_number, configuration)
    end

    def load_environment
      require 'spec/spec_helper'
      RSpec::Core::Runner.disable_autorun!
    end

    def minimal_file
      <<-EOS
      require 'spec_helper'
      describe('nitra preloading') do
        it('preloads the fixtures') do
          1.should == 1
        end
      end
      EOS
    end

    ##
    # Run an rspec file and write the results back to the runner.
    #
    # Doesn't write back to the runner if we mark the run as preloading.
    #
    def run_file(filename, preloading = false)
      begin
        result = RSpec::Core::CommandLine.new(["-f", "p", filename]).run(io, io)
      rescue LoadError
        io << "\nCould not load file #{filename}\n\n"
        result = 1
      end
      if preloading
        puts io.string
      else
        channel.write("command" => "result", "filename" => filename, "return_code" => result.to_i, "text" => io.string, "worker_number" => worker_number)
      end
    end

    def clean_up
      RSpec.reset
    end
  end

  WORKERS = {"rspec" => Nitra::Workers::Rspec, "cucumber" => Nitra::Workers::Cucumber}
end
