class Nitra::Master
  attr_reader :configuration, :files, :frameworks, :current_framework

  def initialize(configuration, files = nil)
    @configuration = configuration
    @frameworks = configuration.frameworks
    if @frameworks.any?
      load_files_from_framework_list
    else
      map_files_to_frameworks(files)
    end
    @current_framework = @frameworks.shift
    @configuration.framework = @current_framework
  end

  def run
    return if files_remaining == 0

    progress = Nitra::Progress.new
    progress.file_count = files_remaining
    yield progress, nil

    runners = []

    if configuration.process_count > 0
      client, runner = Nitra::Channel.pipe
      fork do
        runner.close
        Nitra::Runner.new(configuration, client, "A").run
      end
      client.close
      runners << runner
    end

    slave = Nitra::Slave::Client.new(configuration)
    runners += slave.connect

    while runners.length > 0
      Nitra::Channel.read_select(runners).each do |channel|
        if data = channel.read
          case data["command"]
          when "next"
            if files_remaining == 0
              channel.write "command" => "drain"
            elsif data["framework"] == current_framework
              channel.write "command" => "file", "filename" => next_file
            else
              channel.write "command" => "framework", "framework" => current_framework
            end
          when "result"
            progress.files_completed += 1
            progress.example_count += data["example_count"] || 0
            progress.failure_count += data["failure_count"] || 0
            progress.output << data["text"]
            yield progress, data
          when "debug"
            if configuration.debug
              puts "[DEBUG] #{data["text"]}"
            end
          when "stdout"
            if configuration.debug
              puts "STDOUT for #{data["process"]} #{data["filename"]}:\n#{data["text"]}" unless data["text"].empty?
            end
          end
        else
          runners.delete channel
        end
      end
    end

    debug "waiting for all children to exit..."
    Process.waitall
    progress
  end

  protected
  def debug(*text)
    puts "master: #{text.join}" if configuration.debug
  end

  def map_files_to_frameworks(files)
    @files = files.group_by do |filename|
     framework_name, framework_class = Nitra::Workers::WORKERS.find {|framework_name, framework_class| framework_class.filename_match?(filename)}
     framework_name
    end
    @frameworks = @files.keys
  end

  def load_files_from_framework_list
    @files = frameworks.inject({}) do |result, framework_name|
      result[framework_name] = Nitra::Workers::WORKERS[framework_name].files
      result
    end
  end

  def files_remaining
    files.values.inject(0) {|sum, filenames| sum + filenames.length}
  end

  def current_framework_files
    files[current_framework]
  end

  def next_file
    raise if files_remaining == 0
    file = current_framework_files.shift
    @current_framework = frameworks.shift if current_framework_files.length == 0
    file
  end
end
