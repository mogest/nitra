class Nitra::FrameworkShims
  module Cucumber
    class << self
      def load_environment
        require 'config/application'
        Rails.application.require_environment!
        require 'cucumber'
        require 'nitra/ext/cucumber'
      end

      def files
        Dir["features/**/*.feature"].sort_by{ |f| File.size(f) }.reverse
      end
    end
  end
  module Rspec
    class << self
      def load_environment
        require 'spec/spec_helper'
      end

      def files
        Dir["spec/**/*_spec.rb"].sort_by{ |f| File.size(f) }.reverse
      end
    end
  end
end
