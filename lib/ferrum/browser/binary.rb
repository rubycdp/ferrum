# frozen_string_literal: true

module Ferrum
  class Browser
    #
    # Locates an executable on the system `PATH`, mirroring what a shell's
    # `which`/`where` would find. Used to resolve the browser (and Xvfb)
    # binary when no explicit path is configured.
    #
    module Binary
      module_function

      #
      # Finds the first executable path for the given command(s) on `PATH`.
      #
      # @param [String, Array<String>] commands
      #   Command name(s) to look up.
      #
      # @return [String, nil]
      #   Absolute path to the executable, or `nil` if none is found.
      #
      def find(commands)
        enum(commands).first
      end

      #
      # Finds all executable paths for the given command(s) on `PATH`.
      #
      # @param [String, Array<String>] commands
      #   Command name(s) to look up.
      #
      # @return [Array<String>]
      #   Absolute paths to matching executables.
      #
      def all(commands)
        enum(commands).force
      end

      #
      # Lazily enumerates executable paths for the given command(s) on `PATH`.
      #
      # @param [String, Array<String>] commands
      #   Command name(s) to look up.
      #
      # @return [Enumerator::Lazy]
      #   Lazy enumerator yielding matching executable paths.
      #
      def enum(commands)
        paths, exts = prepare_paths
        cmds = Array(commands).product(paths, exts)
        lazy_find(cmds)
      end

      #
      # Directories on `PATH` and the executable extensions to try against them.
      #
      # @return [Array(Array<String>, Array<String>)]
      #   The `PATH` directories, and the extensions from `PATHEXT` (plus `""`).
      #
      # @raise [EmptyPathError]
      #   If `PATH` is empty.
      #
      def prepare_paths
        exts = (ENV.key?("PATHEXT") ? ENV.fetch("PATHEXT").split(";") : []) << ""
        paths = ENV["PATH"].split(File::PATH_SEPARATOR)
        raise EmptyPathError if paths.empty?

        [paths, exts]
      end

      # rubocop:disable Style/CollectionCompact
      def lazy_find(cmds)
        cmds.lazy.map do |cmd, path, ext|
          absolute_path = File.absolute_path(cmd)
          is_absolute_path = absolute_path == cmd
          cmd = File.expand_path("#{cmd}#{ext}", path) unless is_absolute_path

          next unless File.executable?(cmd)
          next if File.directory?(cmd)

          cmd
        end.reject(&:nil?) # .compact isn't defined on Enumerator::Lazy
      end
      # rubocop:enable Style/CollectionCompact
    end
  end
end
