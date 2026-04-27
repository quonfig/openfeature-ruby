# frozen_string_literal: true

# OpenFeature spec conformance tests — real provider, datadir fixture, no mocks.
# Tests call provider fetch_*_value methods directly after manual init,
# validating the OF spec contract without depending on the SDK singleton.
# Backed by shared quonfig/integration-test-data fixtures (always.true,
# of.targeting, of.weighted, brand.new.*, my-string-list-key).
# References: https://openfeature.dev/specification/sections/providers
require 'test_helper'

class TestSpec < Minitest::Test
  Provider  = Quonfig::OpenFeature::Provider
  Reason    = ::OpenFeature::SDK::Provider::Reason
  ErrorCode = ::OpenFeature::SDK::Provider::ErrorCode
  EvalCtx   = ::OpenFeature::SDK::EvaluationContext

  def setup
    @provider = init_provider
  end

  def teardown
    @provider&.shutdown
  end

  # -------------------------------------------------------------------------
  # 2.3 — Provider lifecycle
  # -------------------------------------------------------------------------

  def test_2_3_init_resolves_for_valid_datadir
    p = build_provider
    p.init
    refute_nil p.client
  ensure
    p&.shutdown
  end

  def test_2_3_init_raises_for_invalid_datadir
    p = build_provider(datadir: '/does/not/exist')
    assert_raises(StandardError) { p.init }
  end

  def test_2_3_shutdown_is_safe_to_call
    p = init_provider
    p.shutdown
    assert_nil p.client
  end

  # -------------------------------------------------------------------------
  # 2.2 — Error codes
  # -------------------------------------------------------------------------

  def test_2_2_2_flag_not_found_for_missing_boolean
    details = @provider.fetch_boolean_value(flag_key: 'does-not-exist', default_value: false)
    assert_equal ErrorCode::FLAG_NOT_FOUND, details.error_code
  end

  def test_2_2_2_flag_not_found_for_missing_string
    details = @provider.fetch_string_value(flag_key: 'does-not-exist', default_value: 'fallback')
    assert_equal ErrorCode::FLAG_NOT_FOUND, details.error_code
  end

  def test_2_2_2_flag_not_found_for_missing_number
    details = @provider.fetch_number_value(flag_key: 'does-not-exist', default_value: 0)
    assert_equal ErrorCode::FLAG_NOT_FOUND, details.error_code
  end

  def test_2_2_2_flag_not_found_for_missing_integer
    details = @provider.fetch_integer_value(flag_key: 'does-not-exist', default_value: 0)
    assert_equal ErrorCode::FLAG_NOT_FOUND, details.error_code
  end

  def test_2_2_2_flag_not_found_for_missing_float
    details = @provider.fetch_float_value(flag_key: 'does-not-exist', default_value: 0.0)
    assert_equal ErrorCode::FLAG_NOT_FOUND, details.error_code
  end

  def test_2_2_2_flag_not_found_for_missing_object
    details = @provider.fetch_object_value(flag_key: 'does-not-exist', default_value: {})
    assert_equal ErrorCode::FLAG_NOT_FOUND, details.error_code
  end

  # -------------------------------------------------------------------------
  # 2.1 — Default value returned on error
  # -------------------------------------------------------------------------

  def test_2_1_default_value_returned_for_missing_boolean
    assert_equal true,
                 @provider.fetch_boolean_value(flag_key: 'does-not-exist', default_value: true).value
    assert_equal false,
                 @provider.fetch_boolean_value(flag_key: 'does-not-exist', default_value: false).value
  end

  def test_2_1_default_value_returned_for_missing_string
    details = @provider.fetch_string_value(flag_key: 'does-not-exist', default_value: 'sentinel')
    assert_equal 'sentinel', details.value
  end

  def test_2_1_default_value_returned_for_missing_number
    details = @provider.fetch_number_value(flag_key: 'does-not-exist', default_value: 42)
    assert_equal 42, details.value
  end

  def test_2_1_default_value_returned_for_missing_object
    default = { 'key' => 'val' }
    details = @provider.fetch_object_value(flag_key: 'does-not-exist', default_value: default)
    assert_equal default, details.value
  end

  # -------------------------------------------------------------------------
  # 2.7 — Resolution reasons
  # -------------------------------------------------------------------------

  def test_2_7_static_reason_for_always_true_flag
    # always.true has only ALWAYS_TRUE criteria => STATIC.
    details = @provider.fetch_boolean_value(flag_key: 'always.true', default_value: false)
    assert_equal Reason::STATIC, details.reason
    assert_equal true, details.value
  end

  def test_2_7_static_reason_for_brand_new_string
    details = @provider.fetch_string_value(flag_key: 'brand.new.string', default_value: '')
    assert_equal Reason::STATIC, details.reason
  end

  def test_2_7_targeting_match_reason_for_pro_user
    # of.targeting has property-match rules => TARGETING_MATCH.
    ctx = EvalCtx.new('user.plan' => 'pro')
    details = @provider.fetch_boolean_value(flag_key: 'of.targeting', default_value: false,
                                            evaluation_context: ctx)
    assert_equal Reason::TARGETING_MATCH, details.reason
    assert_equal true, details.value
  end

  def test_2_7_targeting_match_reason_when_falling_through_to_always_true
    # Even when the ALWAYS_TRUE fallback wins, the *config* has targeting
    # rules, so the reason is still TARGETING_MATCH.
    ctx = EvalCtx.new('user.plan' => 'free')
    details = @provider.fetch_boolean_value(flag_key: 'of.targeting', default_value: true,
                                            evaluation_context: ctx)
    assert_equal Reason::TARGETING_MATCH, details.reason
    assert_equal false, details.value
  end

  def test_2_7_split_reason_for_weighted_value
    # of.weighted picks via weighted_values keyed off user.id.
    ctx = EvalCtx.new(targeting_key: '92a202f2')
    details = @provider.fetch_string_value(flag_key: 'of.weighted', default_value: 'sentinel',
                                           evaluation_context: ctx)
    assert_equal Reason::SPLIT, details.reason
    assert_includes %w[variant-a variant-b], details.value
  end

  def test_2_7_error_reason_for_missing_flag
    details = @provider.fetch_boolean_value(flag_key: 'does-not-exist', default_value: false)
    assert_equal Reason::ERROR, details.reason
  end

  # -------------------------------------------------------------------------
  # 2.4 — All four (well, six) evaluation types resolve correctly
  # -------------------------------------------------------------------------

  def test_2_4_resolves_boolean_flag
    assert_equal true,
                 @provider.fetch_boolean_value(flag_key: 'always.true', default_value: false).value
  end

  def test_2_4_resolves_string_config
    assert_equal 'hello.world',
                 @provider.fetch_string_value(flag_key: 'brand.new.string', default_value: '').value
  end

  def test_2_4_resolves_integer_config
    assert_equal 123,
                 @provider.fetch_integer_value(flag_key: 'brand.new.int', default_value: 0).value
  end

  def test_2_4_resolves_float_config
    assert_in_delta 123.99,
                    @provider.fetch_float_value(flag_key: 'brand.new.double', default_value: 0.0).value, 1e-9
  end

  def test_2_4_resolves_number_config_via_int
    assert_equal 123,
                 @provider.fetch_number_value(flag_key: 'brand.new.int', default_value: 0).value
  end

  def test_2_4_resolves_string_list_via_object
    assert_equal %w[a b c],
                 @provider.fetch_object_value(flag_key: 'my-string-list-key', default_value: []).value
  end

  def test_2_4_resolves_json_object_via_object
    assert_equal({ 'key' => 'value' },
                 @provider.fetch_object_value(flag_key: 'brand.new.json', default_value: {}).value)
  end

  # -------------------------------------------------------------------------
  # 3.2 — Evaluation context propagation
  # -------------------------------------------------------------------------

  def test_3_2_dot_notation_routes_pro_to_true
    ctx = EvalCtx.new('user.plan' => 'pro')
    details = @provider.fetch_boolean_value(flag_key: 'of.targeting', default_value: false,
                                            evaluation_context: ctx)
    assert_equal true, details.value
  end

  def test_3_2_dot_notation_routes_free_to_false
    ctx = EvalCtx.new('user.plan' => 'free')
    details = @provider.fetch_boolean_value(flag_key: 'of.targeting', default_value: true,
                                            evaluation_context: ctx)
    assert_equal false, details.value
  end

  def test_3_2_targeting_key_does_not_break_evaluation
    ctx = EvalCtx.new(targeting_key: 'user-123', 'user.plan' => 'pro')
    details = @provider.fetch_boolean_value(flag_key: 'of.targeting', default_value: false,
                                            evaluation_context: ctx)
    assert_equal true, details.value
  end

  # -------------------------------------------------------------------------
  # 2.8 — Provider metadata
  # -------------------------------------------------------------------------

  def test_2_8_metadata_has_non_empty_name
    assert_kind_of String, @provider.metadata.name
    refute @provider.metadata.name.empty?
  end
end
