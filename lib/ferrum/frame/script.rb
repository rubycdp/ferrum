# frozen_string_literal: true

require "strscan"

module Ferrum
  class Frame
    #
    # @api private
    #
    # A script passed to {Runtime#evaluate} and friends. Reads just enough
    # JavaScript to tell a function declaration from an expression, to find
    # its parameters and where the code ends, skipping strings, template
    # literals, regular expressions and comments so that a `//` inside
    # `"http://…"` isn't mistaken for one.
    #
    # The source is scanned once, in {#initialize}, keeping a stack of open
    # brackets and template literals. On the way it records where the code
    # starts and ends, where the first top-level `(…)` and the commas inside
    # it are, where the first top-level `{…}` closes, and whether `await`
    # appears. Every question below is answered from those positions.
    #
    # @example
    #   script = Script.new("// sum\nasync function(a, b = 1) { return a + b };")
    #   script.code          # => "async function(a, b = 1) { return a + b }"
    #   script.declaration?  # => true
    #   script.parameters    # => ["a", "b"]
    #   script.awaits?       # => false
    #
    class Script
      # A JavaScript identifier, Unicode letters included.
      IDENTIFIER = /[\p{L}\p{Nl}_$][\p{L}\p{Nl}\p{Mn}\p{Mc}\p{Nd}\p{Pc}$]*/

      FUNCTION_DECLARATION = /\A(?:async\s+)?function[\s*(]/
      NAMED_FUNCTION = /\A(?:async\s+)?function\s*\*?\s*#{IDENTIFIER}/
      SINGLE_PARAMETER_ARROW = /\A(?:async\s+)?(#{IDENTIFIER})\s*=>/
      ASYNC_PREFIX = /\A(?:async\s*)?\z/
      ARROW = /\A\s*=>/

      # A parameter's name, followed by its default value if any.
      PARAMETER = /\A(#{IDENTIFIER})\s*(?:=(?!>)|\z)/

      JS_IDENTIFIER = /\A#{IDENTIFIER}\z/

      # Words that can't name a parameter.
      RESERVED_WORDS = %w[
        arguments await break case catch class const continue debugger default delete do else enum eval export extends
        false finally for function if implements import in instanceof interface let new null package private protected
        public return static super switch this throw true try typeof var void while with yield
      ].freeze

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

      # @return [String] the script as given.
      attr_reader :source

      # @return [String] the script without surrounding whitespace, comments
      #   and trailing semicolons.
      attr_reader :code

      #
      # @param [String] source
      #
      def initialize(source)
        @source = utf8(source.to_s)
        @code_start = @code_end = 0
        @parameter_commas = []
        @several_statements = false
        @words = Set.new
        @scanned = @source.valid_encoding?
        @scanned ? scan : @code_end = @source.bytesize
        @code = @source.byteslice(@code_start...@code_end)
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

        arrow? || (@code.match?(FUNCTION_DECLARATION) && @body_end == @code_end)
      end

      #
      # Whether the script is a declaration of a named function, which as a
      # function body is a statement defining it rather than a value.
      #
      # @return [Boolean]
      #
      def named_function?
        declaration? && @code.match?(NAMED_FUNCTION)
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
      # Whether a top-level semicolon separates the code into several
      # statements, as in `"a(); b"`. Statements separated only by line
      # breaks aren't detected, since telling `"a\nb"` from `"a\n.b()"` takes
      # a parser.
      #
      # @return [Boolean]
      #
      def several_statements?
        @several_statements
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

      #
      # The parameter names of a declaration, or `nil` when they can't be
      # read plainly, e.g. because of destructuring or rest parameters.
      #
      # @return [Array<String>, nil]
      #
      def parameters
        return unless @scanned

        if (single = @code[SINGLE_PARAMETER_ARROW, 1])
          return [single]
        end
        return unless @paren_close

        bounds = [@paren_open, *@parameter_commas, @paren_close]
        pieces = bounds.each_cons(2).map { |from, to| @source.byteslice((from + 1)...to).gsub(COMMENT, " ").strip }
        pieces.pop if pieces.last.empty?
        names = pieces.map { |piece| piece[PARAMETER, 1] }
        names if names.all?
      end

      private

      def utf8(source)
        return source if source.encoding == Encoding::UTF_8
        return source.dup.force_encoding(Encoding::UTF_8) if source.encoding == Encoding::BINARY

        source.encode(Encoding::UTF_8)
      rescue EncodingError
        source.dup.force_encoding(Encoding::UTF_8)
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
        separated = false

        until scanner.eos?
          next if scanner.skip(NOISE)

          start = scanner.pos
          previous = scan_token(scanner, stack, previous)
          @code_start = start if @code_end.zero?
          @code_end = scanner.pos unless previous == ";"
          @several_statements ||= separated && previous != ";"
          separated ||= previous == ";" && stack.empty?
        end
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
        track_parameters(char, scanner.pos - 1, stack)
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
      # parameter list of a declaration, opens, closes and is split by commas.
      def track_parameters(char, position, stack)
        return if @paren_close

        case char
        when "(" then @paren_open ||= position if stack.empty?
        when ")" then @paren_close = position if @paren_open && stack == ["("]
        when "," then @parameter_commas << position if @paren_open && stack == ["("]
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
