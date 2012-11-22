gem 'minitest'
require 'minitest/spec'
require 'minitest/autorun'
require_relative '../../lib/nitra/command_line'

describe Nitra::CommandLine do

  let(:config){ m = MiniTest::Mock.new; m.expect(:set_default_framework, []); m}

  describe "option parsing" do
    describe "-c" do
      it "sets process count" do
        config.expect(:set_process_count, nil, [2])
        Nitra::CommandLine.new(config, ['-c','2'])
        config.verify
      end
    end

    describe "--cucumber" do
      it "adds cucumber to framework" do
        config.expect(:add_framework, nil, ['cucumber'])
        Nitra::CommandLine.new(config, ['--cucumber'])
        config.verify
      end
    end

    describe "--debug" do
      it "adds debug flag" do
        config.expect(:debug=, nil, [true])
        Nitra::CommandLine.new(config, ['--debug'])
        config.verify
      end
    end

    describe "-p" do
      it "adds print failure flag" do
        config.expect(:print_failures=, nil, [true])
        Nitra::CommandLine.new(config, ['-p'])
        config.verify
      end
    end

    describe "-q" do
      it "adds quiet flag" do
        config.expect(:quiet=, nil, [true])
        Nitra::CommandLine.new(config, ['-q'])
        config.verify
      end
    end

    describe "--rake-after-runner" do
      it "adds rake tasks to run after runner finishes" do
        config.expect(:add_rake_task, nil, [:after_runner, ['list:of','rake:tasks']])
        Nitra::CommandLine.new(config, ['--rake-after-runner', 'list:of,rake:tasks'])
        config.verify
      end
    end

    describe "--rake-before-runner" do
      it "adds rake tasks to run before runner starts" do
        config.expect(:add_rake_task, nil, [:before_runner, ['list:of','rake:tasks']])
        Nitra::CommandLine.new(config, ['--rake-before-runner', 'list:of,rake:tasks'])
        config.verify
      end
    end

    describe "--rake-before-worker" do
      it "adds rake tasks to run before worker starts" do
        config.expect(:add_rake_task, nil, [:before_worker, ['list:of','rake:tasks']])
        Nitra::CommandLine.new(config, ['--rake-before-worker', 'list:of,rake:tasks'])
        config.verify
      end
    end

    describe "--rspec" do
      it "adds rspec to framework" do
        config.expect(:add_framework, nil, ['rspec'])
        Nitra::CommandLine.new(config, ['--rspec'])
        config.verify
      end
    end

    describe "--slave-mode" do
      it "turns on slave mode" do
        config.expect(:slave_mode=, nil, [true])
        Nitra::CommandLine.new(config, ['--slave-mode'])
        config.verify
      end
    end

    describe "--slave" do
      it "adds a command that will be run later as a slave" do
        config.expect(:add_slave, nil, ['the command to run'])
        Nitra::CommandLine.new(config, ['--slave', 'the command to run'])
        config.verify
      end
    end
  end

  describe "file lists" do
    it "parses out options and leavs only files in list" do
      argv = ['--slave','the slave command','this_test_file_spec.rb']
      config.expect(:add_slave, nil, ['the slave command'])
      Nitra::CommandLine.new(config, argv)
      config.verify
      argv.must_equal ['this_test_file_spec.rb']
    end
  end
end
