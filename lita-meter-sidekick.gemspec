Gem::Specification.new do |spec|
  spec.name          = "lita-meter-sidekick"
  spec.version       = "0.1.0"
  spec.authors       = ["Peyton Vaughn"]
  spec.email         = ["pvaughn@6fusion.com"]
#  spec.description   = "CI/CD operations for Lita + 6fusion Meter."
  spec.summary       = "CI/CD operations for Lita + 6fusion Meter"
  spec.homepage      = "http://6fusion.com/"
  spec.license       = "MIT"
  spec.metadata      = { "lita_plugin_type" => "handler" }

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_runtime_dependency "lita", "~> 4.7"
  spec.add_runtime_dependency "aws-sdk", "~> 2.9"

  spec.add_development_dependency "bundler", "~> 1.3"
#  spec.add_development_dependency "pry-byebug",
  spec.add_development_dependency "rake", "~> 11.2"
#  spec.add_development_dependency "rack-test"
#  spec.add_development_dependency "rspec", ">= 3.0.0"
end
