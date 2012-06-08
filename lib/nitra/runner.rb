require 'stringio'

class Nitra::Runner
  attr_reader :configuration, :server_channel, :runner_id

  def initialize(configuration, server_channel, runner_id)
    @configuration = configuration
    @server_channel = server_channel
    @runner_id = runner_id
  end

  def run
    ENV["RAILS_ENV"] = configuration.environment

    initialise_database

    load_rails_environment

    pipes = start_workers

    trap("SIGTERM") { $aborted = true }
    trap("SIGINT") { $aborted = true }

    hand_out_files_to_workers(pipes)

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
    debug "loading rails environment..."

    ENV["TEST_ENV_NUMBER"] = "1"

    old_stdout = $stdout
    old_stderr = $stderr
    $stdout = $stderr = io = StringIO.new
    begin
      require 'spec/spec_helper'
    ensure
      $stdout = old_stdout
      $stderr = old_stderr
    end

    server_channel.write("command" => "stdout", "process" => "rails initialisation", "text" => io.string)

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
          debug "worker #{worker_channel} unexpectedly died."
          next
        end

        case data['command']
        when "debug", "stdout"
          server_channel.write(data)

        when "result"
          if m = data['text'].match(/(\d+) examples?, (\d+) failure/)
            example_count = m[1].to_i
            failure_count = m[2].to_i
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
            debug "sending #{next_file} to channel #{worker_channel}"
            worker_channel.write "command" => "process", "filename" => next_file
          else
            debug "sending close message to channel #{worker_channel}"
            worker_channel.write "command" => "close"
            pipes.delete worker_channel
          end
        end
      end
    end
  end

  def debug(*text)
    server_channel.write(
      :command => "debug",
      :text => "runner #{runner_id}: #{text.join}"
    ) if configuration.debug
  end
end
