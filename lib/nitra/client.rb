class Nitra::Client
  attr_reader :configuration, :files

  def initialize(configuration, files = nil)
    @configuration = configuration
    @files = files
    @columns = (ENV['COLUMNS'] || 120).to_i
  end

  def run
    start_time = Time.now

    master = Nitra::Master.new(configuration, files)
    progress = master.run do |progress, data|
      print_progress(progress)
      if data && configuration.print_failures && data["failure_count"] != 0
        puts unless configuration.quiet
        puts "=== output for #{data["filename"]} #{'='*40}"
        puts data["text"].gsub(/\n\n\n+/, "\n\n")
      end
    end

    puts progress.output.gsub(/\n\n\n+/, "\n\n")

    puts "\n#{progress.files_completed}/#{progress.file_count} files processed, #{progress.example_count} examples, #{progress.failure_count} failures"
    puts "#{$aborted ? "Aborted after" : "Finished in"} #{"%0.1f" % (Time.now-start_time)} seconds" unless configuration.quiet

    !$aborted && progress.files_completed == progress.file_count && progress.failure_count.zero?
  end

  protected
  def print_progress(progress)
    return if configuration.quiet

    bar_length = @columns - 50
    progress_factor = progress.files_completed / progress.file_count.to_f
    length_completed = (progress_factor * bar_length).to_i
    length_to_go = bar_length - length_completed
    print "\r[#{"X" * length_completed}#{"." * length_to_go}] #{progress.files_completed}/#{progress.file_count} (#{"%0.1f%%" % (progress_factor*100)}) * #{progress.example_count} examples, #{progress.failure_count} failures\r"
    puts if configuration.debug
    $stdout.flush
  end
end
