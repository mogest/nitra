require 'stringio'
require 'tempfile'

class Nitra::Worker
  attr_reader :runner_id, :worker_number, :configuration, :channel, :io, :framework

  def initialize(runner_id, worker_number, configuration)
    @runner_id = runner_id
    @worker_number = worker_number
    @configuration = configuration
    @framework = configuration.framework_shim
    @forked_worker = nil

    ENV["TEST_ENV_NUMBER"] = (worker_number + 1).to_s

    # RSpec doesn't like it when you change the IO between invocations.
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
  def run
    trap("SIGTERM") { Process.kill("SIGKILL", Process.pid) }
    trap("SIGINT") { Process.kill("SIGKILL", Process.pid) }

    debug "Started, using TEST_ENV_NUMBER #{ENV['TEST_ENV_NUMBER']}"
    connect_to_database

    preload_framework

    # Loop until our runner passes us a message from the master to tells us we're finished.
    loop do
      debug "Announcing availability"
      channel.write("command" => "ready")

      debug "Waiting for next job"
      data = channel.read
      if data.nil? || data["command"] == "close"
        debug "Channel closed, exiting"
        exit
      end

      filename = data.fetch("filename").chomp

      debug "Starting to process #{filename}"
      process_file(filename)
      debug "#{filename} processed"
    end
  end

  def preload_framework
    debug "running empty spec/feature to make framework run its initialisation"
    file = Tempfile.new("nitra")
    begin
      file.write(@framework.minimal_file)
      file.close
      output = Nitra::Utils.capture_output do
        run_file(file.path, true)
      end
      channel.write("command" => "stdout", "process" => "init framework", "text" => output) unless output.empty?
    ensure
      file.close unless file.closed?
      file.unlink
      if configuration.framework == :cucumber
        @cuke_runtime.reset
      else
        RSpec.reset
      end
      io.string = ""
    end
  end

  ##
  # Sends debug data up to the runner.
  #
  def debug(*text)
    if configuration.debug
      channel.write("command" => "debug", "text" => "worker #{runner_id}.#{worker_number}: #{text.join}")
    end
  end

  ##
  # Find the database config for this TEST_ENV_NUMBER and manually initialise a connection.
  #
  def connect_to_database
    database_config = YAML.load(ERB.new(IO.read("#{Rails.root}/config/database.yml")).result)[ENV["RAILS_ENV"]]
    ActiveRecord::Base.establish_connection(database_config)
    debug("Connected to database #{database_config["database"]}")
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
    rd, wr = IO.pipe
    @forked_worker = fork do
      trap('USR1'){ exit!(1) }  # at_exit hooks will be run in the parent.
      $stdout.reopen(wr)
      $stderr.reopen(wr)
      rd.close
      run_file(filename)
      wr.close
      Kernel.exit!  # at_exit hooks will be run in the parent.
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
    Process.wait(@forked_worker) if @forked_worker

    @forked_worker = nil

    channel.write("command" => "stdout", "process" => "test framework", "filename" => filename, "text" => output) unless output.empty?
  end

  def run_file(filename, preload = false)
    if configuration.framework == :cucumber
      run_cucumber_file(filename, preload)
    else
      run_rspec_file(filename, preload)
    end
  end

  ##
  # Run an rspec file and write the results back to the runner.
  #
  # Doesn't write back to the runner if we mark the run as preloading.
  #
  def run_rspec_file(filename, preloading = false)
    begin
      result = RSpec::Core::CommandLine.new(["-f", "p", filename]).run(io, io)
    rescue LoadError
      io << "\nCould not load file #{filename}\n\n"
      result = 1
    end
    if preloading
      puts io.string
    else
      channel.write("command" => "result", "filename" => filename, "return_code" => result.to_i, "text" => io.string)
    end
  end

  ##
  # Run a Cucumber file and write the results back to the runner.
  #
  # Doesn't write back to the runner if we mark the run as preloading.
  #
  def run_cucumber_file(filename, preloading = false)
    @cuke_runtime ||= Cucumber::ResetableRuntime.new  # This runtime gets reused, this is important as it's the part that loads the steps...
    begin
      result = 1
      cuke_config = Cucumber::Cli::Configuration.new(io, io)
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
      channel.write("command" => "result", "filename" => filename, "return_code" => result.to_i, "text" => io.string)
    end
  end

  def interrupt_forked_worker_and_exit
    Process.kill('USR1', @forked_worker) if @forked_worker
    Process.waitall
  ensure
    exit(1)
  end
end
