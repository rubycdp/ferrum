# frozen_string_literal: true

require "strscan"

module Ferrum
  class Frame
    #
    # @api private
    #
    # A script passed to {Runtime#evaluate} and friends. Reads just enough
    # JavaScript to tell a function declaration from an expression and to
    # find where the code and its statements end, skipping strings, template
    # literals, regular expressions and comments so that a `//` inside
    # `"http://…"` isn't mistaken for one.
    #
    # The source is scanned once, in {#initialize}, keeping a stack of open
    # brackets and template literals. On the way it records where the code
    # starts and ends, where the first top-level `(…)` opens and closes,
    # where the first top-level `{…}` closes, where the last statement
    # starts, and whether `await` appears. Every question below is answered
    # from those positions.
    #
    # @example
    #   script = Script.new("// sum\nasync function(a, b = 1) { return a + b };")
    #   script.code          # => "async function(a, b = 1) { return a + b }"
    #   script.declaration?  # => true
    #   script.awaits?       # => false
    #
    class Script
      # A JavaScript identifier, Unicode letters included.
      IDENTIFIER = /[\p{L}\p{Nl}_$][\p{L}\p{Nl}\p{Mn}\p{Mc}\p{Nd}\p{Pc}$]*/

      FUNCTION_DECLARATION = /\A(?:async\s+)?function[\s*(]/
      SINGLE_PARAMETER_ARROW = /\A(?:async\s+)?#{IDENTIFIER}\s*=>/
      ASYNC_PREFIX = /\A(?:async\s*)?\z/
      ARROW = /\A\s*=>/

      COMMENT = %r{//[^\n]*|/\*.*?(?:\*/|\z)}m
      NOISE = /\s+|#{COMMENT}/
      STRING = /"(?:\\.|[^"\\\n])*"?|'(?:\\.|[^'\\\n])*'?/m
      TEMPLATE_CHUNK = /(?:\\.|[^`\\$]|\$(?!\{))*/m
      REGEXP = %r{/(?:\\.|\[(?:\\.|[^\]\\\n])*\]|[^/\\\n\[])+/[A-Za-z]*}
      WORD = /[\p{Alnum}_$]+/

      # Characters ending a value, after which a `/` is a division.
      VALUE_END = %r{[\p{Alnum}_$)\]\}"'`/]}

      # Words after which a `/` starts a regular expression, not a division.
      REGEXP_KEYWORDS = %w[return typeof instanceof in of new delete void throw case do else yield await].freeze

      # Words that continue the statement on the line before them.
      CONTINUING_WORDS = %w[in instanceof of else catch finally].freeze

      # `x++` ends a value, and `++x` starts one.
      INCREMENTS = %w[++ --].freeze

      # Words whose condition in parentheses is followed by the statement they
      # control, which may start on the next line.
      CONTROL_WORDS = %w[if for while with].freeze

      # Words after which a `{` opens an object, not a block.
      OBJECT_KEYWORDS = (REGEXP_KEYWORDS - %w[do else]).freeze

      # A statement that isn't an expression, so it has no value to return.
      STATEMENT = /\A(?:const|let|var|if|for|while|do|switch|try|return|throw|break|continue)\b/

      # @return [String] the script as given.
      attr_reader :source

      # @return [String] the script without surrounding whitespace, comments
      #   and trailing semicolons.
      attr_reader :code

      #
      # @param [String] source
      #
      def initialize(source)
        @source = source.to_s
        @code_start = @code_end = 0
        @words = Set.new
        @scanned = @source.valid_encoding? && (@source.encoding == Encoding::UTF_8 || @source.ascii_only?)
        @scanned ? scan : @code_end = @source.bytesize
        @code = @source.byteslice(@code_start...@code_end)
        @wrapped = Script.new(@code[1...-1]) if parenthesized?
      end

      #
      # Whether the script is a complete function or arrow declaration,
      # rather than an expression that happens to begin with one, such as the
      # immediately invoked `function() { … }()`.
      #
      # @return [Boolean]
      #
      def declaration?
        return false unless @scanned
        return @wrapped.declaration? if @wrapped

        arrow? || (@code.match?(FUNCTION_DECLARATION) && @body_end == @code_end)
      end

      #
      # Whether the script uses `await`, and so has to run in an `async`
      # function.
      #
      # @return [Boolean]
      #
      def awaits?
        uses?("await")
      end

      #
      # Whether the script mentions the given word as code, rather than as a
      # property name or inside a string or comment.
      #
      # @param [String] word
      #
      # @return [Boolean]
      #
      def uses?(word)
        @words.include?(word)
      end

      #
      # Whether the code is several statements, separated by a top-level
      # semicolon, as in `"a(); b"`, or by a line break that can only end a
      # statement, as in `"a()\nb"`, unlike `"a\n.b()"`.
      #
      # @return [Boolean]
      #
      def several_statements?
        !@last_statement_start.nil?
      end

      #
      # The code split before its last statement, so that the value of that
      # one can be returned: `"a = 1\nb"` gives `["a = 1\n", "b"]`.
      #
      # @return [Array(String, String)]
      #
      def split_last_statement
        return ["", @code] unless several_statements?

        [@source.byteslice(@code_start...@last_statement_start), @source.byteslice(@last_statement_start...@code_end)]
      end

      #
      # Whether a line break comes before the code, which right after a
      # `return` ends that statement.
      #
      # @return [Boolean]
      #
      def leading_line_break?
        @scanned && !@code.empty? && @source.byteslice(0...@code_start).include?("\n")
      end

      private

      # Whether the code is one parenthesized group, as in `(function() {})`.
      def parenthesized?
        @paren_open == @code_start && @paren_close == @code_end - 1
      end

      def arrow?
        return true if @code.match?(SINGLE_PARAMETER_ARROW)
        return false unless @paren_close

        @source.byteslice(@code_start...@paren_open).match?(ASYNC_PREFIX) &&
          @source.byteslice((@paren_close + 1)..).match?(ARROW)
      end

      def scan
        scanner = StringScanner.new(@source)
        stack = []
        previous = nil
        ended = line_break = false

        until scanner.eos?
          if (length = scanner.skip(NOISE))
            line_break ||= @source.byteslice(scanner.pos - length, length).include?("\n")
            next
          end

          start = scanner.pos
          top = stack.empty?
          token = scan_token(scanner, stack, previous)
          new_line = line_break && top && new_line_statement?(previous, token, scanner.peek(1))
          @last_statement_start = start if token != ";" && (ended || new_line)
          track_block(token, previous, stack)
          track_condition(token, previous, stack)
          ended = token == ";" && (ended || stack.empty?)
          previous = token
          line_break = false
          @code_start = start if @code_end.zero?
          @code_end = scanner.pos unless previous == ";"
        end
      end

      # A value, or `x++`, followed on the next line by a word, a string, `!`,
      # `~`, `++` or `--` can't continue it, so the line break ends the statement.
      def new_line_statement?(previous, token, following)
        return true if @block_end && ["(", "["].include?(token)
        return false if @condition_end
        return false if previous.nil? || REGEXP_KEYWORDS.include?(previous) || CONTINUING_WORDS.include?(token)

        ends = previous[-1].match?(VALUE_END) || INCREMENTS.include?(previous)
        ends && (token.match?(/\A[\p{Alnum}_$"'~]/) || INCREMENTS.include?(token) || (token == "!" && following != "="))
      end

      # Remembers whether the last top-level `}` closed a block, whose end
      # ends the statement even before a `(` or `[` on the next line.
      def track_block(token, previous, stack)
        @block = block_start?(previous) if token == "{" && stack == ["{"]
        @block_end = token == "}" && stack.empty? && @block
      end

      # Remembers whether the last top-level `)` closed the condition of an
      # `if`, `for` or `while`, whose statement goes on even after a line break.
      def track_condition(token, previous, stack)
        @condition = CONTROL_WORDS.include?(previous) if token == "(" && stack == ["("]
        @condition_end = token == ")" && stack.empty? && @condition
      end

      # A `{` after `)`, `=>`, a statement or a name opens a block, as in
      # `function f() {`, `class A {` or `if (a) {`.
      def block_start?(previous)
        return true if previous.nil? || %w[) > ; }].include?(previous)

        previous.match?(/\A#{WORD}\z/) && !OBJECT_KEYWORDS.include?(previous)
      end

      def scan_token(scanner, stack, previous)
        if scanner.scan(WORD)
          @words << scanner.matched unless previous == "."
          scanner.matched
        elsif scanner.scan(STRING) || (regexp_allowed?(previous) && scanner.scan(REGEXP))
          scanner.matched
        elsif scanner.skip(/`/)
          scan_template(scanner, stack)
        else
          scan_punctuator(scanner, stack)
        end
      end

      def scan_punctuator(scanner, stack)
        char = scanner.getch
        return char + scanner.getch if %w[+ -].include?(char) && scanner.peek(1) == char

        track_parens(char, scanner.pos - 1, stack)
        case char
        when "{", "(", "[" then stack.push(char)
        when ")", "]" then stack.pop
        when "}"
          opened = stack.pop
          return scan_template(scanner, stack) if opened == :template

          @body_end ||= scanner.pos if opened == "{" && stack.empty?
        end
        char
      end

      # Remembers where the first top-level parenthesized group, the
      # parameter list of a declaration, opens and closes.
      def track_parens(char, position, stack)
        return if @paren_close

        case char
        when "(" then @paren_open ||= position if stack.empty?
        when ")" then @paren_close = position if @paren_open && stack == ["("]
        end
      end

      def scan_template(scanner, stack)
        scanner.skip(TEMPLATE_CHUNK)
        if scanner.skip(/\$\{/)
          stack.push(:template)
        else
          scanner.skip(/`/)
        end
        "`"
      end

      def regexp_allowed?(previous)
        return true if previous.nil? || REGEXP_KEYWORDS.include?(previous)

        previous.length == 1 && !previous.match?(VALUE_END)
      end
    end
  end
end
