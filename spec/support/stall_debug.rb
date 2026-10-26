# frozen_string_literal: true

module StallDebug
  LOG_PATH = "/tmp/stall-debug/stall-debug.log"
  MUTEX = Mutex.new

  class << self
    attr_accessor :chrome_pid

    def log(message)
      line = format("%<t>.3f [%<thread>s] %<message>s", t: Process.clock_gettime(Process::CLOCK_MONOTONIC),
                                                        thread: Thread.current.object_id, message: message)
      MUTEX.synchronize do
        FileUtils.mkdir_p(File.dirname(LOG_PATH))
        File.open(LOG_PATH, "a") { |f| f.puts(line) }
      end
    end

    def snapshot(port)
      log("loadavg #{File.read('/proc/loadavg').strip}") if File.exist?("/proc/loadavg")
      log("chrome #{`ps -o pid=,stat=,pcpu=,nlwp= -p #{chrome_pid} 2>&1`.strip}") if chrome_pid
      `ss -tmioe '( sport = :#{port} or dport = :#{port} )' 2>&1`.each_line { |l| log("ss #{l.rstrip}") }
    rescue StandardError => e
      log("snapshot failed #{e.class}: #{e.message}")
    end

    def dump_threads
      Thread.list.each do |thread|
        log("thread #{thread.inspect}\n    #{Array(thread.backtrace).first(8).join("\n    ")}")
      end
    end
  end
end

Ferrum::Client::WebSocket.prepend(Module.new do
  def write_frame(data)
    return super if data.bytesize < 1_000_000

    port = @sock.local_address.ip_port
    StallDebug.log("frame start #{data.bytesize}B port=#{port} write_timeout=#{@write_timeout}")
    0.step(data.bytesize - 1, Ferrum::Client::WebSocket::WRITE_CHUNK_SIZE) do |offset|
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      sampler = Thread.new do
        sleep 0.5
        loop do
          StallDebug.log("chunk at #{offset} stuck for #{(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round(2)}s")
          StallDebug.snapshot(port)
          sleep 0.5
        end
      end
      watchdog = if @write_timeout
                   Concurrent::ScheduledTask.execute(@write_timeout) do
                     StallDebug.log("WATCHDOG fired at offset #{offset}")
                     StallDebug.snapshot(port)
                     StallDebug.dump_threads
                     abandon_stalled_write
                   end
                 end
      begin
        @sock.write(data.byteslice(offset, Ferrum::Client::WebSocket::WRITE_CHUNK_SIZE))
      rescue StandardError => e
        StallDebug.log("chunk at #{offset} raised #{e.class}: #{e.message}")
        raise
      end
      took = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
      StallDebug.log(format("chunk at %<offset>d done in %<took>.3fs", offset: offset, took: took)) if took > 0.2
    ensure
      sampler&.kill
      cancelled = watchdog&.cancel
      StallDebug.log("watchdog cancel returned #{cancelled.inspect} at offset #{offset}") if watchdog && !cancelled
    end
    StallDebug.log("frame done")
  end
end)
