require "ferrum"

def kill_browsers
  processes = []
  running = `ps aux`.split("\n")
  Ferrum::Browser::Chrome::LINUX_BIN_PATH.each do |binary_name|
    reg = /#{binary_name}/
    running.each do |line|
      processes << line if line.match(reg)
    end
  end

  processes.map! { |l| l.split(" ")[1] }

  processes.each { |pid| `kill -9 #{pid} || true` }
end

desc "kill all instances of chrome"
task :kill_browsers do
  print "this will kill all google chrome instances, are you sure? y/n\n"

  next unless STDIN.gets.chomp.chomp.match(/y/i)

  kill_browsers
  kill_browsers
end