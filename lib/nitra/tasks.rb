class Nitra::Tasks
  attr_reader :runner

  def initialize(runner)
    @runner = runner
    if runner.configuration.rake_tasks.keys.any?
      require 'rake'
      Rake.load_rakefile("Rakefile")
    end
  end

  def run(name, count = 1)
    return unless tasks = runner.configuration.rake_tasks[name]
    runner.debug "Running #{name} tasks: #{tasks.inspect}"
    rd, wr = IO.pipe
    (1..count).collect do |index|
      fork do
        ENV["TEST_ENV_NUMBER"] = index.to_s
        rd.close
        $stdout.reopen(wr)
        $stderr.reopen(wr)
        connect_to_database
        tasks.each do |task|
          Rake::Task[task].invoke
        end
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
    successful = all_children_successful?
    runner.server_channel.write("command" => (successful ? 'stdout' : 'error'), "process" => tasks.inspect, "text" => output)
    exit if !successful
  end

  private

  def connect_to_database
    Nitra::RailsTooling.connect_to_database
  end

  ##
  # Reap the exit codes for any forked processes and report failures.
  #
  def all_children_successful?
    Process.waitall.all? { |pid, process| process.success? }
  end

end
