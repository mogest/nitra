##
# Nitra::Formatter print out data regarding the run.
#
module Nitra
  class Formatter
    attr_accessor :start_time, :progress, :configuration

    def initialize(progress, configuration)
      self.progress = progress
      self.configuration = configuration
    end

    def start
      self.start_time = Time.now
      print_progress
    end

    def print_progress
      print_failures
      print_bar
    end

    def finish
      puts progress.filtered_output

      puts "\n#{overview}"
      puts "#{$aborted ? "Aborted after" : "Finished in"} #{"%0.1f" % (Time.now-start_time)} seconds"
    end

    private

    ##
    # Print the progress bar, doesn't do anything if we're in debug.
    #
    def print_bar
      return if configuration.quiet || configuration.debug || progress.file_count == 0
      total = 50
      completed = (progress.files_completed / progress.file_count.to_f * total).to_i
      print "\r[#{"X" * completed}#{"." * (total - completed)}] #{overview}\r"
      $stdout.flush
    end

    ##
    # Prints the output in the progress object and resets it if we've got eager printing turned on.
    #
    def print_failures
      return unless progress.output.length > 0 && configuration.print_failures
      puts progress.filtered_output
      progress.output = ""
    end

    ##
    # A simple overview of files processed so far and success/failure numbers.
    #
    def overview
      "#{progress.files_completed}/#{progress.file_count} files | #{progress.example_count} examples, #{progress.failure_count} failures"
    end
  end
end
