require 'stringio'

class Nitra::Runner
  attr_reader :configuration, :server_channel, :runner_id, :framework, :worker_pids

  def initialize(configuration, server_channel, runner_id)
    @configuration = configuration
    @server_channel = server_channel
    @runner_id = runner_id
    @framework = configuration.framework_shim
    @worker_pids = []

    configuration.calculate_default_process_count
    server_channel.raise_epipe_on_write_error = true
  end

  def run
    ENV["RAILS_ENV"] = configuration.environment

    load_rails_environment

    pipes = start_workers

    trap("SIGTERM") { $aborted = true }
    trap("SIGINT") { $aborted = true }

    hand_out_files_to_workers(pipes)
  rescue Errno::EPIPE
  ensure
    trap("SIGTERM", "DEFAULT")
    trap("SIGINT", "DEFAULT")
  end

  protected

  def load_rails_environment
    debug "Loading rails environment..."

    ENV["TEST_ENV_NUMBER"] = "1"

    output = Nitra::Utils.capture_output do
      require 'config/application'
      Rails.application.require_environment!
    end

    server_channel.write("command" => "stdout", "process" => "rails initialisation", "text" => output)
  end

  def start_workers
    (1..configuration.process_count).collect do |index|
      pid, pipe = Nitra::Worker.new(runner_id, index, configuration).fork_and_run
      worker_pids << pid
      pipe
    end
  end

  def hand_out_files_to_workers(pipes)
    while !$aborted && pipes.length > 0
      Nitra::Channel.read_select(pipes + [server_channel]).each do |worker_channel|

        # This is our back-channel that lets us know in case the master is dead.
        kill_workers if worker_channel == server_channel && server_channel.rd.eof?

        unless data = worker_channel.read
          pipes.delete worker_channel
          debug "Worker #{worker_channel} unexpectedly died."
          next
        end

        case data['command']
        when "debug", "stdout"
          server_channel.write(data)

        when "result"
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

          stripped_data = data['text'].gsub(/^[.FP*]+$/, '').gsub(/\nFailed examples:.+/m, '').gsub(/^Finished in.+$/, '').gsub(/^\d+ example.+$/, '').gsub(/^No examples found.$/, '').gsub(/^Failures:$/, '')

          server_channel.write(
            "command"       => "result",
            "filename"      => data["filename"],
            "return_code"   => data["return_code"],
            "example_count" => example_count,
            "failure_count" => failure_count,
            "text"          => stripped_data)

        when "ready"
          server_channel.write("command" => "next")
          next_file = server_channel.read.fetch("filename")

          if next_file
            debug "Sending #{next_file} to channel #{worker_channel}"
            worker_channel.write "command" => "process", "filename" => next_file
          else
            debug "Sending close message to channel #{worker_channel}"
            worker_channel.write "command" => "close"
            pipes.delete worker_channel
          end
        end
      end
    end
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
    worker_pids.each {|pid| Process.kill('USR1', pid)}
    Process.waitall
    exit
  end
end
