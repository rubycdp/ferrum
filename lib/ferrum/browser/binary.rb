# frozen_string_literal: true

module Ferrum
  class Browser
    module Binary
      module_function

      def find(commands)
        enum(commands).first
      end

      def all(commands)
        enum(commands).force
      end

      def enum(commands)
        paths, exts = prepare_paths
        cmds = Array(commands).product(paths, exts)
        lazy_find(cmds)
      end

      def prepare_paths
        exts = (ENV.key?("PATHEXT") ? ENV.fetch("PATHEXT").split(";") : []) << ""
        paths = ENV["PATH"].split(File::PATH_SEPARATOR)
        raise EmptyPathError if paths.empty?

        [paths, exts]
      end

      def lazy_find(cmds)
        cmds.lazy.filter_map do |cmd, path, ext|
          cmd = File.expand_path("#{cmd}#{ext}", path) unless File.absolute_path?(cmd)

          next unless File.executable?(cmd)
          next if File.directory?(cmd)

          cmd
        end
      end
    end
  end
end
