# frozen_string_literal: true

require 'test_helper'

class TestProvider < Minitest::Test
  Provider  = Quonfig::OpenFeature::Provider
  Reason    = ::OpenFeature::SDK::Provider::Reason
  ErrorCode = ::OpenFeature::SDK::Provider::ErrorCode

  def test_metadata_name_is_quonfig
    p = build_provider
    assert_equal 'quonfig', p.metadata.name
  end

  def test_default_targeting_key_mapping
    p = build_provider
    assert_equal 'user.id', p.targeting_key_mapping
  end

  def test_custom_targeting_key_mapping
    p = build_provider(targeting_key_mapping: 'account.id')
    assert_equal 'account.id', p.targeting_key_mapping
  end

  # ---- not-initialized path -------------------------------------------------

  def test_fetch_boolean_returns_provider_not_ready_before_init
    p = build_provider
    assert_nil p.client
    details = p.fetch_boolean_value(flag_key: 'my-flag', default_value: false)
    assert_equal false, details.value
    assert_equal Reason::ERROR, details.reason
    assert_equal ErrorCode::PROVIDER_NOT_READY, details.error_code
  end

  def test_fetch_string_returns_provider_not_ready_before_init
    p = build_provider
    details = p.fetch_string_value(flag_key: 'my-string', default_value: 'fallback')
    assert_equal 'fallback', details.value
    assert_equal ErrorCode::PROVIDER_NOT_READY, details.error_code
  end

  def test_fetch_object_returns_provider_not_ready_before_init
    p = build_provider
    details = p.fetch_object_value(flag_key: 'my-list', default_value: [])
    assert_equal [], details.value
    assert_equal ErrorCode::PROVIDER_NOT_READY, details.error_code
  end

  # ---- shutdown -------------------------------------------------------------

  def test_shutdown_clears_client_and_subsequent_calls_return_provider_not_ready
    p = init_provider
    refute_nil p.client
    p.shutdown
    assert_nil p.client
    details = p.fetch_boolean_value(flag_key: 'my-flag', default_value: false)
    assert_equal ErrorCode::PROVIDER_NOT_READY, details.error_code
  end

  # ---- client escape hatch --------------------------------------------------

  def test_client_returns_underlying_quonfig_client_after_init
    p = init_provider
    assert_kind_of ::Quonfig::Client, p.client
  end

  def test_init_is_idempotent
    p = init_provider
    first = p.client
    p.init
    assert_same first, p.client
  end

  # ---- forwards extra kwargs to Quonfig::Client -----------------------------

  def test_forwards_extra_quonfig_options
    # global_context flows into Quonfig::Client
    p = init_provider(global_context: { 'org' => { 'tier' => 'enterprise' } })
    assert_equal({ 'org' => { 'tier' => 'enterprise' } }, p.client.options.global_context)
  end
end
