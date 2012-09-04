require 'stringio'

class Nitra::Runner
  attr_reader :configuration, :server_channel, :runner_id, :framework, :workers

  def initialize(configuration, server_channel, runner_id)
    @configuration = configuration
    @server_channel = server_channel
    @runner_id = runner_id
    @framework = configuration.framework
    @workers = {}

    configuration.calculate_default_process_count
    server_channel.raise_epipe_on_write_error = true
  end

  def run
    ENV["RAILS_ENV"] = configuration.environment

    load_databases

    load_rails_environment

    start_workers

    trap("SIGTERM") { $aborted = true }
    trap("SIGINT") { $aborted = true }

    hand_out_files_to_workers
  rescue Errno::EPIPE
  ensure
    trap("SIGTERM", "DEFAULT")
    trap("SIGINT", "DEFAULT")
  end

  protected

  def load_databases
    if configuration.load_schema || configuration.migrate
      require 'rake'
      Rake.load_rakefile("Rakefile")
    end

    if configuration.load_schema
      debug "Initializing databases..."
      rd, wr = IO.pipe
      (1..configuration.process_count).collect do |index|
        fork do
          ENV["TEST_ENV_NUMBER"] = index.to_s
          rd.close
          $stdout.reopen(wr)
          $stderr.reopen(wr)
          Rake::Task["db:drop"].invoke
          Rake::Task["db:create"].invoke
          Rake::Task["db:schema:load"].invoke
        end
      end
      wr.close
      output = ""
      loop do
        IO.select([rd])
        text = rd.read
        break if text.nil? || text.length.zero?
        output.concat text
      end
      rd.close
      server_channel.write("command" => "stdout", "process" => "db:schema:load", "text" => output)
      Process.waitall
    end

    if configuration.migrate
      debug "Migrating databases..."
      rd, wr = IO.pipe
      (1..configuration.process_count).collect do |index|
        fork do
          ENV["TEST_ENV_NUMBER"] = index.to_s
          rd.close
          $stdout.reopen(wr)
          $stderr.reopen(wr)
          Rake::Task["db:migrate"].invoke
        end
      end
      wr.close
      output = ""
      loop do
        IO.select([rd])
        text = rd.read
        break if text.nil? || text.length.zero?
        output.concat text
      end
      rd.close
      server_channel.write("command" => "stdout", "process" => "db:migrate", "text" => output)
      Process.waitall
    end
  end

  def load_rails_environment
    debug "Loading rails environment..."

    ENV["TEST_ENV_NUMBER"] = "1"

    output = Nitra::Utils.capture_output do
      require 'config/application'
      Rails.application.require_environment!
      ActiveRecord::Base.connection.disconnect!
    end

    server_channel.write("command" => "stdout", "process" => "rails initialisation", "text" => output)
  end

  def start_workers
    (1..configuration.process_count).collect do |index|
      start_worker(index)
    end
  end

  def start_worker(index)
    pid, pipe = Nitra::Workers::Worker.worker_classes[framework].new(runner_id, index, configuration).fork_and_run
    workers[index] = {:pid => pid, :pipe => pipe}
  end

  def worker_pipes
    workers.collect {|index, worker_hash| worker_hash[:pipe]}
  end

  def hand_out_files_to_workers
    while !$aborted && workers.length > 0
      Nitra::Channel.read_select(worker_pipes + [server_channel]).each do |worker_channel|

        # This is our back-channel that lets us know in case the master is dead.
        kill_workers if worker_channel == server_channel && server_channel.rd.eof?

        unless data = worker_channel.read
          worker_number, worker_hash = workers.find {|number, hash| hash[:pipe] == worker_channel}
          workers.delete worker_number
          debug "Worker #{worker_number} unexpectedly died."
          next
        end

        case data['command']
        when "debug", "stdout"
          server_channel.write(data)

        when "result"
          handle_result(data)

        when "ready"
          handle_ready(data, worker_channel)
        end
      end
    end
  end

  ##
  # This parses the results we got back from the worker.
  #
  # It needs rewriting when we finally rewrite the workers to use custom formatters.
  #
  # Also, it's probably buggy as hell...
  #
  def handle_result(data)
    #defaults - theoretically anything can end up here so we just want to pass on useful data
    result_text = ""
    example_count = 0
    failure_count = 0
    return_code = data["return_code"].to_i

    # Rspec result
    if m = data['text'].match(/(\d+) examples?, (\d+) failure/)
      example_count = m[1].to_i
      failure_count = m[2].to_i

    # Cucumber result
    elsif m = data['text'].match(/(\d+) scenarios?.+$/)
      example_count = m[1].to_i
      if m = data['text'].match(/\d+ scenarios? \(.*(\d+) [failed|undefined].*\)/)
        failure_count = m[1].to_i
      else
        failure_count = 0
      end
    end

    result_text = data['text'] if failure_count > 0 || return_code != 0

    server_channel.write(
      "command"       => "result",
      "filename"      => data["filename"],
      "return_code"   => return_code,
      "example_count" => example_count,
      "failure_count" => failure_count,
      "text"          => result_text)
  end

  def handle_ready(data, worker_channel)
    worker_number = data["worker_number"]
    server_channel.write("command" => "next", "framework" => data["framework"])
    data = server_channel.read

    case data["command"]
    when "framework"
      close_worker(worker_number, worker_channel)

      @framework = data["framework"]
      debug "Restarting #{worker_number} with framework #{framework}"
      start_worker(worker_number)

    when "file"
      debug "Sending #{data["filename"]} to #{worker_number}"
      worker_channel.write "command" => "process", "filename" => data["filename"]

    when "drain"
      close_worker(worker_number, worker_channel)
    end
  end

  def close_worker(worker_number, worker_channel)
    debug "Sending close message to #{worker_number}"
    worker_channel.write "command" => "close"
    workers.delete worker_number
  end

  def debug(*text)
    if configuration.debug
      server_channel.write("command" => "debug", "text" => "runner #{runner_id}: #{text.join}")
    end
  end

  ##
  # Kill the workers.
  #
  def kill_workers
    worker_pids = workers.collect{|index, hash| hash[:pid]}
    worker_pids.each {|pid| Process.kill('USR1', pid) rescue Errno::ESRCH}
    Process.waitall
    exit
  end
end
