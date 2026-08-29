# frozen_string_literal: true

require "fileutils"
require "ferrum/utils/elapsed_time"
require "ferrum/utils/platform"

module Ferrum
  class Browser
    class Process
      #
      # OS-level process termination and user-data-directory removal, kept
      # separate from the rest of {Process} (spawning, CDP handshake, ...).
      # Both the GC finalizer and the explicit {Process#stop} path need to
      # run the exact same kill/cleanup logic on plain pid/path values --
      # never on `self`. A finalizer proc that closes over the object it's
      # attached to creates a reference cycle GC can never collect, so the
      # finalizer would never run; keeping this logic as free functions
      # taking plain arguments sidesteps that entirely.
      #
      module Killer
        module_function

        KILL_TIMEOUT = 2
        WAIT_KILLED = 0.05
        REAP_TIMEOUT = 0.5
        REMOVE_DIR_RETRIES = 5
        REMOVE_DIR_RETRY_DELAY = 0.1

        #
        # Kills the process at the given pid (and its process group, if
        # any), escalating from TERM to KILL if it doesn't exit within
        # {KILL_TIMEOUT} seconds.
        #
        # @param [Integer] pid
        #
        # @return [void]
        #
        def kill(pid)
          if Utils::Platform.windows?
            # Process.kill is unreliable on Windows
            ::Process.kill("KILL", pid) unless system("taskkill /f /t /pid #{pid} >NUL 2>NUL")
            return
          end

          send_signal(pid, "TERM")
          start = Utils::ElapsedTime.monotonic_time
          leader_exited = false
          loop do
            # The leader (the pid we actually spawned and can #wait on) may
            # exit well before the rest of its process group does -- e.g. a
            # renderer/zygote that ignores TERM. Reaping the leader must not
            # by itself end the loop, or that child is orphaned forever
            # since KILL is only ever sent from the timeout branch below.
            leader_exited ||= !::Process.wait(pid, ::Process::WNOHANG).nil?
            break if leader_exited && !process_group_alive?(pid)

            sleep(WAIT_KILLED)
            next unless Utils::ElapsedTime.timeout?(start, KILL_TIMEOUT)

            send_signal(pid, "KILL")
            wait_reaped(pid) unless leader_exited
            break
          end
        rescue Errno::ESRCH, Errno::ECHILD
          # nop
        end

        #
        # Waits for `pid` to become reapable, giving up after `timeout`.
        #
        # Deliberately a bounded poll rather than a blocking `Process.wait`.
        # {#process_killer} installs {#kill} as an `ObjectSpace` finalizer, so
        # it can run while the interpreter is shutting down, and a blocking
        # wait there never returns.
        #
        # @param [Integer] pid
        # @param [Float] timeout
        #
        # @return [Integer, nil]
        #   The reaped pid, or `nil` if it didn't exit in time or wasn't ours.
        #
        def wait_reaped(pid, timeout: REAP_TIMEOUT)
          start = Utils::ElapsedTime.monotonic_time
          loop do
            reaped = ::Process.wait(pid, ::Process::WNOHANG)
            return reaped if reaped
            return nil if Utils::ElapsedTime.timeout?(start, timeout)

            sleep(WAIT_KILLED)
          end
        rescue Errno::ECHILD, Errno::ESRCH
          nil
        end

        #
        # Builds a finalizer proc that kills the process with the given pid.
        #
        # @param [Integer] pid
        #   Process id to kill.
        #
        # @return [Proc]
        #
        def process_killer(pid)
          proc { kill(pid) }
        end

        #
        # Signals the whole process group Chrome was spawned into (it's
        # spawned with `pgroup: true`), so its child processes (renderer,
        # GPU, zygote, ...) are cleaned up too instead of being left
        # orphaned. Falls back to signaling just the pid directly if
        # there's no such process group to signal (e.g. Xvfb, which isn't
        # spawned with `pgroup: true`) or the group can't be signaled.
        #
        # @param [Integer] pid
        # @param [String] name
        #
        # @return [void]
        #
        def send_signal(pid, name)
          ::Process.kill(name, -pid)
        rescue Errno::EPERM, Errno::ESRCH
          ::Process.kill(name, pid)
        end

        #
        # Checks whether any process in pid's process group is still alive.
        #
        # @param [Integer] pid
        #
        # @return [Boolean]
        #
        def process_group_alive?(pid)
          ::Process.kill(0, -pid)
          true
        rescue Errno::ESRCH
          false
        rescue Errno::EPERM
          true
        end

        #
        # Removes the given directory, retrying with exponential backoff on
        # transient errors. Chrome can briefly hold file locks right after
        # being killed, so the directory may not be removable on the first
        # try; retrying avoids leaking temp directories in that case.
        #
        # @param [String] path
        #   Directory to remove.
        # @param [Integer] retries
        #   Maximum number of removal attempts.
        # @param [Float] delay
        #   Base delay, in seconds, before the first retry; doubles on each
        #   subsequent attempt.
        #
        # @return [void]
        #
        def remove_directory(path, retries: REMOVE_DIR_RETRIES, delay: REMOVE_DIR_RETRY_DELAY)
          retries.times do |attempt|
            FileUtils.remove_entry(path)
            break
          rescue Errno::ENOENT
            break
          rescue Errno::ENOTEMPTY, Errno::EBUSY, Errno::EACCES, Errno::EPERM => e
            raise e if attempt == retries - 1

            sleep(delay * (2**attempt))
          end
        rescue StandardError => e
          warn("[Ferrum] Failed to remove user data dir #{path}: #{e.class}: #{e.message}")
        end

        #
        # Builds a finalizer proc that removes the directory at the given
        # path.
        #
        # @param [String] path
        #   Directory to remove.
        #
        # @return [Proc]
        #
        def directory_remover(path)
          proc { remove_directory(path) }
        end
      end
    end
  end
end
