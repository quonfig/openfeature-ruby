# frozen_string_literal: true

require 'minitest/autorun'
begin
  require 'minitest/reporters'
  Minitest::Reporters.use! unless ENV['RM_INFO']
rescue LoadError
  # reporters are optional
end

require 'quonfig/openfeature'

module QuonfigOFTestHelpers
  # Shared fixtures from the quonfig/integration-test-data sibling repo.
  # CI clones it alongside this repo at the same level. Locally it's expected
  # to live at ../../integration-test-data relative to the openfeature-ruby
  # checkout (i.e. as a sibling under the monorepo root).
  INTEGRATION_FIXTURES_DIR =
    if (env = ENV['QUONFIG_INTEGRATION_TEST_DATA_DIR']) && !env.empty?
      env
    else
      [
        File.expand_path('../../integration-test-data/data/integration-tests', __dir__),
        File.expand_path('../../../integration-test-data/data/integration-tests', __dir__)
      ].find { |p| Dir.exist?(p) } ||
        File.expand_path('../../integration-test-data/data/integration-tests', __dir__)
    end

  module_function

  def fixtures_dir
    INTEGRATION_FIXTURES_DIR
  end

  def build_provider(**overrides)
    Quonfig::OpenFeature::Provider.new(
      sdk_key: 'test-sdk-key',
      datadir: fixtures_dir,
      environment: 'Production',
      enable_sse: false,
      enable_polling: false,
      **overrides
    )
  end

  def init_provider(**overrides)
    p = build_provider(**overrides)
    p.init
    p
  end
end

Minitest::Test.class_eval do
  include QuonfigOFTestHelpers
  extend QuonfigOFTestHelpers
end
