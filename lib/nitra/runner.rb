require 'stringio'

class Nitra::Runner
  attr_reader :configuration, :server_channel, :runner_id

  def initialize(configuration, server_channel, runner_id)
    @configuration = configuration
    @server_channel = server_channel
    @runner_id = runner_id

    configuration.calculate_default_process_count
    server_channel.raise_epipe_on_write_error = true
  end

  def run
    ENV["RAILS_ENV"] = configuration.environment

    initialise_database

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
  def initialise_database
    if configuration.load_schema
      configuration.process_count.times do |index|
        debug "initialising database #{index+1}..."
        ENV["TEST_ENV_NUMBER"] = (index + 1).to_s
        output = `bundle exec rake db:drop db:create db:schema:load 2>&1`
        server_channel.write("command" => "stdout", "process" => "db:schema:load", "text" => output)
      end
    end

    if configuration.migrate
      configuration.process_count.times do |index|
        debug "migrating database #{index+1}..."
        ENV["TEST_ENV_NUMBER"] = (index + 1).to_s
        output = `bundle exec rake db:migrate 2>&1`
        server_channel.write("command" => "stdout", "process" => "db:migrate", "text" => output)
      end
    end
  end

  def load_rails_environment
    debug "Loading rails environment..."

    ENV["TEST_ENV_NUMBER"] = "1"

    output = Nitra::Utils.capture_output do
      configuration.framework.load_environment
    end

    server_channel.write("command" => "stdout", "process" => "rails initialisation", "text" => output)

    ActiveRecord::Base.connection.disconnect!
  end

  def start_workers
    (0...configuration.process_count).collect do |index|
      Nitra::Worker.new(runner_id, index, configuration).fork_and_run
    end
  end

  def hand_out_files_to_workers(pipes)
    while !$aborted && pipes.length > 0
      Nitra::Channel.read_select(pipes).each do |worker_channel|
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

          server_channel.write(
            "command"       => "result",
            "filename"      => data["filename"],
            "return_code"   => data["return_code"],
            "example_count" => example_count,
            "failure_count" => failure_count,
            "text"          => data['text'])

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
end
