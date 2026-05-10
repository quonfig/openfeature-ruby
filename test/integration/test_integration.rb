# frozen_string_literal: true

# Integration tests: drive a real Quonfig::OpenFeature::Provider through the
# OpenFeature::SDK singleton — the user-facing path. Backed by the shared
# quonfig/integration-test-data fixtures.
require 'test_helper'

class TestIntegration < Minitest::Test
  EvalCtx = ::OpenFeature::SDK::EvaluationContext
  Reason  = ::OpenFeature::SDK::Provider::Reason

  def setup
    @provider = build_provider
    ::OpenFeature::SDK.set_provider_and_wait(@provider)
    @client = ::OpenFeature::SDK.build_client(domain: "qf-int-#{object_id}")
  end

  def teardown
    @provider&.shutdown
  end

  def test_resolves_boolean_flag_to_true
    # always.true is a feature_flag with a single ALWAYS_TRUE rule.
    assert_equal true,
                 @client.fetch_boolean_value(flag_key: 'always.true', default_value: false)
  end

  def test_resolves_string_config
    assert_equal 'hello.world',
                 @client.fetch_string_value(flag_key: 'brand.new.string', default_value: '')
  end

  def test_resolves_integer_config
    assert_equal 123,
                 @client.fetch_integer_value(flag_key: 'brand.new.int', default_value: 0)
  end

  def test_resolves_float_config
    assert_in_delta 123.99,
                    @client.fetch_float_value(flag_key: 'brand.new.double', default_value: 0.0), 1e-9
  end

  def test_resolves_string_list_as_object_array
    assert_equal %w[a b c],
                 @client.fetch_object_value(flag_key: 'my-string-list-key', default_value: [])
  end

  def test_resolves_json_object_via_object
    assert_equal({ 'key' => 'value' },
                 @client.fetch_object_value(flag_key: 'brand.new.json', default_value: {}))
  end

  def test_targeting_rule_pro_user_gets_true
    ctx = EvalCtx.new('user.plan' => 'pro')
    assert_equal true,
                 @client.fetch_boolean_value(flag_key: 'of.targeting', default_value: false,
                                             evaluation_context: ctx)
  end

  def test_targeting_rule_free_user_gets_false
    ctx = EvalCtx.new('user.plan' => 'free')
    assert_equal false,
                 @client.fetch_boolean_value(flag_key: 'of.targeting', default_value: true,
                                             evaluation_context: ctx)
  end

  def test_returns_default_for_missing_boolean
    assert_equal false,
                 @client.fetch_boolean_value(flag_key: 'does-not-exist', default_value: false)
  end

  def test_returns_default_string_for_missing_flag
    assert_equal 'fallback',
                 @client.fetch_string_value(flag_key: 'does-not-exist', default_value: 'fallback')
  end

  def test_client_escape_hatch_exposes_quonfig_client
    assert_kind_of ::Quonfig::Client, @provider.client
  end

  # ---- variant + flag_metadata (qfg-9dbl) ----------------------------

  def test_static_variant_and_flag_metadata
    details = @client.fetch_boolean_details(flag_key: 'always.true', default_value: false)
    assert_equal 'static', details.variant
    md = details.flag_metadata
    refute_nil md
    assert_kind_of String, md['config_id']
    assert_equal 'feature_flag', md['config_type']
    assert_equal 'Production', md['environment']
    refute md.key?('rule_index')
    refute md.key?('weighted_value_index')
  end

  def test_targeting_match_variant_and_flag_metadata
    ctx = EvalCtx.new('user.plan' => 'pro')
    details = @client.fetch_boolean_details(flag_key: 'of.targeting', default_value: false,
                                            evaluation_context: ctx)
    assert_equal 'targeting:0', details.variant
    md = details.flag_metadata
    assert_equal '18000000000000001', md['config_id']
    assert_equal 'config', md['config_type']
    assert_equal 0, md['rule_index']
    refute md.key?('weighted_value_index')
  end

  def test_split_variant_and_flag_metadata
    saw = nil
    %w[user-1 user-2 user-3 user-4 user-5 user-100 user-123].each do |uid|
      ctx = EvalCtx.new('user.id' => uid)
      d = @client.fetch_string_details(flag_key: 'of.weighted', default_value: 'fallback',
                                       evaluation_context: ctx)
      next unless d.reason == Reason::SPLIT

      saw = d
      break
    end
    refute_nil saw, 'expected at least one user.id to land on SPLIT'
    assert_match(/\Asplit:\d+\z/, saw.variant)
    md = saw.flag_metadata
    assert_equal '18000000000000002', md['config_id']
    assert_equal 'config', md['config_type']
    assert_equal saw.variant.split(':').last.to_i, md['weighted_value_index']
    assert_kind_of Integer, md['rule_index']
  end

  def test_error_flag_not_found_variant_and_error_message
    details = @client.fetch_boolean_details(flag_key: 'does-not-exist', default_value: false)
    assert_equal Reason::ERROR, details.reason
    assert_equal 'default', details.variant
    refute_nil details.error_message
    refute_empty details.error_message
  end
end
