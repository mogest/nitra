module Nitra::Slave
  class Client
    attr_reader :configuration

    def initialize(configuration)
      @configuration = configuration
    end

    ##
    # Starts the slave runners.
    #
    # We do this in two steps, starts them all and then sends them their configurations.
    # This extra complexity speeds up the initial startup when working with many slaves.
    #
    def connect
      runner_id = "A"
      @configuration.slaves.collect do |slave_details|
        runner_id = runner_id.succ
        server = start_host(slave_details, runner_id)
        [server, slave_details, runner_id]
      end.collect do |server, slave_details, runner_id|
        configure_host(server, slave_details, runner_id)
      end.compact
    end

    protected
    def start_host(slave_details, runner_id)
      client, server = Nitra::Channel.pipe

      puts "Starting slave runner #{runner_id} with command '#{slave_details[:command]}'" if configuration.debug

      pid = fork do
        server.close
        $stdin.reopen(client.rd)
        $stdout.reopen(client.wr)
        $stderr.reopen(client.wr)
        exec slave_details[:command]
      end
      client.close
      server
    end

    def configure_host(server, slave_details, runner_id)
      slave_config = configuration.dup
      slave_config.process_count = slave_details.fetch(:cpus)

      server.write(
        "command" => "configuration",
        "runner_id" => runner_id,
        "configuration" => slave_config)
      response = server.read

      if response["command"] == "connected"
        puts "Connection to slave runner #{runner_id} successful" if configuration.debug
        server
      else
        $stderr.puts "Connection to slave runner #{runner_id} FAILED with message: #{response.inspect}"
        Process.kill("KILL", pid)
        nil
      end
    end
  end

  class Server
    attr_reader :channel

    def run
      @channel = Nitra::Channel.new($stdin, $stdout)

      response = @channel.read
      unless response && response["command"] == "configuration"
        puts "handshake failed"
        exit 1
      end

      @channel.write("command" => "connected")

      runner = Nitra::Runner.new(response["configuration"], channel, response["runner_id"])

      runner.run
    end
  end
end
