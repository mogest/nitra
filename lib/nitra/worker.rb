require 'stringio'
require 'tempfile'

class Nitra::Worker
  attr_reader :runner_id, :worker_number, :configuration, :channel, :io

  def initialize(runner_id, worker_number, configuration)
    @runner_id = runner_id
    @worker_number = worker_number
    @configuration = configuration
    @first_file_has_been_run = false

    ENV["TEST_ENV_NUMBER"] = (worker_number + 1).to_s

    # RSpec doesn't like it when you change the IO between invocations.
    # So we make one object and flush it after every invocation.
    @io = StringIO.new
  end

  def fork_and_run
    client, server = Nitra::Channel.pipe

    fork do
      server.close
      @channel = client
      run
    end

    client.close
    server
  end

  protected
  def run
    trap("SIGTERM") { Process.kill("SIGKILL", Process.pid) }
    trap("SIGINT") { Process.kill("SIGKILL", Process.pid) }

    debug "Started"

    connect_to_database

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
    Rails.cache.reset if Rails.cache.respond_to?(:reset)
  end

  ##
  # Process the file.
  #
  # 2 things to note here
  # 1) The first file is run in this process so that all of the support code is loaded.
  # Subsequent files fork.
  # 2)There's two sets of data we're interested in, the output from the test framework, and any other output.
  # We capture the framework's output in the @io object and send that up to the runner in a results message.
  # Anything else we capture off the stdout/stderr in a buffer and fire off in the stdout message.
  #
  def process_file(filename)
    stdout_buffer = ""
    if @first_file_has_been_run
      stdout_buffer << run_file_with_fork(filename)
    else
      stdout_buffer << run_file_without_fork(filename)
      @first_file_has_been_run = true
    end
    channel.write("command" => "stdout", "process" => "test framework", "filename" => filename, "text" => stdout_buffer) unless stdout_buffer.empty?
  end

  ##
  # Runs a file in this process.
  # Record the standard outputs so we can feed them back to the runner.
  #
  def run_file_without_fork(filename)
    stdout_buffer = StringIO.new
    $stdout = stdout_buffer
    $stderr = stdout_buffer
    if filename =~ /.*\.feature$/
      run_cucumber_file(filename)
    else
      run_rspec_file(filename)
      RSpec.reset
    end
    stdout_buffer.rewind
    stdout_buffer.read
  ensure
    # Clear anything we've recorded using @io
    io.string = ""
    # Reset stdout
    $stderr = STDERR
    $stdout = STDOUT
  end

  ##
  # Runs the file in a forked process.
  # Records the standard output using a pipe between the processes so we can feed it back to the runner.
  #
  def run_file_with_fork(filename)
    rd, wr = IO.pipe
    pid = fork do
      rd.close
      $stdout.reopen(wr)
      $stderr.reopen(wr)
      run_file(filename)
      Kernel.exit!  # at_exit hooks shouldn't be run, otherwise we don't get any benefit from forking because we gotta reload a whole bunch of shit...
    end
    wr.close
    stdout_buffer = ""
    loop do
      IO.select([rd])
      text = rd.read
      break if text.nil? || text.length.zero?
      stdout_buffer << text
    end
    rd.close
    Process.wait(pid) if pid
    stdout_buffer
  end

  ##
  # Picks a method based on filename.
  # This should be abstracted away as you can only use one framework at a time.
  #
  def run_file(filename)
    if filename =~ /.*\.feature$/
      run_cucumber_file(filename)
    else
      run_rspec_file(filename)
    end
  end

  ##
  # Run an rspec file and write the results back to the runner.
  #
  def run_rspec_file(filename)
    begin
      result = RSpec::Core::CommandLine.new(["-f", "p", filename]).run(io, io)
    rescue LoadError
      io << "\nCould not load file #{filename}\n\n"
      result = 1
    end
    channel.write("command" => "result", "filename" => filename, "return_code" => result.to_i, "text" => io.string)
  end

  ##
  # Run a Cucumber file and write the results back to the runner.
  #
  def run_cucumber_file(filename)
    @cuke_runtime ||= Cucumber::ResetableRuntime.new  # This runtime gets reused, this is important as it's the part that loads the steps...
    begin
      result = 1
      cuke_config = Cucumber::Cli::Configuration.new(io, io)
      cuke_config.parse!(["--no-color", filename])
      @cuke_runtime.configure(cuke_config)
      @cuke_runtime.reset
      @cuke_runtime.run!
      result = 0 unless @cuke_runtime.results.failure?
    rescue LoadError
      io << "\nCould not load file #{filename}\n\n"
    end
    channel.write("command" => "result", "filename" => filename, "return_code" => result.to_i, "text" => io.string)
  end
end
