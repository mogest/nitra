class Nitra
  def run
    start_time = Time.now
    ENV["RAILS_ENV"] = "nitra"

    process_count = 4
    debug = false

    if false
      process_count.times do |index|
        puts "initialising database #{index+1}..."
        ENV["TEST_ENV_NUMBER"] = (index + 1).to_s
        system("bundle exec rake db:schema:load")
      end
    end

    puts "loading rails environment..." if debug

    ENV["TEST_ENV_NUMBER"] = "1"

    require 'config/environment'
    require 'rspec'
    require 'stringio'

    ActiveRecord::Base.connection.disconnect!

    trap("SIGINT") { Process.kill("SIGKILL", Process.pid) }

    pipes = (0...process_count).collect do |index|
      server_sender_pipe = IO.pipe
      client_sender_pipe = IO.pipe
      fork do
        server_sender_pipe[1].close
        client_sender_pipe[0].close
        rd = server_sender_pipe[0]
        wr = client_sender_pipe[1]

        ENV["TEST_ENV_NUMBER"] = (index + 1).to_s

        database_config = YAML.load(ERB.new(IO.read("#{Rails.root}/config/database.yml")).result)[ENV["RAILS_ENV"]]
        ActiveRecord::Base.establish_connection(database_config)
        Rails.cache.reset if Rails.cache.respond_to?(:reset)

        puts "announcing availability" if debug
        wr.write("0\n")

        io = StringIO.new
        loop do
          puts "#{index} waiting for next job" if debug
          filename = rd.gets
          exit if filename.blank?
          filename = filename.chomp
          puts "#{index} starting to process #{filename}" if debug

          RSpec::Core::CommandLine.new(["-f", "p", filename]).run(io, io)
          RSpec.reset

          wr.write("#{io.string.length}\n#{io.string}")
          io.string = ""
        end
      end
      server_sender_pipe[0].close
      client_sender_pipe[1].close
      [client_sender_pipe[0], server_sender_pipe[1]]
    end

    readers = pipes.collect(&:first)
    files = Dir["spec/**/*_spec.rb"]

    return if files.empty?

    puts "Running rspec on #{files.length} files spread across #{process_count} processes\n\n"

    @columns = (ENV['COLUMNS'] || 120).to_i
    @file_count = files.length
    @files_completed = 0
    @example_count = 0
    @failure_count = 0

    result = ""
    while readers.length > 0
      print_progress
      fds = IO.select(readers)
      fds.first.each do |fd|
        length = fd.gets

        if length.nil?
          break
        elsif length.to_i > 0
          data = fd.read(length.to_i)

          @files_completed += 1
          if m = data.match(/(\d+) examples?, (\d+) failure/)
            @example_count += m[1].to_i
            @failure_count += m[2].to_i
          end

          result << data.gsub(/^[.FP]+$/, '').gsub(/\nFailed examples:.+/m, '').gsub(/^Finished in.+$/, '').gsub(/^\d+ example.+$/, '').gsub(/^No examples found.$/, '').gsub(/^Failures:$/, '')
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
    puts ""
    result = result.gsub(/\n\n\n+/, "\n\n")
    puts result
    puts "\nFinished in #{"%0.1f" % (Time.now-start_time)} seconds"
  end

  protected
  def print_progress
    bar_length = @columns - 50
    progress = @files_completed / @file_count.to_f
    length_completed = (progress * bar_length).to_i
    length_to_go = bar_length - length_completed
    print "[#{"X" * length_completed}#{"." * length_to_go}] #{@files_completed}/#{@file_count} (#{"%0.1f%%" % (progress*100)}) * #{@example_count} examples, #{@failure_count} failures\r"
  end
end
