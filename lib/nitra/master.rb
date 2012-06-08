class Nitra::Master
  attr_reader :configuration, :files

  def initialize(configuration, files = nil)
    @configuration = configuration
    @files = files
  end

  def run
    @files = Dir["spec/**/*_spec.rb"] if files.nil? || files.empty?
    return if files.empty?

    progress = Nitra::Progress.new
    progress.file_count = @files.length
    yield progress, nil

    client, runner = Nitra::Channel.pipe
    fork do
      runner.close
      Nitra::Runner.new(configuration, client, "A").run
    end
    client.close

    # TODO : open Nitra::Runner on other machines

    runners = [runner]

    while runners.length > 0
      Nitra::Channel.read_select(runners).each do |channel|
        if data = channel.read
          case data["command"]
          when "next"
            channel.write "filename" => files.shift
          when "result"
            progress.files_completed += 1
            progress.example_count += data["example_count"]
            progress.failure_count += data["failure_count"]
            progress.output << data["text"]
            yield progress, data
          when "debug"
            puts "[DEBUG] #{data["text"]}"
          when "stdout"
            puts "STDOUT for #{data["process"]} #{data["filename"]}:\n#{data["text"]}" unless data["text"].empty?
          end
        else
          runners.delete channel
        end
      end
    end

    debug "waiting for runner children to exit..."
    Process.wait
    progress
  end

  protected
  def debug(*text)
    puts "master: #{text.join}" if configuration.debug
  end
end
