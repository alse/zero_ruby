# frozen_string_literal: true

require_relative "errors"

module ZeroRuby
  # Schema class for registering and processing Zero mutations.
  #
  # @example
  #   class ZeroSchema < ZeroRuby::Schema
  #     mutation "works.create", handler: Mutations::WorkCreate
  #     mutation "works.update", handler: Mutations::WorkUpdate
  #   end
  class Schema
    class << self
      # Register a mutation handler
      # @param name [String] The mutation name (e.g., "works.create")
      # @param handler [Class] The mutation class to handle this mutation
      def mutation(name, handler:)
        mutations[name.to_s] = handler
      end

      # Get all registered mutations
      def mutations
        @mutations ||= if superclass.respond_to?(:mutations)
          superclass.mutations.dup
        else
          {}
        end
      end

      # Generate TypeScript type definitions from registered mutations
      # @return [String] TypeScript type definitions
      def to_typescript
        TypeScriptGenerator.new(self).generate
      end

      # Execute a Zero push request. This is the main entry point for processing mutations.
      #
      # @param push_data [Hash] The parsed push request body
      # @param context [Hash] Context hash to pass to mutations (e.g., current_user:)
      # @param lmid_store [LmidStore, nil] Optional LMID store override
      # @return [Hash] Result hash: {mutations: [...]} on success, {error: {...}} on failure
      #
      # @example Basic usage
      #   body = JSON.parse(request.body.read)
      #   result = ZeroSchema.execute(body, context: {current_user: user})
      #   render json: result
      def execute(push_data, context:, lmid_store: nil)
        push_version = push_data["pushVersion"]
        supported_version = ZeroRuby.configuration.supported_push_version

        unless push_version == supported_version
          return {
            error: {
              kind: "PushFailed",
              reason: "UnsupportedPushVersion",
              message: "Unsupported push version: #{push_version}. Expected: #{supported_version}"
            }
          }
        end

        store = lmid_store || ZeroRuby.configuration.lmid_store_instance
        processor = PushProcessor.new(
          schema: self,
          lmid_store: store,
          max_retries: ZeroRuby.configuration.max_retry_attempts
        )
        processor.process(push_data, context)
      end

      # Execute a single mutation.
      # Used by PushProcessor for LMID-tracked mutations.
      # @param mutation_data [Hash] The mutation data from Zero
      # @param context [Hash] Context hash to pass to mutations
      # @return [Hash] Empty hash on success
      # @raise [MutationNotFoundError] If the mutation is not registered
      # @raise [ZeroRuby::Error] If the mutation fails
      def execute_mutation(mutation_data, context)
        name = normalize_mutation_name(mutation_data["name"])
        raw_args = extract_args(mutation_data)
        params = transform_keys(raw_args)

        ctx = context.freeze
        handler = mutations[name]

        raise MutationNotFoundError.new(name) unless handler

        handler.new(params, ctx).call
      end

      private

      # Normalize mutation name (convert | to . for Zero's format)
      def normalize_mutation_name(name)
        return "" if name.nil?
        name.tr("|", ".")
      end

      # Extract args from mutation data
      def extract_args(mutation_data)
        args = mutation_data["args"]
        return {} if args.nil?

        # Zero sends args as an array with a single object
        args.is_a?(Array) ? (args.first || {}) : args
      end

      # Transform camelCase string keys to snake_case symbols (deep)
      def transform_keys(object)
        case object
        when Hash
          object.each_with_object({}) do |(key, value), result|
            new_key = key.to_s.gsub(/([A-Z])/, '_\1').downcase.delete_prefix("_").to_sym
            result[new_key] = transform_keys(value)
          end
        when Array
          object.map { |e| transform_keys(e) }
        else
          object
        end
      end
    end
  end
end
