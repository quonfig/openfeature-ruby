# frozen_string_literal: true

lib = File.expand_path('lib', __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'quonfig/openfeature/version'

Gem::Specification.new do |spec|
  spec.name        = 'quonfig-openfeature'
  spec.version     = Quonfig::OpenFeature::VERSION
  spec.authors     = ['Jeff Dwyer']
  spec.email       = ['jeff@quonfig.com']

  spec.summary     = 'OpenFeature provider for Quonfig (Ruby)'
  spec.description = 'OpenFeature provider that wraps the quonfig Ruby SDK and ' \
                     'implements the OpenFeature Ruby provider contract.'
  spec.homepage    = 'https://github.com/quonfig/openfeature-ruby'
  spec.license     = 'MIT'

  spec.required_ruby_version = '>= 3.0'

  spec.files = Dir[
    'lib/**/*.rb',
    'README.md',
    'LICENSE.txt',
    'VERSION',
    'CHANGELOG.md'
  ].select { |f| File.file?(f) }

  spec.require_paths = ['lib']

  spec.add_dependency 'openfeature-sdk', '>= 0.5'
  spec.add_dependency 'quonfig', '>= 0.0.13'

  spec.add_development_dependency 'minitest', '>= 5.0'
  spec.add_development_dependency 'minitest-reporters', '>= 1.0'
  spec.add_development_dependency 'rake', '>= 13.0'
  spec.metadata['rubygems_mfa_required'] = 'true'
end
