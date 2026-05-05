# frozen_string_literal: true

require 'open_feature/sdk'

module Quonfig
  module OpenFeature
    # Maps native Quonfig SDK errors to OpenFeature ErrorCode constants.
    module Errors
      module_function

      ErrorCode = ::OpenFeature::SDK::Provider::ErrorCode

      # @param err [Exception, String, nil]
      # @return [String] one of the ErrorCode constants
      def to_error_code(err)
        return ErrorCode::GENERAL if err.nil?

        # Class-based mapping is the most reliable signal.
        return ErrorCode::FLAG_NOT_FOUND if defined?(::Quonfig::Errors::MissingDefaultError) && err.is_a?(::Quonfig::Errors::MissingDefaultError)

        return ErrorCode::TYPE_MISMATCH if defined?(::Quonfig::Errors::TypeMismatchError) && err.is_a?(::Quonfig::Errors::TypeMismatchError)

        if (defined?(::Quonfig::Errors::UninitializedError) && err.is_a?(::Quonfig::Errors::UninitializedError)) ||
           (defined?(::Quonfig::Errors::InitializationTimeoutError) && err.is_a?(::Quonfig::Errors::InitializationTimeoutError))
          return ErrorCode::PROVIDER_NOT_READY
        end

        # Fallback: inspect the message text for keywords, matching the Node provider.
        msg = (err.respond_to?(:message) ? err.message : err.to_s).to_s.downcase
        return ErrorCode::FLAG_NOT_FOUND if msg.include?('not found') ||
                                            msg.include?('no value found') ||
                                            msg.include?('value found for key')
        return ErrorCode::TYPE_MISMATCH if msg.include?('type mismatch') ||
                                           (msg.include?('expected ') && msg.include?('got '))
        return ErrorCode::PROVIDER_NOT_READY if msg.include?('not initialized') ||
                                                msg.include?('provider not ready') ||
                                                msg.include?("couldn't initialize") ||
                                                msg.include?('initialization timeout')

        ErrorCode::GENERAL
      end
    end
  end
end
