module Nitra::Workers
  class Cucumber < Worker
    def self.files
      Dir["features/**/*.feature"].sort_by {|f| File.size(f)}.reverse
    end

    def self.filename_match?(filename)
      filename =~ /\.feature/
    end

    def initialize(runner_id, worker_number, configuration)
      super(runner_id, worker_number, configuration)
    end

    def load_environment
      require 'cucumber'
      require 'nitra/ext/cucumber'
    end

    def minimal_file
      <<-EOS
      Feature: cucumber preloading
        Scenario: a fake scenario
          Given every step is unimplemented
          When we run this file
          Then Cucumber will load it's environment
      EOS
    end

    ##
    # Run a Cucumber file and write the results back to the runner.
    #
    # Doesn't write back to the runner if we mark the run as preloading.
    #
    def run_file(filename, preloading = false)
      @cuke_runtime ||= ::Cucumber::ResetableRuntime.new  # This runtime gets reused, this is important as it's the part that loads the steps...
      begin
        result = 1
        cuke_config = ::Cucumber::Cli::Configuration.new(io, io)
        cuke_config.parse!(["--no-color", "--require", "features", filename])
        @cuke_runtime.configure(cuke_config)
        @cuke_runtime.run!
        result = 0 unless @cuke_runtime.results.failure?
      rescue LoadError
        io.concat "\nCould not load file #{filename}\n\n"
      rescue Exception => e
        io.concat "Exception when running #{filename}: #{e.message}"
        io.concat e.backtrace[0..7].join "\n"
      end

      if preloading
        puts(io.string)
      else
        channel.write("command" => "result", "filename" => filename, "return_code" => result.to_i, "text" => io.string, "worker_number" => worker_number)
      end
    end

    def clean_up
      @cuke_runtime.reset
    end
  end
end
