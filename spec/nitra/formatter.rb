$LOAD_PATH.unshift File.expand_path(File.dirname(__FILE__) + '/../../lib')
gem 'minitest'
require 'ostruct'
require 'minitest/spec'
require 'minitest/autorun'
require 'nitra/formatter'
require 'nitra/progress'
require 'nitra/configuration'
require 'nitra/utils'

describe Nitra::Formatter do
  let(:progress)  { Nitra::Progress.new                    }
  let(:config)    { Nitra::Configuration.new               }
  let(:formatter) { Nitra::Formatter.new(progress, config) }

  describe "start" do
    it "prints the progress bar and saves the start time" do
      progress.file_count = 100
      output = Nitra::Utils.capture_output { formatter.start }
      output.must_include("..")
      formatter.start_time.wont_be_nil
    end
  end

  describe "#print_progress" do
    before :each do
      progress.file_count = 100
    end

    it "skips the bar when passed quiet config" do
      config.quiet = true
      output = Nitra::Utils.capture_output { formatter.print_progress }
      output.wont_include("..")
    end

    it "skips the bar when passed debug config" do
      config.debug = true
      output = Nitra::Utils.capture_output { formatter.print_progress }
      output.wont_include("..")
    end

    it "skips the bar when there's no files" do
      progress.file_count = 0
      output = Nitra::Utils.capture_output { formatter.print_progress }
      output.wont_include("..")
    end

    it "prints output since last progress if print_failures config is on" do
      progress.output = "lemons"
      output = Nitra::Utils.capture_output { formatter.print_progress }
      output.wont_include("lemons")
      progress.output.must_equal "lemons"

      config.print_failures = true

      output = Nitra::Utils.capture_output { formatter.print_progress }
      output.must_include("lemons")
      progress.output.must_equal ""
    end
  end

  describe "finish" do
    it "prints some basic stats" do
      progress.files_completed = 1
      progress.file_count = 2
      Nitra::Utils.capture_output { formatter.start } #silence
      output = Nitra::Utils.capture_output { formatter.finish }
      output.must_include("1/2 files")
      output.must_include("Finished in")
    end
  end
end
__END__

    def initialize(configuration, progress)
      self.configuration = configuration
      self.progress = progress
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
      return if configuration.quiet || configuration.debug
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
