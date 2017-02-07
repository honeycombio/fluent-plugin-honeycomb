Gem::Specification.new do |spec|
  spec.name        = 'fluent-plugin-honeycomb'
  spec.version     = '0.1.0'
  spec.date        = '2017-02-07'

  spec.summary     = "send data to Honeycomb"
  spec.description = "Ruby gem for sending data to Honeycomb"
  spec.authors     = ['The Honeycomb.io Team']
  spec.email       = 'support@honeycomb.io'
  spec.files       = []
  spec.homepage    = 'https://github.com/honeycombio/fluent-plugin-honeycomb'
  spec.license     = 'Apache-2.0'

  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.require_paths = ["lib"]

  spec.required_ruby_version = '>= 2.2.0'

  spec.add_runtime_dependency "libhoney", "~> 1.0"
  spec.add_runtime_dependency "fluentd", "~> 0.12"

  spec.add_development_dependency "bundler", "~> 1.7"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "webmock", "~> 2.1"
  spec.add_development_dependency "test-unit"
end
