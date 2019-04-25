Gem::Specification.new do |spec|
  spec.name        = 'fluent-plugin-honeycomb'
  spec.version     = '0.7.1'

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

  spec.required_ruby_version = '>= 2.0.0'

  spec.add_runtime_dependency "fluentd", "< 1.5"
  spec.add_runtime_dependency "http", "< 3"

  spec.add_development_dependency "appraisal"
  spec.add_development_dependency "bundler"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "webmock"
  spec.add_development_dependency "test-unit"
  spec.add_development_dependency "mocha"
  spec.add_development_dependency "simplecov"
  spec.add_development_dependency "coveralls"
  spec.add_development_dependency "bump"
  spec.add_development_dependency "timecop"
end
