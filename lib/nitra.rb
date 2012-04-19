require 'stringio'

class Nitra
  attr_accessor :load_schema, :migrate, :debug, :quiet, :print_failures
  attr_accessor :files
  attr_accessor :process_count, :environment

  def initialize
    self.process_count = 4
    self.environment = "nitra"
  end

  def run
    start_time = Time.now
    ENV["RAILS_ENV"] = environment

    initialise_database

    load_rails_environment

    pipes = fork_workers

    self.files = Dir["spec/**/*_spec.rb"] if files.nil? || files.empty?
    return if files.empty?

    trap("SIGTERM") { $aborted = true }
    trap("SIGINT") { $aborted = true }

    return_code, result = hand_out_files_to_workers(files, pipes)

    trap("SIGTERM", "DEFAULT")
    trap("SIGINT", "DEFAULT")

    print_result(result)
    puts "\n#{$aborted ? "Aborted after" : "Finished in"} #{"%0.1f" % (Time.now-start_time)} seconds" unless quiet

    $aborted ? 255 : return_code
  end

  protected
  def print_result(result)
    puts result.gsub(/\n\n\n+/, "\n\n")
  end

  def print_progress
    unless quiet
      bar_length = @columns - 50
      progress = @files_completed / @file_count.to_f
      length_completed = (progress * bar_length).to_i
      length_to_go = bar_length - length_completed
      print "[#{"X" * length_completed}#{"." * length_to_go}] #{@files_completed}/#{@file_count} (#{"%0.1f%%" % (progress*100)}) * #{@example_count} examples, #{@failure_count} failures\r"
    end
  end

  def initialise_database
    if load_schema
      process_count.times do |index|
        puts "initialising database #{index+1}..." unless quiet
        ENV["TEST_ENV_NUMBER"] = (index + 1).to_s
        system("bundle exec rake db:drop db:create db:schema:load")
      end
    end

    if migrate
      process_count.times do |index|
        puts "migrating database #{index+1}..." unless quiet
        ENV["TEST_ENV_NUMBER"] = (index + 1).to_s
        system("bundle exec rake db:migrate")
      end
    end
  end

  def load_rails_environment
    puts "loading rails environment..." if debug

    ENV["TEST_ENV_NUMBER"] = "1"

    require 'spec/spec_helper'

    ActiveRecord::Base.connection.disconnect!
  end

  def fork_workers
    (0...process_count).collect do |index|
      server_sender_pipe = IO.pipe
      client_sender_pipe = IO.pipe

      fork do
        trap("SIGTERM") { Process.kill("SIGKILL", Process.pid) }
        trap("SIGINT") { Process.kill("SIGKILL", Process.pid) }

        server_sender_pipe[1].close
        client_sender_pipe[0].close
        rd = server_sender_pipe[0]
        wr = client_sender_pipe[1]

        ENV["TEST_ENV_NUMBER"] = (index + 1).to_s

        database_config = YAML.load(ERB.new(IO.read("#{Rails.root}/config/database.yml")).result)[ENV["RAILS_ENV"]]
        ActiveRecord::Base.establish_connection(database_config)
        Rails.cache.reset if Rails.cache.respond_to?(:reset)

        puts "announcing availability" if debug
        wr.write("0,0\n")

        io = StringIO.new
        loop do
          puts "#{index} waiting for next job" if debug
          filename = rd.gets
          exit if filename.blank?
          filename = filename.chomp
          puts "#{index} starting to process #{filename}" if debug

          begin
            result = RSpec::Core::CommandLine.new(["-f", "p", filename]).run(io, io)
          rescue LoadError
            io << "\nCould not load file #{filename}\n\n"
            result = 1
          end
          RSpec.reset

          puts "#{index} #{filename} processed" if debug

          wr.write("#{result.to_i},#{io.string.length}\n#{io.string}")
          io.string = ""
        end
      end

      server_sender_pipe[0].close
      client_sender_pipe[1].close
      [client_sender_pipe[0], server_sender_pipe[1]]
    end
  end

  def hand_out_files_to_workers(files, pipes)
    puts "Running rspec on #{files.length} files spread across #{process_count} processes\n\n" unless quiet

    @columns = (ENV['COLUMNS'] || 120).to_i
    @file_count = files.length
    @files_completed = 0
    @example_count = 0
    @failure_count = 0

    result = ""
    worst_return_code = 0
    readers = pipes.collect(&:first)

    while !$aborted && readers.length > 0
      print_progress
      fds = IO.select(readers)
      fds.first.each do |fd|
        unless value = fd.gets
          readers.delete(fd)
          worst_return_code = 255
          if readers.empty?
            puts "Worker unexpectedly died.  No more workers to run specs - dying."
          else
            puts "Worker unexpectedly died.  Trying to continue with fewer workers."
          end
          break
        end

        return_code, length = value.split(",")
        worst_return_code = return_code.to_i if worst_return_code < return_code.to_i

        if length.to_i > 0
          data = fd.read(length.to_i)

          @files_completed += 1
          failure_count = 0

          if m = data.match(/(\d+) examples?, (\d+) failure/)
            @example_count += m[1].to_i
            failure_count += m[2].to_i
          end

          @failure_count += failure_count
          stripped_data = data.gsub(/^[.FP*]+$/, '').gsub(/\nFailed examples:.+/m, '').gsub(/^Finished in.+$/, '').gsub(/^\d+ example.+$/, '').gsub(/^No examples found.$/, '').gsub(/^Failures:$/, '')

          if print_failures && failure_count > 0
            print_result(stripped_data)
          else
            result << stripped_data
          end
        else
          puts "ZERO LENGTH" if debug
        end

        wr = pipes.detect {|rd, wr| rd == fd}[1]
        if files.length.zero?
          wr.puts ""
          readers.delete(fd)
        else
          puts "master is sending #{files.first} to fd #{wr}" if debug
          wr.puts files.shift
        end
      end
    end

    print_progress
    puts "" unless quiet

    [worst_return_code, result]
  end
end
