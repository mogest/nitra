gem 'minitest'
require 'minitest/spec'
require 'minitest/autorun'
require 'ostruct'
require '../../lib/tasks.rb'

# Tasks needs an overhaul - it should just run stuff and report back, not talk to channels.
# describe Nitra::Tasks do
#   def runner_tasks
#     {:before_runner => 'before_runner', :before_worker => 'before_worker', :after_runner => 'after_runner', :debug => false}
#   end
#   it "runs tasks for runners" do
#     tasks = Nitra::Tasks.new(runner_tasks)
#     tasks.run(:before_runner).must eq('ran before_runner')
#   end
# end
