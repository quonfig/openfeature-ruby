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
    #
    # Provider status follows the SDK's +on_init_failure+ mode (init-failure
    # design B.5). Pass +on_init_failure:+ and +init_timeout_ms:+ through
    # +Provider.new+; they are forwarded to +Quonfig::Client.new+.
    #
    #   * +:fail+ (default): +init+ raises, so the provider is ERROR. sdk-ruby
    #     returns no client, so nothing retries; restart the process.
    #   * +:wait+: +init+ blocks until config loads (NOT_READY), then READY.
    #   * +:continue+: +init+ resolves; with no config yet the provider emits
    #     PROVIDER_ERROR (ERROR, evaluations return the default with
    #     PROVIDER_NOT_READY), then PROVIDER_READY when the client heals.
    class Provider
      include ::OpenFeature::SDK::Provider::EventEmitter

      NAME = 'quonfig'

      # How long the heal watcher waits for OpenFeature to record the READY it
      # dispatches when +init+ returns, before it reports PROVIDER_ERROR.
      INIT_DISPATCH_WAIT_S = 5

      ResolutionDetails = ::OpenFeature::SDK::Provider::ResolutionDetails
      Reason            = ::OpenFeature::SDK::Provider::Reason
      ErrorCode         = ::OpenFeature::SDK::Provider::ErrorCode
      ProviderMetadata  = ::OpenFeature::SDK::Provider::ProviderMetadata

      # The stored +valueType+s each fetch method can read: its own type plus
      # the ones it converts exactly (int <-> double, duration -> ISO string).
      # A TYPE_MISMATCH on a config of one of these types means the value
      # did not parse, so it is reported as PARSE_ERROR (qfg-9xsl).
      READABLE_VALUE_TYPES = {
        boolean: %w[bool],
        string: %w[string log_level duration],
        integer: %w[int double],
        float: %w[double int],
        number: %w[int double],
        object: %w[string_list json]
      }.freeze

      # The native details getter that reads each stored +valueType+ as itself.
      NATIVE_DETAILS_GETTER = {
        'bool' => :get_bool_details,
        'string' => :get_string_details,
        'log_level' => :get_string_details,
        'duration' => :get_duration_details,
        'int' => :get_int_details,
        'double' => :get_float_details,
        'string_list' => :get_string_list_details,
        'json' => :get_json_details
      }.freeze
      # sdk-ruby's error code for a value that did not parse (a malformed
      # stored value or ENV_VAR value, qfg-wg1n). Matched as a string: the
      # quonfig floor (2.1.0) defines no constant for it and never emits it,
      # so with that SDK the TYPE_MISMATCH re-read in #malformed? still applies.
      SDK_PARSE_ERROR = 'PARSE_ERROR'
      private_constant :READABLE_VALUE_TYPES, :NATIVE_DETAILS_GETTER, :SDK_PARSE_ERROR

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
        @initialized = false
      end

      # Initialize the underlying Quonfig client. Called by
      # +OpenFeature::SDK.set_provider_and_wait+. Raises under
      # +on_init_failure: :fail+ when no config loads, which OpenFeature
      # records as ERROR.
      def init(_evaluation_context = nil)
        return if @initialized

        @client ||= ::Quonfig::Client.new(@quonfig_options)
        @initialized = true
        watch_for_heal(@client) unless client_ready?(@client)
        nil
      end

      # Shut the provider down. Mirrors the OpenFeature InMemoryProvider
      # contract — silently no-ops if the client was never built.
      def shutdown
        client = @client
        @client = nil
        @initialized = false
        client&.stop
        @heal_thread&.join(1)
        @heal_thread = nil
        nil
      end

      # Escape hatch: returns the underlying +Quonfig::Client+ for native-only
      # features (keys, raw config, durations, log levels). Returns +nil+ until
      # +init+ has run.
      attr_reader :client

      # ---- fetch_*_value -----------------------------------------------------

      def fetch_boolean_value(flag_key:, default_value:, evaluation_context: nil)
        evaluate(flag_key, default_value, evaluation_context) do |client, mapped_ctx|
          details = client.get_bool_details(flag_key, context: mapped_ctx)
          to_resolution(details, default_value, parse_error: malformed?(client, flag_key, mapped_ctx, :boolean, details))
        end
      end

      # A +duration+ config reads as its stored ISO 8601 text, unchanged
      # ("PT90S" stays "PT90S"): OpenFeature has no duration type (qfg-177f).
      def fetch_string_value(flag_key:, default_value:, evaluation_context: nil)
        evaluate(flag_key, default_value, evaluation_context) do |client, mapped_ctx|
          next duration_iso_resolution(client, flag_key, mapped_ctx, default_value) if stored_value_type(client, flag_key) == 'duration'

          details = client.get_string_details(flag_key, context: mapped_ctx)
          to_resolution(details, default_value, parse_error: malformed?(client, flag_key, mapped_ctx, :string, details))
        end
      end

      def fetch_number_value(flag_key:, default_value:, evaluation_context: nil)
        # OpenFeature's "number" is Ruby Numeric (Integer or Float). Try integer
        # first, fall back to float so we transparently handle both Quonfig
        # int and double configs.
        evaluate(flag_key, default_value, evaluation_context) do |client, mapped_ctx|
          details = client.get_int_details(flag_key, context: mapped_ctx)
          details = client.get_float_details(flag_key, context: mapped_ctx) if details.error_code == ::Quonfig::EvaluationDetails::ERROR_TYPE_MISMATCH
          to_resolution(details, default_value, parse_error: malformed?(client, flag_key, mapped_ctx, :number, details))
        end
      end

      def fetch_integer_value(flag_key:, default_value:, evaluation_context: nil)
        evaluate(flag_key, default_value, evaluation_context) do |client, mapped_ctx|
          details = client.get_int_details(flag_key, context: mapped_ctx)
          to_resolution(details, default_value, parse_error: malformed?(client, flag_key, mapped_ctx, :integer, details))
        end
      end

      def fetch_float_value(flag_key:, default_value:, evaluation_context: nil)
        evaluate(flag_key, default_value, evaluation_context) do |client, mapped_ctx|
          details = client.get_float_details(flag_key, context: mapped_ctx)
          to_resolution(details, default_value, parse_error: malformed?(client, flag_key, mapped_ctx, :float, details))
        end
      end

      # Object resolution tries +get_string_list_details+ first (so Quonfig
      # +string_list+ configs surface as native arrays), then falls back to
      # +get_json_details+ for any other JSON-shaped config.
      def fetch_object_value(flag_key:, default_value:, evaluation_context: nil)
        evaluate(flag_key, default_value, evaluation_context) do |client, mapped_ctx|
          details = client.get_string_list_details(flag_key, context: mapped_ctx)
          details = client.get_json_details(flag_key, context: mapped_ctx) if details.error_code == ::Quonfig::EvaluationDetails::ERROR_TYPE_MISMATCH
          to_resolution(details, default_value, parse_error: malformed?(client, flag_key, mapped_ctx, :object, details))
        end
      end

      private

      def client_ready?(client)
        !client.respond_to?(:ready?) || client.ready?
      end

      # +on_init_failure: :continue+ left the client without config. Report
      # ERROR once OpenFeature has recorded the READY it dispatches after +init+
      # returns, then READY when the client's background retry heals.
      def watch_for_heal(client)
        @heal_thread = Thread.new do
          await_init_dispatch
          unless client.ready?
            emit_event(::OpenFeature::SDK::ProviderEvent::PROVIDER_ERROR,
                       error_code: ErrorCode::PROVIDER_NOT_READY,
                       message: 'Quonfig has no config yet (on_init_failure: :continue); ' \
                                'serving code defaults while it retries')
          end
          emit_event(::OpenFeature::SDK::ProviderEvent::PROVIDER_READY) if client.wait_for_ready && @client.equal?(client)
        end
      end

      # OpenFeature dispatches PROVIDER_READY after +init+ returns. Wait for it
      # so our PROVIDER_ERROR lands after it, not before. +provider_state+ is
      # private in openfeature-sdk 0.5.x and public in 0.6.x.
      def await_init_dispatch
        config = @configuration
        return unless config.respond_to?(:provider_state, true)

        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + INIT_DISPATCH_WAIT_S
        while config.send(:provider_state, self) == ::OpenFeature::SDK::ProviderState::NOT_READY
          break if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

          sleep 0.01
        end
      end

      # True when +details+ is a TYPE_MISMATCH for a config whose value has a
      # type +kind+ can read but did not parse: a stored int "twelve", an int
      # ENV_VAR set to "twelve", a duration "30s" (qfg-9xsl). sdk-ruby's
      # *_details report a malformed value and a wrong-type read alike as
      # TYPE_MISMATCH, so this checks the stored +valueType+ and reads the
      # config with the getter for that type: if that read fails too, the
      # value is malformed. A config of a type +kind+ cannot read stays
      # TYPE_MISMATCH, and so does a value that parsed but does not convert
      # exactly (fetch_integer_value on a 3.9 double).
      def malformed?(client, flag_key, mapped_ctx, kind, details)
        return false unless details.error_code == ::Quonfig::EvaluationDetails::ERROR_TYPE_MISMATCH

        value_type = stored_value_type(client, flag_key)
        return false unless READABLE_VALUE_TYPES.fetch(kind).include?(value_type)

        native = client.public_send(NATIVE_DETAILS_GETTER.fetch(value_type), flag_key, context: mapped_ctx)
        native.error_code == ::Quonfig::EvaluationDetails::ERROR_TYPE_MISMATCH
      end

      # Read a duration config as its ISO 8601 text with one evaluation:
      # sdk-ruby's evaluate_details (quonfig >= 2.1.0) returns the resolved
      # value in stored form, so the text is the stored text, or an ENV_VAR's
      # text for a provided duration. evaluate_details does no type check, so
      # the text is validated here with Quonfig::Duration.valid?, the grammar
      # get_duration uses:
      #
      #   * valid text: the text, with the evaluation's reason, variant and
      #     flag_metadata.
      #   * malformed stored text ("30s"): the default with PARSE_ERROR.
      #   * malformed ENV_VAR: evaluate_details reports ERROR / TYPE_MISMATCH,
      #     which on a duration config can only mean a value that did not
      #     parse, so it is PARSE_ERROR too.
      #   * the structured { seconds, nanos } shape has no ISO text: the
      #     default with TYPE_MISMATCH.
      def duration_iso_resolution(client, flag_key, mapped_ctx, default_value)
        details = client.evaluate_details(flag_key, context: mapped_ctx)
        if details.reason == ::Quonfig::EvaluationDetails::REASON_ERROR
          parse_error = details.error_code == ::Quonfig::EvaluationDetails::ERROR_TYPE_MISMATCH
          return to_resolution(details, default_value, parse_error: parse_error)
        end
        return to_resolution(details, default_value) if details.reason == ::Quonfig::EvaluationDetails::REASON_DEFAULT

        value = details.value
        return to_resolution(details, default_value) if value.is_a?(String) && ::Quonfig::Duration.valid?(value)

        error_code = value.is_a?(String) ? ErrorCode::PARSE_ERROR : ErrorCode::TYPE_MISMATCH
        ResolutionDetails.new(value: default_value, reason: Reason::ERROR, error_code: error_code,
                              error_message: "duration #{flag_key.inspect} has no valid ISO 8601 text",
                              variant: details.variant, flag_metadata: details.flag_metadata || {})
      end

      def stored_value_type(client, flag_key)
        config = client.store.get(flag_key)
        return nil unless config.is_a?(Hash)

        (config['valueType'] || config[:valueType] || config['value_type'] || config[:value_type])&.to_s
      end

      # Map a Quonfig::EvaluationDetails to the OpenFeature ResolutionDetails
      # the SDK consumes. The Quonfig SDK's *_details methods don't raise, so
      # this is a pure mapping layer. +parse_error+ reports an ERROR as
      # PARSE_ERROR (see #malformed?); an SDK PARSE_ERROR passes straight
      # through in #map_error_code.
      def to_resolution(details, default_value, parse_error: false)
        variant = details.variant
        flag_metadata = details.flag_metadata || {}
        case details.reason
        when ::Quonfig::EvaluationDetails::REASON_STATIC
          ResolutionDetails.new(value: details.value, reason: Reason::STATIC,
                                variant: variant, flag_metadata: flag_metadata)
        when ::Quonfig::EvaluationDetails::REASON_TARGETING_MATCH
          ResolutionDetails.new(value: details.value, reason: Reason::TARGETING_MATCH,
                                variant: variant, flag_metadata: flag_metadata)
        when ::Quonfig::EvaluationDetails::REASON_SPLIT
          ResolutionDetails.new(value: details.value, reason: Reason::SPLIT,
                                variant: variant, flag_metadata: flag_metadata)
        when ::Quonfig::EvaluationDetails::REASON_DEFAULT
          ResolutionDetails.new(value: default_value, reason: Reason::DEFAULT,
                                variant: variant, flag_metadata: flag_metadata)
        when ::Quonfig::EvaluationDetails::REASON_ERROR
          ResolutionDetails.new(
            value: default_value,
            reason: Reason::ERROR,
            error_code: parse_error ? ErrorCode::PARSE_ERROR : map_error_code(details.error_code),
            error_message: details.error_message,
            variant: variant,
            flag_metadata: flag_metadata
          )
        else
          # Defensive default: surface as ERROR so unknown reasons don't
          # silently leak the SDK value back.
          ResolutionDetails.new(
            value: default_value,
            reason: Reason::ERROR,
            error_code: ErrorCode::GENERAL,
            error_message: "unknown reason: #{details.reason.inspect}",
            variant: variant,
            flag_metadata: flag_metadata
          )
        end
      end

      def map_error_code(error_code)
        case error_code
        when ::Quonfig::EvaluationDetails::ERROR_FLAG_NOT_FOUND then ErrorCode::FLAG_NOT_FOUND
        when ::Quonfig::EvaluationDetails::ERROR_TYPE_MISMATCH  then ErrorCode::TYPE_MISMATCH
        when ::Quonfig::EvaluationDetails::ERROR_PROVIDER_NOT_READY then ErrorCode::PROVIDER_NOT_READY
        when SDK_PARSE_ERROR then ErrorCode::PARSE_ERROR
        else ErrorCode::GENERAL
        end
      end

      def evaluate(_flag_key, default_value, evaluation_context)
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
      rescue ::Quonfig::Errors::UninitializedError, ::Quonfig::Errors::InitializationError => e
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
