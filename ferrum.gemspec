# frozen_string_literal: true

require_relative "lib/ferrum/version"

Gem::Specification.new do |s|
  s.name          = "ferrum"
  s.version       = Ferrum::VERSION
  s.platform      = Gem::Platform::RUBY
  s.authors       = ["Dmitry Vorotilin"]
  s.email         = ["d.vorotilin@gmail.com"]
  s.homepage      = "https://github.com/rubycdp/ferrum"
  s.summary       = "Ruby headless Chrome driver"
  s.description   = "Ferrum allows you to control headless Chrome browser"
  s.license       = "MIT"
  s.require_paths = ["lib"]
  s.files         = Dir["lib/**/*", "LICENSE", "README.md"]
  s.metadata = {
    "homepage_uri" => "https://ferrum.rubycdp.com/",
    "bug_tracker_uri" => "https://github.com/rubycdp/ferrum/issues",
    "documentation_uri" => "https://github.com/rubycdp/ferrum/blob/main/README.md",
    "changelog_uri" => "https://github.com/rubycdp/ferrum/blob/main/CHANGELOG.md",
    "source_code_uri" => "https://github.com/rubycdp/ferrum",
    "rubygems_mfa_required" => "true"
  }

  s.required_ruby_version = ">= 3.1"

  s.add_dependency "addressable",      "~> 2.5"
  s.add_dependency "base64",           "~> 0.2"
  s.add_dependency "concurrent-ruby",  "~> 1.1"
  s.add_dependency "webrick",          "~> 1.7"
  s.add_dependency "websocket-driver", "~> 0.7"
end
