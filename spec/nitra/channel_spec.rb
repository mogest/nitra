gem 'minitest'
require 'minitest/spec'
require 'minitest/autorun'
require_relative '../../lib/nitra/channel'

describe Nitra::Channel do
  describe ".pipe" do
    it "creates a pipe pair" do
      server, client = Nitra::Channel.pipe
      server.must_be_instance_of Nitra::Channel
      client.must_be_instance_of Nitra::Channel
    end
  end

  describe "#close" do
    it "closes channels" do
      server, client = Nitra::Channel.pipe
      server.close
      server.rd.must_be :closed?
      server.wr.must_be :closed?
    end
  end

  describe "#write" do
    it "writes a NITRA encoded yaml message" do
      server, client = Nitra::Channel.pipe
      server.write(['encode all the things'])
      client.read.must_equal ['encode all the things']
    end
  end

  describe "#read" do
    it "reads NITRA encoded yaml messages" do
      server, client = Nitra::Channel.pipe
      client.write(['encode all the things'])
      server.read.must_equal ['encode all the things']
    end
    it "rejects bad messages" do
      server, client = Nitra::Channel.pipe
      client.wr.write("not a nitra packet\n")
      proc {server.read}.must_raise Nitra::Channel::ProtocolInvalidError
    end
  end
end
