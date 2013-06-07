require 'yaml'

module Nitra
  class Channel
    ProtocolInvalidError = Class.new(StandardError)

    attr_reader :rd, :wr
    attr_accessor :raise_epipe_on_write_error

    def initialize(rd, wr)
      @rd = rd
      @wr = wr
    end

    def self.pipe
      c_rd, s_wr = IO.pipe
      s_rd, c_wr = IO.pipe
      [new(c_rd, c_wr), new(s_rd, s_wr)]
    end

    def self.read_select(channels)
      fds = IO.select(channels.collect(&:rd))
      fds.first.collect do |fd|
        channels.detect {|c| c.rd == fd}
      end
    end

    def close
      rd.close
      wr.close
    end

    def read
      return unless line = rd.gets
      if result = line.strip.match(/\ANITRA,(\d+)\z/)
        data = rd.read(result[1].to_i)
        YAML.load(data)
      else
        raise ProtocolInvalidError, "Expected nitra length line, got #{line.inspect}"
      end
    end

    def write(data)
      encoded = YAML.dump(data)
      wr.write("NITRA,#{encoded.bytesize}\n#{encoded}")
      wr.flush
    rescue Errno::EPIPE
      raise if raise_epipe_on_write_error
    end
  end
end
