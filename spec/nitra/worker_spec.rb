gem 'minitest'
require 'minitest/spec'
require 'minitest/autorun'
require_relative '../../lib/nitra/worker'

describe Nitra::Workers::Worker do
  it "does some inheritance tricks" do
    class RSpec < Nitra::Workers::Worker
    end
    Nitra::Workers::Worker.worker_classes['rspec'].must_equal RSpec
    RSpec.framework_name.must_equal 'rspec'
  end
end
