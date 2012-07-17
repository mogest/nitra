module Nitra::Workers
  class Rspec < Worker
    def self.files
      Dir["spec/**/*_spec.rb"].sort_by {|f| File.size(f)}.reverse
    end

    def self.filename_match?(filename)
      filename =~ /_spec\.rb/
    end

    def initialize(runner_id, worker_number, configuration)
      super(runner_id, worker_number, configuration)
    end

    def load_environment
      require 'spec/spec_helper'
      RSpec::Core::Runner.disable_autorun!
    end

    def minimal_file
      <<-EOS
      require 'spec_helper'
      describe('nitra preloading') do
        it('preloads the fixtures') do
          1.should == 1
        end
      end
      EOS
    end

    ##
    # Run an rspec file and write the results back to the runner.
    #
    # Doesn't write back to the runner if we mark the run as preloading.
    #
    def run_file(filename, preloading = false)
      begin
        result = RSpec::Core::CommandLine.new(["-f", "p", filename]).run(io, io)
      rescue LoadError
        io << "\nCould not load file #{filename}\n\n"
        result = 1
      end
      if preloading
        puts io.string
      else
        channel.write("command" => "result", "filename" => filename, "return_code" => result.to_i, "text" => io.string, "worker_number" => worker_number)
      end
    end

    def clean_up
      RSpec.reset
    end
  end
end
