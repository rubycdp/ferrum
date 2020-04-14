# frozen_string_literal: true

module Ferrum
  class Browser
    class Environment
      attr_reader :process_options, :xvfb
      def initialize(process_options)
        @process_options = process_options
      end

      def to_h
        if xvfb?
          xvfb_env
        else
          default_env
        end
      end

      def cleanup!
        close_xvfb! if xvfb && xvfb.started?
      end

      private

        def default_env
          {}
        end

        def xvfb_env
          manage_xvfb!
          { "DISPLAY" => xvfb.display_env_variable }
        end

        def xvfb?
          process_options[:headless] == :xvfb
        end

        def manage_xvfb!
          @xvfb = Ferrum::Xvfb::Process.new(process_options).start!

          ObjectSpace.define_finalizer(self, xvfb.clean_up_proc)
        end

        def close_xvfb!
          xvfb.clean_up_proc.call
          ObjectSpace.undefine_finalizer(self)
        end
    end
  end
end