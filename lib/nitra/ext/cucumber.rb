require 'cucumber/rb_support/rb_language'
require 'cucumber/runtime'
module Cucumber
  module RbSupport
    class RbLanguage
      # Reloading support files is bad for us. Idealy we'd subclass but since
      # Cucumber's internals are a bit shit and insists on using the new keyword
      # everywhere we have to monkeypatch it out or spend another 6 months
      # rewriting it and getting patches accepted...
      def load_code_file(code_file)
        require File.expand_path(code_file)
      end
    end
  end
  class ResetableRuntime < Runtime
    # Cucumber lacks a reset hook like the one Rspec has so we need to patch one in...
    # Call this after configure so that the correct configuration is used to create the result set.
    def reset
      @results = Results.new(nil)
    end
  end
end
