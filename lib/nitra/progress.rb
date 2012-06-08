class Nitra::Progress
  attr_accessor :file_count, :files_completed, :example_count, :failure_count, :output

  def initialize
    @file_count = @files_completed = @example_count = @failure_count = 0
    @output = ""
  end
end
