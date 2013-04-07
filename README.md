# Nitra
Nitra is a multi-process, optionally multi-server rspec and cucumber runner that uses forking to reduce memory usage and IPC to distribute builds amongst available CPUs efficiently.

## Philosophy
* Nitra attempts to do the simplest thing possible
* Nitra (ab)uses unix primitives where possible
* Nitra doesn't do thing that unix already does better (eg. rsync)
* IPC is accomplished via pipes and select
* Forking is used heavily for several reasons
* Running nitra locally should be easy
* Running nitra on a cluster should be easy too (though verbose)
* Config files are a nuisance and should be stuffed into rake files (deals with the verbosity)

## Usage
      nitra [options] [spec_filename [...]]
          -c, --cpus NUMBER                Specify the number of CPUs to use on the host, or if specified after a --slave, on the slave
              --cucumber                   Add full cucumber run, causes any files you list manually to be ignored
              --debug                      Print debug output
          -p, --print-failures             Print failures immediately when they occur
          -q, --quiet                      Quiet; don't display progress bar
              --rake-after-runner task:1,task:2,task:3
                                           The list of rake tasks to run, once per runner, in the runner's environment, just before the runner exits
              --rake-before-runner task:1,task:2,task:3
                                           The list of rake tasks to run, once per runner, in the runner's environment, after the runner starts
              --rake-before-worker task:1,task:2,task:3
                                           The list of rake tasks to run, once per worker, in the worker's environment, before the worker starts
              --reset                      r
                                           Reset database, equivalent to --rake-before-worker db:reset
              --slave-mode                 Run in slave mode; ignores all other command-line options
              --slave CONNECTION_COMMAND   Provide a command that executes "nitra --slave-mode" on another host
              --rspec                      Add full rspec run, causes any files you list manually to be ignored
          -e, --environment ENV            Set the RAILS_ENV to load
          -h, --help                       Show this message

### Getting started
First things first add nitra to your Gemfile:

    gem 'nitra'

Then run your specs locally across your cpu's cores:

    bundle exec nitra --rspec

This will just run all your specs using the default number of cpu's reported by your system. Hyperthreaded intels will report a high number which might not be a good fit, you can tune this with the -c option.

Clustered commands run slightly differently. Effectively nitra will fork and exec a command that it expects will be a nitra slave, this means we can use ssh as our tunnel of choice. It looks something like this:

    bundle exec nitra --rspec --slave "ssh your.server.name 'cd your/project && bundle exec nitra --slave-mode'"

When nitra --slave command it forks, execs it, and assumes it's another process that's running "nitra --slave-mode".

### Running a build cluster
Nitra doesn't prescribe how you get your code onto the other machines in your cluster. For example you can run a git checkout on the boxes you want to build on if it's the fastest way for you. For our part - we've had the most success with rsync.

Our build is run via rake tasks so we end up with a bunch of generated code to rsync files back and forth - here's a basic version that might help get you up and running:

    namespace :nitra do
      task :config do
          @servers = [
            {:name => "server1", :port => "66666", :c => "4"},
            {:name => "server2", :port => "99999", :c => "2"},
            {:name => "server3", :port => "77777", :c => "8"},
            {:name => "server4", :port => "88888", :c => "4"}
          ]
      end

      desc "Sync the local directory and install the gems onto the remote servers"
      task :prep => :config do
        @servers.each do |server|
          fork do
            system "ssh -p #{server[:port]} #{server[:name]} 'mkdir -p nitra/projects/your_project'"
            exec %(rsync -aze 'ssh -q -p #{server[:port]}' --exclude .git --delete ./ #{server[:name]}:nitra/projects/your_project/ && ssh -q -t -p #{server[:port]} #{server[:name]} 'cd nitra/projects/your_project && bundle install --quiet --path ~/gems')
          end
        end
        Process.waitall
      end

      task :all => :config do
        cmd = %(bundle exec nitra -p -q --rspec --cucumber --rake-before-worker db:reset)
        @servers.each do |server|
          cmd << %( --slave "ssh -p #{server[:port]} #{server[:name]} 'cd nitra/projects/your_project && bundle exec nitra --slave-mode'" -c#{server[:c]})
        end
        system cmd
      end
    end

## Copyright
Copyright 2012-2013 Roger Nesbitt, Powershop Limited, YouDo Limited.  MIT licence.
