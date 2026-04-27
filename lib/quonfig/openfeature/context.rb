# frozen_string_literal: true

module Quonfig
  module OpenFeature
    # Maps an OpenFeature flat EvaluationContext to Quonfig's nested contexts hash.
    #
    # Mapping rules (mirror @quonfig/openfeature-node and openfeature-go):
    #   - +targeting_key+ maps to namespace+property specified by +targeting_key_mapping+
    #     (default "user.id"). The mapping is split on the FIRST dot — namespace before,
    #     property after.
    #   - Keys with a dot are split on the first dot: "user.email" -> { "user" => { "email" => v } }
    #   - Keys without a dot go to the default empty-string namespace:
    #     "country" -> { "" => { "country" => v } }
    #   - Multi-dot keys split on the first dot only:
    #     "user.ip.address" -> { "user" => { "ip.address" => v } }
    #   - Nil values are skipped.
    #   - An empty / nil context returns +{}+.
    module Context
      module_function

      DEFAULT_TARGETING_KEY_MAPPING = 'user.id'
      TARGETING_KEY_FIELDS = %w[targeting_key targetingKey].freeze

      # @param of_context [::OpenFeature::SDK::EvaluationContext, Hash, nil]
      # @param targeting_key_mapping [String]
      # @return [Hash{String=>Hash{String=>Object}}]
      def map_context(of_context, targeting_key_mapping = DEFAULT_TARGETING_KEY_MAPPING)
        return {} if of_context.nil?

        fields, targeting_key = extract_fields_and_targeting_key(of_context)
        return {} if fields.empty? && (targeting_key.nil? || targeting_key.to_s.empty?)

        result = {}

        unless targeting_key.nil? || targeting_key.to_s.empty?
          ns, prop = split_first(targeting_key_mapping)
          assign(result, ns, prop, targeting_key)
        end

        fields.each do |key, value|
          next if value.nil?
          # The targeting_key is handled above; do not also write it under its raw name.
          next if TARGETING_KEY_FIELDS.include?(key.to_s)

          ns, prop = split_first(key.to_s)
          assign(result, ns, prop, value)
        end

        result
      end

      # Returns [fields_hash_with_string_keys, targeting_key_or_nil]. Accepts an
      # OpenFeature::SDK::EvaluationContext (preferred) or a plain Hash.
      def extract_fields_and_targeting_key(ctx)
        if ctx.respond_to?(:fields) && ctx.respond_to?(:targeting_key)
          [(ctx.fields || {}).transform_keys(&:to_s), ctx.targeting_key]
        elsif ctx.is_a?(Hash)
          stringified = ctx.transform_keys(&:to_s)
          tk = stringified['targeting_key'] || stringified['targetingKey']
          [stringified, tk]
        else
          [{}, nil]
        end
      end

      def split_first(key)
        idx = key.index('.')
        return ['', key] if idx.nil?

        [key[0...idx], key[(idx + 1)..]]
      end

      def assign(result, namespace, property, value)
        result[namespace] ||= {}
        result[namespace][property] = value
      end
    end
  end
end
