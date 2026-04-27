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
  FIXTURES_DIR = File.expand_path('fixtures', __dir__)

  module_function

  def fixtures_dir
    FIXTURES_DIR
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
