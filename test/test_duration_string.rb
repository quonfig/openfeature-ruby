# frozen_string_literal: true

# fetch_string_value on a duration config reads through sdk-ruby's public
# Client#evaluate_details (quonfig >= 2.1.0, qfg-177f): one evaluation, the
# stored ISO 8601 text, no reach into the resolver or private client methods.
require 'test_helper'

class TestDurationString < Minitest::Test
  Provider  = Quonfig::OpenFeature::Provider
  Reason    = ::OpenFeature::SDK::Provider::Reason
  ErrorCode = ::OpenFeature::SDK::Provider::ErrorCode
  Details   = ::Quonfig::EvaluationDetails

  KEY = 'duration.key'

  # A client double holding one duration config. It records every read, so a
  # test can pin which client methods the provider calls.
  class DurationClient
    Store = Struct.new(:config) do
      def get(_key)
        config
      end
    end

    attr_reader :calls, :store

    def initialize(details)
      @details = details
      @calls = []
      @store = Store.new({ 'key' => KEY, 'valueType' => 'duration' })
    end

    def evaluate_details(key, context: nil)
      @calls << [:evaluate_details, key, context]
      @details
    end

    def method_missing(name, *args, **_kwargs)
      @calls << [name, *args]
      raise NoMethodError, "provider called #{name} on the duration client" unless name.to_s.end_with?('_details')

      Details.new(value: nil, reason: Details::REASON_ERROR, error_code: Details::ERROR_TYPE_MISMATCH)
    end

    def respond_to_missing?(_name, _include_private = false)
      false
    end
  end

  def read(details, context: nil)
    client = DurationClient.new(details)
    provider = Provider.new(client: client)
    provider.init
    [provider.fetch_string_value(flag_key: KEY, default_value: 'PT0S', evaluation_context: context), client]
  end

  def static(value)
    Details.new(value: value, reason: Details::REASON_STATIC, variant: 'static',
                flag_metadata: { 'config_type' => 'config' }, value_type: 'duration')
  end

  def test_valid_duration_is_one_evaluate_details_call
    details, client = read(static('PT90S'))
    assert_equal 'PT90S', details.value
    assert_equal Reason::STATIC, details.reason
    assert_equal 'static', details.variant
    assert_equal({ 'config_type' => 'config' }, details.flag_metadata)
    assert_nil details.error_code
    assert_equal [:evaluate_details], client.calls.map(&:first)
  end

  def test_split_reason_and_variant_carry_through
    split = Details.new(value: 'PT1M', reason: Details::REASON_SPLIT, variant: 'split:1',
                        flag_metadata: { 'weighted_value_index' => 1 }, value_type: 'duration')
    details, = read(split)
    assert_equal 'PT1M', details.value
    assert_equal Reason::SPLIT, details.reason
    assert_equal 'split:1', details.variant
  end

  def test_mapped_context_is_passed_to_evaluate_details
    ctx = ::OpenFeature::SDK::EvaluationContext.new(targeting_key: 'u1')
    _, client = read(static('PT1S'), context: ctx)
    assert_equal({ 'user' => { 'id' => 'u1' } }, client.calls.first[2])
  end

  def test_malformed_stored_duration_is_parse_error
    details, client = read(static('30s'))
    assert_equal 'PT0S', details.value
    assert_equal Reason::ERROR, details.reason
    assert_equal ErrorCode::PARSE_ERROR, details.error_code
    assert_equal [:evaluate_details], client.calls.map(&:first)
  end

  def test_malformed_env_var_duration_is_parse_error
    # evaluate_details reports an ENV_VAR that does not parse as its type as
    # ERROR / TYPE_MISMATCH; on a duration config that is a malformed value.
    env_error = Details.new(value: nil, reason: Details::REASON_ERROR,
                            error_code: Details::ERROR_TYPE_MISMATCH, error_message: 'bad env')
    details, client = read(env_error)
    assert_equal 'PT0S', details.value
    assert_equal ErrorCode::PARSE_ERROR, details.error_code
    assert_equal [:evaluate_details], client.calls.map(&:first)
  end

  def test_structured_seconds_nanos_duration_is_type_mismatch
    details, = read(static({ 'seconds' => 90, 'nanos' => 0 }))
    assert_equal 'PT0S', details.value
    assert_equal Reason::ERROR, details.reason
    assert_equal ErrorCode::TYPE_MISMATCH, details.error_code
  end

  def test_no_match_returns_default
    details, = read(Details.new(value: nil, reason: Details::REASON_DEFAULT, variant: 'default'))
    assert_equal 'PT0S', details.value
    assert_equal Reason::DEFAULT, details.reason
  end

  def test_provider_source_has_no_resolver_or_private_client_workaround
    source = File.read(File.expand_path('../lib/quonfig/openfeature/provider.rb', __dir__), encoding: 'UTF-8')
    refute_match(/send\(:build_context/, source)
    refute_match(/\.resolver\b/, source)
    refute_match(/raw_value/, source)
  end

  def test_gemspec_requires_quonfig_2_1
    spec = Gem::Specification.load(File.expand_path('../quonfig-openfeature.gemspec', __dir__))
    dep = spec.runtime_dependencies.find { |d| d.name == 'quonfig' }
    assert_equal Gem::Requirement.new('>= 2.1.0'), dep.requirement
  end
end
