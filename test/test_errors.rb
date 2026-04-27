# frozen_string_literal: true

require 'test_helper'

class TestErrors < Minitest::Test
  Errors    = Quonfig::OpenFeature::Errors
  ErrorCode = ::OpenFeature::SDK::Provider::ErrorCode

  def test_missing_default_error_maps_to_flag_not_found
    err = ::Quonfig::Errors::MissingDefaultError.new('my-flag')
    assert_equal ErrorCode::FLAG_NOT_FOUND, Errors.to_error_code(err)
  end

  def test_type_mismatch_error_maps_to_type_mismatch
    err = ::Quonfig::Errors::TypeMismatchError.new('my-flag', 'String', 42)
    assert_equal ErrorCode::TYPE_MISMATCH, Errors.to_error_code(err)
  end

  def test_uninitialized_error_maps_to_provider_not_ready
    err = ::Quonfig::Errors::UninitializedError.new
    assert_equal ErrorCode::PROVIDER_NOT_READY, Errors.to_error_code(err)
  end

  def test_initialization_timeout_error_maps_to_provider_not_ready
    err = ::Quonfig::Errors::InitializationTimeoutError.new(10, 'my-flag')
    assert_equal ErrorCode::PROVIDER_NOT_READY, Errors.to_error_code(err)
  end

  def test_unknown_runtime_error_maps_to_general
    err = StandardError.new('something else exploded')
    assert_equal ErrorCode::GENERAL, Errors.to_error_code(err)
  end

  def test_message_keyword_fallback_for_not_found
    err = StandardError.new('No value found for key foo')
    assert_equal ErrorCode::FLAG_NOT_FOUND, Errors.to_error_code(err)
  end

  def test_message_keyword_fallback_for_provider_not_ready
    err = StandardError.new('Quonfig is not initialized yet')
    assert_equal ErrorCode::PROVIDER_NOT_READY, Errors.to_error_code(err)
  end

  def test_nil_input_maps_to_general
    assert_equal ErrorCode::GENERAL, Errors.to_error_code(nil)
  end
end
