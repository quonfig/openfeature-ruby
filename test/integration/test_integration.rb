# frozen_string_literal: true

# Integration tests: drive a real Quonfig::OpenFeature::Provider through the
# OpenFeature::SDK singleton — the user-facing path.
require 'test_helper'

class TestIntegration < Minitest::Test
  EvalCtx = ::OpenFeature::SDK::EvaluationContext

  def setup
    @provider = build_provider
    ::OpenFeature::SDK.set_provider_and_wait(@provider)
    @client = ::OpenFeature::SDK.build_client(domain: "qf-int-#{object_id}")
  end

  def teardown
    @provider&.shutdown
  end

  def test_resolves_boolean_flag_to_true
    assert_equal true,
                 @client.fetch_boolean_value(flag_key: 'my-flag', default_value: false)
  end

  def test_resolves_string_config
    assert_equal 'hello',
                 @client.fetch_string_value(flag_key: 'my-string', default_value: '')
  end

  def test_resolves_integer_config
    assert_equal 42,
                 @client.fetch_integer_value(flag_key: 'my-int', default_value: 0)
  end

  def test_resolves_float_config
    assert_in_delta 3.14,
                    @client.fetch_float_value(flag_key: 'my-float', default_value: 0.0), 1e-9
  end

  def test_resolves_string_list_as_object_array
    assert_equal %w[a b c],
                 @client.fetch_object_value(flag_key: 'my-list', default_value: [])
  end

  def test_resolves_json_object_via_object
    assert_equal({ 'foo' => 'bar' },
                 @client.fetch_object_value(flag_key: 'my-json', default_value: {}))
  end

  def test_targeting_rule_pro_user_gets_true
    ctx = EvalCtx.new('user.plan' => 'pro')
    assert_equal true,
                 @client.fetch_boolean_value(flag_key: 'plan-flag', default_value: false,
                                             evaluation_context: ctx)
  end

  def test_targeting_rule_free_user_gets_false
    ctx = EvalCtx.new('user.plan' => 'free')
    assert_equal false,
                 @client.fetch_boolean_value(flag_key: 'plan-flag', default_value: true,
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
end
