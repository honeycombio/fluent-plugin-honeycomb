Gem::Specification.new do |spec|
  spec.name        = 'fluent-plugin-honeycomb'
  spec.version     = '0.2.1'
  spec.date        = '2017-02-07'

  spec.summary     = "Fluentd output plugin for Honeycomb.io"
  spec.description = "Fluentd output plugin for Honeycomb.io"
  spec.authors     = ['The Honeycomb.io Team']
  spec.email       = 'support@honeycomb.io'
  spec.files       = []
  spec.homepage    = 'https://github.com/honeycombio/fluent-plugin-honeycomb'
  spec.license     = 'Apache-2.0'

  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.require_paths = ["lib"]

  spec.required_ruby_version = '>= 2.1.0'

  spec.add_runtime_dependency "fluentd", "~> 0.12"
  spec.add_runtime_dependency "http", "~> 2.0"

  spec.add_development_dependency "bundler", "~> 1.7"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "webmock", "~> 2.1"
  spec.add_development_dependency "test-unit"
  spec.add_development_dependency "simplecov"
  spec.add_development_dependency "coveralls"
  spec.add_development_dependency "bump"
  spec.add_development_dependency "timecop"
end
