# frozen_string_literal: true

# Typed-getter contract (qfg-zvyy), driven through the real provider and the
# OpenFeature client against the integration-test-data +getter.contract.*+
# fixtures. No mocks: this pins what provider users inherit from +quonfig+
# (sdk-ruby) 2.0.0.
#
# The rule: a flag read with the method for another type returns the caller's
# default with reason ERROR and error code TYPE_MISMATCH. Strings are never
# coerced (a stored "false" is not a bool, "3" is not a number). Numbers convert
# only when exact: an int config reads as a float, and a double config reads as
# an integer only when it is whole and within +/-(2^53-1).
require 'test_helper'

class TestTypedGetterContract < Minitest::Test
  Reason    = ::OpenFeature::SDK::Provider::Reason
  ErrorCode = ::OpenFeature::SDK::Provider::ErrorCode

  def setup
    @provider = build_provider
    ::OpenFeature::SDK.set_provider_and_wait(@provider)
    @client = ::OpenFeature::SDK.build_client(domain: "qf-contract-#{object_id}")
  end

  def teardown
    @provider&.shutdown
  end

  # ---- helpers -------------------------------------------------------------

  def fetch(type, key, default)
    @client.public_send(:"fetch_#{type}_details", flag_key: key, default_value: default)
  end

  def assert_error(details, default, error_code)
    assert_equal default, details.value
    assert_equal default.class, details.value.class
    assert_equal Reason::ERROR, details.reason
    assert_equal error_code, details.error_code
  end

  def assert_type_mismatch(details, default)
    assert_error(details, default, ErrorCode::TYPE_MISMATCH)
  end

  def assert_resolves(details, expected)
    assert_equal expected, details.value
    assert_equal expected.class, details.value.class
    assert_equal Reason::STATIC, details.reason
    assert_nil details.error_code
  end

  def with_env(name, value)
    old = ENV.fetch(name, nil)
    value.nil? ? ENV.delete(name) : ENV[name] = value
    yield
  ensure
    old.nil? ? ENV.delete(name) : ENV[name] = old
  end

  # ---- wrong type -> default + TYPE_MISMATCH --------------------------------

  def test_boolean_on_stored_string_false_returns_default
    assert_type_mismatch(fetch(:boolean, 'getter.contract.string.false', true), true)
  end

  def test_boolean_on_stored_string_true_returns_default
    assert_type_mismatch(fetch(:boolean, 'getter.contract.string.true', false), false)
  end

  def test_boolean_on_stored_int_returns_default
    assert_type_mismatch(fetch(:boolean, 'getter.contract.int', true), true)
  end

  def test_integer_on_stored_string_number_returns_default
    assert_type_mismatch(fetch(:integer, 'getter.contract.string.number', 7), 7)
  end

  def test_float_on_stored_string_number_returns_default
    assert_type_mismatch(fetch(:float, 'getter.contract.string.number', 7.5), 7.5)
  end

  def test_number_on_stored_string_number_returns_default
    assert_type_mismatch(fetch(:number, 'getter.contract.string.number', 7), 7)
  end

  def test_string_on_stored_int_returns_default_not_its_text
    assert_type_mismatch(fetch(:string, 'getter.contract.int', 'fallback'), 'fallback')
  end

  def test_string_on_stored_bool_returns_default
    assert_type_mismatch(fetch(:string, 'getter.contract.bool', 'fallback'), 'fallback')
  end

  def test_integer_on_fractional_double_returns_default_not_truncated
    assert_type_mismatch(fetch(:integer, 'getter.contract.double', 7), 7)
  end

  def test_integer_on_unsafe_double_returns_default
    assert_type_mismatch(fetch(:integer, 'getter.contract.double.unsafe', 7), 7)
  end

  def test_integer_on_huge_double_returns_default
    assert_type_mismatch(fetch(:integer, 'getter.contract.double.huge', 7), 7)
  end

  def test_float_on_duration_returns_default
    # A duration reads only as its ISO text (fetch_string_value); for integer
    # milliseconds use provider.client.get_duration.
    assert_type_mismatch(fetch(:float, 'getter.contract.duration', 5.0), 5.0)
  end

  def test_number_on_duration_returns_default
    assert_type_mismatch(fetch(:number, 'getter.contract.duration', 5), 5)
  end

  def test_object_on_stored_string_returns_default
    assert_type_mismatch(fetch(:object, 'getter.contract.string', { 'd' => true }), { 'd' => true })
  end

  def test_object_on_stored_bool_returns_default
    assert_type_mismatch(fetch(:object, 'getter.contract.bool', { 'd' => true }), { 'd' => true })
  end

  # ---- matching and exactly convertible types resolve ----------------------

  def test_boolean_on_bool_config
    assert_resolves(fetch(:boolean, 'getter.contract.bool', false), true)
  end

  def test_string_on_string_config
    assert_resolves(fetch(:string, 'getter.contract.string', ''), 'fast')
  end

  def test_integer_on_int_config
    assert_resolves(fetch(:integer, 'getter.contract.int', 0), 30)
  end

  def test_float_on_int_config_converts
    assert_resolves(fetch(:float, 'getter.contract.int', 0.0), 30.0)
  end

  def test_float_on_double_config
    assert_resolves(fetch(:float, 'getter.contract.double', 0.0), 3.9)
  end

  def test_integer_on_whole_double_converts
    assert_resolves(fetch(:integer, 'getter.contract.double.whole', 0), 3)
  end

  def test_number_on_int_config
    assert_resolves(fetch(:number, 'getter.contract.int', 0), 30)
  end

  def test_number_on_fractional_double_config
    assert_resolves(fetch(:number, 'getter.contract.double', 0), 3.9)
  end

  def test_object_on_json_config
    assert_resolves(fetch(:object, 'getter.contract.json', {}), { 'a' => 1 })
  end

  def test_object_on_string_list_config
    assert_resolves(fetch(:object, 'getter.contract.string_list', []), %w[a b])
  end

  # ---- malformed values and resolution errors return the default -----------
  #
  # A malformed value, stored or ENV_VAR, of the requested type (or one the
  # method converts exactly) is PARSE_ERROR (qfg-9xsl). An unset ENV_VAR is a
  # resolution error: GENERAL.

  def assert_parse_error(details, default)
    assert_error(details, default, ErrorCode::PARSE_ERROR)
  end

  def test_float_on_malformed_double_returns_default
    assert_parse_error(fetch(:float, 'getter.contract.double.malformed', 1.5), 1.5)
  end

  def test_integer_on_malformed_int_returns_default
    assert_parse_error(fetch(:integer, 'getter.contract.int.malformed', 12), 12)
  end

  def test_float_on_malformed_int_returns_default
    assert_parse_error(fetch(:float, 'getter.contract.int.malformed', 1.5), 1.5)
  end

  def test_integer_on_malformed_double_returns_default
    assert_parse_error(fetch(:integer, 'getter.contract.double.malformed', 12), 12)
  end

  def test_number_on_malformed_int_returns_default
    assert_parse_error(fetch(:number, 'getter.contract.int.malformed', 12), 12)
  end

  def test_integer_on_malformed_env_var_returns_default
    with_env('QUONFIG_ITD_GETTER_INT', 'twelve') do
      assert_parse_error(fetch(:integer, 'getter.contract.provided.int.malformed', 4), 4)
    end
  end

  def test_float_on_malformed_env_var_returns_default
    with_env('QUONFIG_ITD_GETTER_DOUBLE', 'abc') do
      assert_parse_error(fetch(:float, 'getter.contract.provided.double.malformed', 2.5), 2.5)
    end
  end

  def test_string_on_malformed_duration_returns_default
    assert_parse_error(fetch(:string, 'test.duration.malformed.30s', 'PT0S'), 'PT0S')
  end

  def test_boolean_on_malformed_int_is_type_mismatch_not_parse_error
    # The wrong-type read wins: a bool read of an int config is the caller's
    # problem whatever the stored value looks like.
    assert_type_mismatch(fetch(:boolean, 'getter.contract.int.malformed', true), true)
  end

  def test_boolean_on_unset_env_var_returns_default
    with_env('QUONFIG_ITD_GETTER_UNSET_BOOL', nil) do
      assert_error(fetch(:boolean, 'getter.contract.provided.bool.missing', true), true, ErrorCode::GENERAL)
    end
  end

  # ---- duration: ISO text through fetch_string_value (qfg-177f) ------------

  def test_string_on_duration_returns_stored_iso_text
    assert_resolves(fetch(:string, 'getter.contract.duration', 'PT0S'), 'PT30S')
  end

  def test_string_on_env_var_duration_returns_env_text
    with_env('QUONFIG_ITD_DURATION_PT1_5S', 'PT1.5S') do
      assert_resolves(fetch(:string, 'provided.duration.PT1.5S', 'PT0S'), 'PT1.5S')
    end
  end

  def test_string_on_malformed_env_var_duration_is_parse_error
    with_env('QUONFIG_ITD_DURATION_PT1_5S', '30s') do
      assert_parse_error(fetch(:string, 'provided.duration.PT1.5S', 'PT0S'), 'PT0S')
    end
  end

  def test_string_on_weighted_duration_returns_variant_iso_text
    details = fetch(:string, 'weighted.variant.duration', 'PT0S')
    assert_equal 'PT90S', details.value
    assert_equal Reason::SPLIT, details.reason
    assert_nil details.error_code
  end

  def test_duration_reads_through_native_client
    # sdk-ruby's get_duration returns integer milliseconds.
    assert_equal 30_000, @provider.client.get_duration('getter.contract.duration', default: 0)
  end
end
