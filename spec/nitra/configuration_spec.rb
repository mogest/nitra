gem 'minitest'
require 'minitest/spec'
require 'minitest/autorun'
require_relative '../../lib/nitra/configuration'

describe Nitra::Configuration do
  let(:config){ Nitra::Configuration.new }
  it "has default values" do
    config.slaves.must_equal []
    config.frameworks.must_equal []
    config.rake_tasks.must_equal Hash.new;
    config.process_count.must_equal Nitra::Utils.processor_count
  end

  describe "#add_framework" do
    it "adds a framework to frameworks" do
      config.add_framework("cucumber")
      config.add_framework("rspec")
      config.frameworks.must_equal ["cucumber", "rspec"]
    end
  end

  describe "#add_rake_task" do
    it "adds a rake task to the rake task hash" do
      config.add_rake_task(:task_name, ['list','of','tasks'])
      config.rake_tasks.must_equal({:task_name => ['list','of','tasks']})
    end
  end

  describe "#add_slave" do
    it "adds a slave command to the slave array" do
      command = 'command to run to get a nitra slave'
      config.add_slave(command)
      config.slaves[0].must_equal({:command => command, :cpus => nil})
    end
  end

  describe "#set_default_framework" do
    it "sets the default framework to the first one in the list" do
      config.add_framework 'rspec'
      config.add_framework 'cucumber'
      config.set_default_framework
      config.framework.must_equal 'rspec'
    end

    it "does nothing when there's no frameworks" do
      config.set_default_framework
      config.framework.must_be_nil
    end
  end

  # We want slaves to inherit all config except for process count.
  # This needs refactoring to not be so frickin retardedk.
  it "does interesting things with slave process configs" do
    config.process_count.must_equal Nitra::Utils.processor_count
    config.slaves << {}
    config.set_process_count 1000
    config.slaves.first[:cpus].must_equal 1000
  end
end
