# frozen_string_literal: true

# An sdk-ruby details result with error code PARSE_ERROR (a malformed stored
# value or ENV_VAR value, qfg-wg1n) passes straight through as the OpenFeature
# PARSE_ERROR, with no second read. Released sdk-ruby (<= 2.1.0) reports these
# as TYPE_MISMATCH; that path keeps the stored-valueType re-read (qfg-9xsl).
require 'test_helper'

class TestParseErrorPassthrough < Minitest::Test
  Provider  = Quonfig::OpenFeature::Provider
  Reason    = ::OpenFeature::SDK::Provider::Reason
  ErrorCode = ::OpenFeature::SDK::Provider::ErrorCode
  Details   = ::Quonfig::EvaluationDetails

  KEY = 'malformed.key'
  SDK_PARSE_ERROR = 'PARSE_ERROR'

  # A client double whose every details read reports PARSE_ERROR. It records
  # each read so a test can pin that the provider does not re-read.
  class ParseErrorClient
    Store = Struct.new(:config) do
      def get(_key)
        config
      end
    end

    attr_reader :calls, :store

    def initialize(value_type)
      @calls = []
      @store = Store.new({ 'key' => KEY, 'valueType' => value_type })
    end

    def method_missing(name, *args, **_kwargs)
      return super unless name.to_s.end_with?('_details')

      @calls << [name, *args]
      Details.new(value: nil, reason: Details::REASON_ERROR, error_code: SDK_PARSE_ERROR,
                  error_message: "value for #{KEY} cannot be parsed", variant: 'v1',
                  flag_metadata: { 'config_type' => 'config' })
    end

    def respond_to_missing?(name, include_private = false)
      name.to_s.end_with?('_details') || super
    end
  end

  def fetch(method, value_type, default)
    client = ParseErrorClient.new(value_type)
    provider = Provider.new(client: client)
    provider.init
    [provider.public_send(method, flag_key: KEY, default_value: default), client]
  end

  def assert_parse_error(resolution, default)
    assert_equal default, resolution.value
    assert_equal Reason::ERROR, resolution.reason
    assert_equal ErrorCode::PARSE_ERROR, resolution.error_code
    assert_equal "value for #{KEY} cannot be parsed", resolution.error_message
  end

  def test_integer_passes_parse_error_through_with_one_read
    resolution, client = fetch(:fetch_integer_value, 'int', 7)
    assert_parse_error(resolution, 7)
    assert_equal [[:get_int_details, KEY]], client.calls
  end

  def test_float_passes_parse_error_through_with_one_read
    resolution, client = fetch(:fetch_float_value, 'double', 1.5)
    assert_parse_error(resolution, 1.5)
    assert_equal [[:get_float_details, KEY]], client.calls
  end

  def test_number_passes_parse_error_through_without_float_fallback
    resolution, client = fetch(:fetch_number_value, 'int', 3)
    assert_parse_error(resolution, 3)
    assert_equal [[:get_int_details, KEY]], client.calls
  end

  def test_boolean_passes_parse_error_through_with_one_read
    resolution, client = fetch(:fetch_boolean_value, 'bool', false)
    assert_parse_error(resolution, false)
    assert_equal [[:get_bool_details, KEY]], client.calls
  end

  def test_string_passes_parse_error_through_with_one_read
    resolution, client = fetch(:fetch_string_value, 'string', 'dflt')
    assert_parse_error(resolution, 'dflt')
    assert_equal [[:get_string_details, KEY]], client.calls
  end

  def test_object_passes_parse_error_through_without_json_fallback
    resolution, client = fetch(:fetch_object_value, 'string_list', [])
    assert_parse_error(resolution, [])
    assert_equal [[:get_string_list_details, KEY]], client.calls
  end

  def test_duration_string_passes_parse_error_through
    resolution, client = fetch(:fetch_string_value, 'duration', 'PT0S')
    assert_parse_error(resolution, 'PT0S')
    assert_equal [[:evaluate_details, KEY]], client.calls
  end

  def test_passthrough_keeps_variant_and_flag_metadata
    resolution, = fetch(:fetch_integer_value, 'int', 7)
    assert_equal 'v1', resolution.variant
    assert_equal({ 'config_type' => 'config' }, resolution.flag_metadata)
  end
end
