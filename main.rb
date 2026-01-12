require_relative "parser"
require_relative "code_writer"

class VMTranslator
  def initialize(file_path)
    @parser = Parser.new(file_path)
    @code_writer = CodeWriter.new(file_path)
  end

  def translate
    while @parser.has_more_lines?
      @parser.advance
      if @parser.command_type == Parser::C_PUSH || @parser.command_type == Parser::C_POP
        @code_writer.write_push_pop(command: @parser.command_type, segment: @parser.arg1, index: @parser.arg2)
      else
        @code_writer.write_arithmetic(@parser.arg1)
      end
    end

    @code_writer.close
  end
end

vm_translator = VMTranslator.new(ARGV[0])
vm_translator.translate
