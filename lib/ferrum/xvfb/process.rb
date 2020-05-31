# frozen_string_literal: true

module Ferrum
  module Xvfb
    class Process
      attr_reader :process_options
      def initialize(process_options)
        @process_options = process_options
        check_binary!
      end

      def start!
        start_process!
        self
      end

      def check_binary!
        raise "Xvfb not found, please try to install it with: sudo apt-get install -y xvfb" if
            binary_path.empty?
      end

      def display_env_variable
        ":#{display_id}"
      end

      def display_id
        @display_id ||= (Time.now.to_f * 1000).to_i % 100_000_000
      end

      def clean_up_proc
        Proc.new do
          stop_process! if started?
        end
      end

      def start_xvfb_cmd
        binary_path + " :#{display_id}  -screen 0 #{screen_size}"
      end

      def screen_size
        return "1024x768x24" if process_options[:window_size].nil?

        process_options[:window_size].join("x") + "x24"
      end

      def binary_path
        @binary_path ||= execute("which Xvfb")
      end

      def start_process!
        return if started?
        @xvfb_pid = ::Process.spawn(start_xvfb_cmd)
        ::Process.detach(@xvfb_pid)
        @started = true
      end

      def stop_process!
        ::Process.kill('TERM', @xvfb_pid) rescue Errno::ESRCH
        @started = false
        sleep 0.1 # is needed, process not ending this fast
      end

      def execute(cmd)
        `#{cmd}`.strip
      end

      def started?
        @started
      end

      def alive?
        return false unless started?
        process_alive?
      end

      def process_alive?
        begin
          ::Process::kill(0, @xvfb_pid) == 1
        rescue Errno::ESRCH
          false
        end
      end
    end
  end
end