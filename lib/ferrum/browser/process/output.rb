# frozen_string_literal: true

module Ferrum
  class Browser
    class Process
      #
      # What the browser process wrote to stdout and stderr: keeps the last
      # {LIMIT} lines and writes each one to the `:browser` log channel. Owns
      # the pipe the process writes to, which is read on its own thread for as
      # long as the process lives, so it never fills up and blocks the browser.
      #
      class Output
        LIMIT = 100
        DRAIN_TIMEOUT = 0.5

        def initialize(log = nil)
          @log = log
          @lines = []
          @partial = String.new(encoding: Encoding::BINARY)
          @mutex = Mutex.new
          @io = @reader = nil
        end

        #
        # Opens the pipe and yields its write end, to be given to the process
        # as stdout and stderr. The write end is closed here afterwards, so
        # reading hits the end of the pipe once the process exits.
        #
        # @yieldparam [IO] io
        #
        # @return [void]
        #
        def pipe
          @io, writer = IO.pipe
          yield writer
        ensure
          close_io(writer)
        end

        #
        # Reads the pipe until the output matches, the process exits or the
        # time is up.
        #
        # @param [Regexp] regexp
        #
        # @param [Numeric] timeout
        #
        # @return [MatchData, nil]
        #
        def wait_for(regexp, timeout)
          deadline = Utils::ElapsedTime.monotonic_time + timeout
          while (now = Utils::ElapsedTime.monotonic_time) < deadline
            begin
              self << @io.read_nonblock(512)
            rescue IO::WaitReadable
              @io.wait_readable(deadline - now)
            rescue EOFError
              return
            else
              match = to_s.match(regexp)
              return match if match
            end
          end
        end

        #
        # Keeps reading the pipe on a new thread until it's closed.
        #
        # @return [Thread]
        #
        def follow
          @reader = Utils::Thread.spawn do
            loop { self << @io.readpartial(4096) }
          rescue IOError
            self << "\n" unless @partial.empty?
          end
        end

        #
        # Gives the reading thread {DRAIN_TIMEOUT} seconds to take what the
        # process wrote last, then closes the pipe. The lines are kept.
        #
        # @return [void]
        #
        def close
          @reader&.join(DRAIN_TIMEOUT)
          close_io(@io)
          @io = @reader = nil
        end

        #
        # Adds a chunk of output, which can end in the middle of a line.
        #
        # @param [String] chunk
        #
        # @return [self]
        #
        def <<(chunk)
          lines = @mutex.synchronize do
            *complete, @partial = (@partial + chunk.b).split("\n", -1)
            complete.map! { |line| utf8(line) }
            @lines.concat(complete)
            @lines.shift(@lines.size - LIMIT) if @lines.size > LIMIT
            complete
          end

          lines.each { |line| @log&.browser(line) }
          self
        end

        #
        # The last lines, oldest first.
        #
        # @return [Array<String>]
        #
        def lines
          @mutex.synchronize { @partial.empty? ? @lines.dup : [*@lines, utf8(@partial)] }
        end

        #
        # The last lines joined by newlines.
        #
        # @return [String]
        #
        def to_s
          lines.join("\n")
        end

        private

        def utf8(line)
          line.dup.force_encoding(Encoding::UTF_8).scrub.delete_suffix("\r")
        end

        def close_io(io)
          io.close if io && !io.closed?
        rescue IOError
          raise unless RUBY_ENGINE == "jruby"
        end
      end
    end
  end
end
