# frozen_string_literal: true

source 'https://rubygems.org'

# quonfig resolves from RubyGems via the gemspec runtime dependency. To build
# against a local sdk-ruby checkout (CI does, with ../sdk-ruby), set
# QUONFIG_SDK_RUBY_PATH. Never commit a Gemfile.lock generated with it set: a
# PATH source outside the repo breaks Dependabot's file fetch.
if (sdk_ruby_path = ENV.fetch('QUONFIG_SDK_RUBY_PATH', nil))
  gem 'quonfig', path: sdk_ruby_path
end

group :development do
  gem 'rubocop', '~> 1.86'
end

gemspec
