class Parser
  C_ARITHMETIC = :C_ARITHMETIC
  C_PUSH = :C_PUSH
  C_POP = :C_POP

  C_LABEL = :C_LABEL
  C_GOTO = :C_GOTO
  C_IF_GOTO = :C_IF_GOTO

  C_FUNCTION = :C_FUNCTION
  C_RETURN = :C_RETURN
  
  def initialize(file_path)
    # ファイルの内容を配列として読み込む
    @lines = File.readlines(file_path, chomp: true)
                 .map { |line| line.split("//").first&.strip }
                 .reject { |line| line.nil? || line.empty? }

    @current_index = -1
    @current_command = nil
  end

  def has_more_lines?
    @current_index + 1 < @lines.size
  end

  def advance
    @current_index += 1
    @current_command = @lines[@current_index]
    @parts = @current_command.split
  end

  def command_type
    if @current_command.start_with?("add")  ||
        @current_command.start_with?("sub") ||
        @current_command.start_with?("neg") ||
        @current_command.start_with?("eq")  ||
        @current_command.start_with?("gt")  ||
        @current_command.start_with?("lt")  ||
        @current_command.start_with?("and") ||
        @current_command.start_with?("or")  ||
        @current_command.start_with?("not")
      C_ARITHMETIC
    elsif @current_command.start_with?("push")
      C_PUSH
    elsif @current_command.start_with?("pop")
      C_POP
    elsif @current_command.start_with?("label")
      C_LABEL
    elsif @current_command.start_with?("goto")
      C_GOTO
    elsif @current_command.start_with?("if-goto")
      C_IF_GOTO
    elsif @current_command.start_with?("function")
      C_FUNCTION
    elsif @current_command.start_with?("return")
      C_RETURN
    end
  end

  def arg1
    case command_type
    when C_ARITHMETIC
      @parts[0]
    when C_PUSH, C_POP, C_LABEL, C_GOTO, C_IF_GOTO, C_FUNCTION
      @parts[1]
    end
  end

  def arg2
    case command_type
    when C_PUSH, C_POP, C_FUNCTION
      @parts[2]
    end
  end
end