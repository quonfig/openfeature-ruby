# frozen_string_literal: true

require 'open_feature/sdk'
require 'quonfig'

require 'quonfig/openfeature/context'
require 'quonfig/openfeature/errors'

module Quonfig
  module OpenFeature
    # OpenFeature provider that wraps the +quonfig+ Ruby SDK and implements the
    # OpenFeature server-side provider contract:
    #
    #   * +metadata+
    #   * +init(evaluation_context = nil)+
    #   * +shutdown+
    #   * +fetch_boolean_value(flag_key:, default_value:, evaluation_context:)+
    #   * +fetch_string_value(flag_key:, default_value:, evaluation_context:)+
    #   * +fetch_number_value(flag_key:, default_value:, evaluation_context:)+
    #   * +fetch_integer_value(flag_key:, default_value:, evaluation_context:)+
    #   * +fetch_float_value(flag_key:, default_value:, evaluation_context:)+
    #   * +fetch_object_value(flag_key:, default_value:, evaluation_context:)+
    #
    # Usage:
    #
    #   require 'quonfig/openfeature'
    #   require 'open_feature/sdk'
    #
    #   provider = Quonfig::OpenFeature::Provider.new(sdk_key: 'qf_sk_...')
    #   OpenFeature::SDK.set_provider_and_wait(provider)
    #
    #   client = OpenFeature::SDK.build_client
    #   client.fetch_boolean_value(flag_key: 'my-flag', default_value: false)
    class Provider
      NAME = 'quonfig'

      ResolutionDetails = ::OpenFeature::SDK::Provider::ResolutionDetails
      Reason            = ::OpenFeature::SDK::Provider::Reason
      ErrorCode         = ::OpenFeature::SDK::Provider::ErrorCode
      ProviderMetadata  = ::OpenFeature::SDK::Provider::ProviderMetadata

      attr_reader :metadata, :targeting_key_mapping

      # @param sdk_key [String, nil] SDK key for the live delivery service.
      # @param datadir [String, nil] path to a Quonfig workspace for offline mode.
      # @param environment [String, nil] which environment to evaluate.
      # @param targeting_key_mapping [String] dot-notation path the OpenFeature
      #   targeting_key is rewritten to (default "user.id").
      # @param client [Quonfig::Client, nil] inject a pre-built Quonfig client
      #   (primarily for tests). When supplied, the other +sdk_key+/+datadir+/etc.
      #   options are ignored.
      # @param quonfig_options [Hash] any other keyword arguments are forwarded
      #   verbatim to +Quonfig::Client.new+.
      def initialize(sdk_key: nil, datadir: nil, environment: nil,
                     targeting_key_mapping: Context::DEFAULT_TARGETING_KEY_MAPPING,
                     client: nil, **quonfig_options)
        @metadata = ProviderMetadata.new(name: NAME).freeze
        @targeting_key_mapping = targeting_key_mapping
        @client = client
        @quonfig_options = build_quonfig_options(
          sdk_key: sdk_key,
          datadir: datadir,
          environment: environment,
          extra: quonfig_options
        )
        @initialized = !@client.nil?
      end

      # Initialize the underlying Quonfig client. Called by
      # +OpenFeature::SDK.set_provider_and_wait+.
      def init(_evaluation_context = nil)
        return if @initialized

        @client = ::Quonfig::Client.new(@quonfig_options)
        @initialized = true
        nil
      end

      # Shut the provider down. Mirrors the OpenFeature InMemoryProvider
      # contract — silently no-ops if the client was never built.
      def shutdown
        client = @client
        @client = nil
        @initialized = false
        client&.stop
        nil
      end

      # Escape hatch: returns the underlying +Quonfig::Client+ for native-only
      # features (keys, raw config, durations, log levels). Returns +nil+ until
      # +init+ has run.
      def client
        @client
      end

      # ---- fetch_*_value -----------------------------------------------------

      def fetch_boolean_value(flag_key:, default_value:, evaluation_context: nil)
        evaluate(flag_key, default_value, evaluation_context) do |client, mapped_ctx|
          value = client.get_bool(flag_key, default: nil, context: mapped_ctx)
          if value.nil?
            ResolutionDetails.new(value: default_value, reason: Reason::ERROR,
                                  error_code: ErrorCode::FLAG_NOT_FOUND,
                                  error_message: "flag not found: #{flag_key}")
          else
            ResolutionDetails.new(value: value, reason: Reason::TARGETING_MATCH)
          end
        end
      end

      def fetch_string_value(flag_key:, default_value:, evaluation_context: nil)
        evaluate(flag_key, default_value, evaluation_context) do |client, mapped_ctx|
          value = client.get_string(flag_key, default: nil, context: mapped_ctx)
          if value.nil?
            ResolutionDetails.new(value: default_value, reason: Reason::ERROR,
                                  error_code: ErrorCode::FLAG_NOT_FOUND,
                                  error_message: "flag not found: #{flag_key}")
          else
            ResolutionDetails.new(value: value, reason: Reason::TARGETING_MATCH)
          end
        end
      end

      def fetch_number_value(flag_key:, default_value:, evaluation_context: nil)
        # OpenFeature's "number" is Ruby Numeric (Integer or Float). Try integer
        # first, fall back to float so we transparently handle both Quonfig
        # int and double configs.
        evaluate(flag_key, default_value, evaluation_context) do |client, mapped_ctx|
          value = nil
          begin
            value = client.get_int(flag_key, default: nil, context: mapped_ctx)
          rescue ::Quonfig::Errors::TypeMismatchError
            value = client.get_float(flag_key, default: nil, context: mapped_ctx)
          end

          if value.nil?
            ResolutionDetails.new(value: default_value, reason: Reason::ERROR,
                                  error_code: ErrorCode::FLAG_NOT_FOUND,
                                  error_message: "flag not found: #{flag_key}")
          else
            ResolutionDetails.new(value: value, reason: Reason::TARGETING_MATCH)
          end
        end
      end

      def fetch_integer_value(flag_key:, default_value:, evaluation_context: nil)
        evaluate(flag_key, default_value, evaluation_context) do |client, mapped_ctx|
          value = client.get_int(flag_key, default: nil, context: mapped_ctx)
          if value.nil?
            ResolutionDetails.new(value: default_value, reason: Reason::ERROR,
                                  error_code: ErrorCode::FLAG_NOT_FOUND,
                                  error_message: "flag not found: #{flag_key}")
          else
            ResolutionDetails.new(value: value, reason: Reason::TARGETING_MATCH)
          end
        end
      end

      def fetch_float_value(flag_key:, default_value:, evaluation_context: nil)
        evaluate(flag_key, default_value, evaluation_context) do |client, mapped_ctx|
          value = client.get_float(flag_key, default: nil, context: mapped_ctx)
          if value.nil?
            ResolutionDetails.new(value: default_value, reason: Reason::ERROR,
                                  error_code: ErrorCode::FLAG_NOT_FOUND,
                                  error_message: "flag not found: #{flag_key}")
          else
            ResolutionDetails.new(value: value, reason: Reason::TARGETING_MATCH)
          end
        end
      end

      # Object resolution tries +get_string_list+ first (so Quonfig
      # +string_list+ configs surface as native arrays), then falls back to
      # +get_json+ for any other JSON-shaped config.
      def fetch_object_value(flag_key:, default_value:, evaluation_context: nil)
        evaluate(flag_key, default_value, evaluation_context) do |client, mapped_ctx|
          value = nil
          begin
            value = client.get_string_list(flag_key, default: nil, context: mapped_ctx)
          rescue ::Quonfig::Errors::TypeMismatchError
            value = nil
          end
          if value.nil?
            value = client.get_json(flag_key, default: nil, context: mapped_ctx)
          end

          if value.nil?
            ResolutionDetails.new(value: default_value, reason: Reason::ERROR,
                                  error_code: ErrorCode::FLAG_NOT_FOUND,
                                  error_message: "flag not found: #{flag_key}")
          else
            ResolutionDetails.new(value: value, reason: Reason::TARGETING_MATCH)
          end
        end
      end

      private

      def evaluate(flag_key, default_value, evaluation_context)
        client = @client
        if client.nil?
          return ResolutionDetails.new(
            value: default_value,
            reason: Reason::ERROR,
            error_code: ErrorCode::PROVIDER_NOT_READY,
            error_message: 'Quonfig provider has not been initialized'
          )
        end

        mapped_ctx = Context.map_context(evaluation_context, @targeting_key_mapping)
        yield(client, mapped_ctx)
      rescue ::Quonfig::Errors::MissingDefaultError => e
        ResolutionDetails.new(value: default_value, reason: Reason::ERROR,
                              error_code: ErrorCode::FLAG_NOT_FOUND,
                              error_message: e.message)
      rescue ::Quonfig::Errors::TypeMismatchError => e
        ResolutionDetails.new(value: default_value, reason: Reason::ERROR,
                              error_code: ErrorCode::TYPE_MISMATCH,
                              error_message: e.message)
      rescue ::Quonfig::Errors::UninitializedError, ::Quonfig::Errors::InitializationTimeoutError => e
        ResolutionDetails.new(value: default_value, reason: Reason::ERROR,
                              error_code: ErrorCode::PROVIDER_NOT_READY,
                              error_message: e.message)
      rescue StandardError => e
        ResolutionDetails.new(value: default_value, reason: Reason::ERROR,
                              error_code: Errors.to_error_code(e),
                              error_message: e.message)
      end

      def build_quonfig_options(sdk_key:, datadir:, environment:, extra:)
        opts = {}
        opts[:sdk_key] = sdk_key unless sdk_key.nil?
        opts[:datadir] = datadir unless datadir.nil?
        opts[:environment] = environment unless environment.nil?
        opts.merge(extra)
      end
    end
  end
end
