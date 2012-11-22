module Nitra
  class Utils
    # The following taken and modified from the 'parallel' gem.
    # Licensed under the MIT licence, copyright Michael Grosser.
    def self.processor_count
      @processor_count ||= case `uname`
      when /darwin/i
        (`which hwprefs` != '' ? `hwprefs thread_count` : `sysctl -n hw.ncpu`).to_i
      when /linux/i
        `grep -c processor /proc/cpuinfo`.to_i
      when /freebsd/i
        `sysctl -n hw.ncpu`.to_i
      when /solaris2/i
        `psrinfo -p`.to_i # this is physical cpus afaik
      else
        1
      end
    end

    def self.capture_output
      old_stdout = $stdout
      old_stderr = $stderr
      $stdout = $stderr = io = StringIO.new
      begin
        yield
      ensure
        $stdout = old_stdout
        $stderr = old_stderr
      end
      io.string
    end
  end
end
