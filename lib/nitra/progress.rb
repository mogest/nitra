class Nitra::Progress
  attr_accessor :file_count, :files_completed, :example_count, :failure_count, :output, :failure

  def initialize
    @file_count = @files_completed = @example_count = @failure_count = 0
    @output = ""
    @failure = false
  end
end
