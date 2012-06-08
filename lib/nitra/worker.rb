require 'stringio'
require 'tempfile'

class Nitra::Worker
  attr_reader :runner_id, :worker_number, :configuration, :channel

  def initialize(runner_id, worker_number, configuration)
    @runner_id = runner_id
    @worker_number = worker_number
    @configuration = configuration
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

    debug "started"

    ENV["TEST_ENV_NUMBER"] = (worker_number + 1).to_s

    # Find the database config for this TEST_ENV_NUMBER and manually initialise a connection.
    database_config = YAML.load(ERB.new(IO.read("#{Rails.root}/config/database.yml")).result)[ENV["RAILS_ENV"]]
    ActiveRecord::Base.establish_connection(database_config)
    Rails.cache.reset if Rails.cache.respond_to?(:reset)

    # RSpec doesn't like it when you change the IO between invocations.  So we make one object and flush it
    # after every invocation.
    io = StringIO.new

    # When rspec processes the first spec file, it does initialisation like loading in fixtures into the
    # database.  If we're forking for each file, we need to initialise first so it doesn't try to initialise
    # for every single file.
    if configuration.fork_for_each_file
      debug "running empty spec to make rspec run its initialisation"
      file = Tempfile.new("nitra")
      begin
        file.write("require 'spec_helper'; describe('nitra preloading') { it('preloads the fixtures') { 1.should == 1 } }\n")
        file.close
        output = Nitra::Utils.capture_output do
          RSpec::Core::CommandLine.new(["-f", "p", file.path]).run(io, io)
        end
        channel.write("command" => "stdout", "process" => "init rspec", "text" => output) unless output.empty?
      ensure
        file.close unless file.closed?
        file.unlink
      end
      RSpec.reset
      io.string = ""
    end

    # Loop until our master tells us we're finished.
    loop do
      debug "announcing availability"
      channel.write("command" => "ready")

      debug "waiting for next job"
      data = channel.read
      if data.nil? || data["command"] == "close"
        debug "channel closed, exiting"
        exit
      end

      filename = data.fetch("filename").chomp
      debug "starting to process #{filename}"

      perform_rspec_for_filename = lambda do
        begin
          result = RSpec::Core::CommandLine.new(["-f", "p", filename]).run(io, io)
        rescue LoadError
          io << "\nCould not load file #{filename}\n\n"
          result = 1
        end

        channel.write("command" => "result", "filename" => filename, "return_code" => result.to_i, "text" => io.string)
      end

      if configuration.fork_for_each_file
        rd, wr = IO.pipe
        pid = fork do
          rd.close
          $stdout.reopen(wr)
          $stderr.reopen(wr)
          perform_rspec_for_filename.call
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
      else
        stdout_buffer = Nitra::Utils.capture_output do
          perform_rspec_for_filename.call
        end
        io.string = ""
        RSpec.reset
      end
      channel.write("command" => "stdout", "process" => "rspec", "filename" => filename, "text" => stdout_buffer) unless stdout_buffer.empty?

      debug "#{filename} processed"
    end
  end

  def debug(*text)
    channel.write(
      "command" => "debug",
      "text" => "worker #{runner_id}.#{worker_number}: #{text.join}"
    ) if configuration.debug
  end
end
