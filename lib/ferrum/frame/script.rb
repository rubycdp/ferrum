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
    class Script
      FUNCTION_DECLARATION = /\A(?:async\s+)?function[\s*(]/
      NAMED_FUNCTION = /\A(?:async\s+)?function\s*\*?\s*[A-Za-z_$]/
      SINGLE_PARAMETER_ARROW = /\A(?:async\s+)?([A-Za-z_$][\w$]*)\s*=>/
      ASYNC_PREFIX = /\A(?:async\s*)?\z/
      ARROW = /\A\s*=>/

      # A parameter's name, followed by its default value if any.
      PARAMETER = /\A([A-Za-z_$][\w$]*)\s*(?:=(?!>)|\z)/

      JS_IDENTIFIER = /\A[A-Za-z_$][A-Za-z0-9_$]*\z/

      # Words that can't name a parameter.
      RESERVED_WORDS = %w[
        arguments await break case catch class const continue debugger default delete do else enum eval export extends
        false finally for function if implements import in instanceof interface let new null package private protected
        public return static super switch this throw true try typeof var void while with yield
      ].freeze

      NOISE = %r{\s+|//[^\n]*|/\*.*?(?:\*/|\z)}m
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
        @source = source.to_s
        @code_start = @code_end = 0
        @parameter_commas = []
        @words = Set.new
        scan
        @code = @source[@code_start...@code_end]
      end

      #
      # Whether the script is a complete function or arrow declaration,
      # rather than an expression that happens to begin with one, such as the
      # immediately invoked `function() { … }()`.
      #
      # @return [Boolean]
      #
      def declaration?
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
      # Whether a line break comes before the code, which right after a
      # `return` ends that statement.
      #
      # @return [Boolean]
      #
      def leading_line_break?
        !@code.empty? && @source[0...@code_start].include?("\n")
      end

      #
      # The parameter names of a declaration, or `nil` when they can't be
      # read plainly, e.g. because of destructuring or rest parameters.
      #
      # @return [Array<String>, nil]
      #
      def parameters
        if (single = @code[SINGLE_PARAMETER_ARROW, 1])
          return [single]
        end
        return unless @paren_close

        bounds = [@paren_open, *@parameter_commas, @paren_close]
        pieces = bounds.each_cons(2).map { |from, to| @source[(from + 1)...to].strip }
        pieces.pop if pieces.last.empty?
        names = pieces.map { |piece| piece[PARAMETER, 1] }
        names if names.all?
      end

      private

      def arrow?
        return true if @code.match?(SINGLE_PARAMETER_ARROW)
        return false unless @paren_close

        @source[@code_start...@paren_open].match?(ASYNC_PREFIX) && @source[(@paren_close + 1)..].match?(ARROW)
      end

      def scan
        scanner = StringScanner.new(@source)
        stack = []
        previous = nil

        until scanner.eos?
          next if scanner.skip(NOISE)

          start = scanner.pos
          previous = scan_token(scanner, stack, previous)
          @code_start = start if @code_end.zero?
          @code_end = scanner.pos unless previous == ";"
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
          return scan_template(scanner, stack) if stack.pop == :template

          @body_end ||= scanner.pos if stack.empty?
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
