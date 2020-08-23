lib = File.expand_path("lib", __dir__)
$:.unshift(lib) unless $:.include?(lib)

require "ferrum/version"

Gem::Specification.new do |s|
  s.name          = "ferrum"
  s.version       = Ferrum::VERSION
  s.platform      = Gem::Platform::RUBY
  s.authors       = ["Dmitry Vorotilin"]
  s.email         = ["d.vorotilin@gmail.com"]
  s.homepage      = "https://github.com/route/ferrum"
  s.summary       = "Ruby headless Chrome driver"
  s.description   = "Ferrum allows you to control headless Chrome browser"
  s.license       = "MIT"
  s.require_paths = ["lib"]
  s.files         = Dir["{lib}/**/*"] + %w[LICENSE README.md]

  s.required_ruby_version = ">= 2.3.0"

  s.add_runtime_dependency "websocket-driver", ">= 0.6", "< 0.8"
  s.add_runtime_dependency "cliver",           "~> 0.3"
  s.add_runtime_dependency "concurrent-ruby",  "~> 1.1"
  s.add_runtime_dependency "addressable",      "~> 2.5"

  s.add_development_dependency "rake",         "~> 13.0"
  s.add_development_dependency "rspec",        "~> 3.8"
  s.add_development_dependency "sinatra",      "~> 2.0"
  s.add_development_dependency "puma",         "~> 4.1"
  s.add_development_dependency "image_size",   "~> 2.0"
  s.add_development_dependency "pdf-reader",   "~> 2.2"
  s.add_development_dependency "chunky_png",   "~> 1.3"
end
