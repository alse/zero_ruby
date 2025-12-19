# frozen_string_literal: true

require_relative "errors"
require_relative "error_formatter"

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

      # Get handler class for a mutation name
      # @param name [String] The mutation name
      # @return [Class, nil] The handler class or nil if not found
      def handler_for(name)
        mutations[normalize_mutation_name(name)]
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
        validate_push_structure!(push_data)

        push_version = push_data["pushVersion"]
        supported_version = ZeroRuby.configuration.supported_push_version

        unless push_version == supported_version
          mutations = push_data["mutations"] || []
          mutation_ids = mutations.map { |m| {id: m["id"], clientID: m["clientID"]} }

          return {
            kind: "PushFailed",
            origin: "server",
            reason: "unsupportedPushVersion",
            message: "Unsupported push version: #{push_version}. Expected: #{supported_version}",
            mutationIDs: mutation_ids
          }
        end

        store = lmid_store || ZeroRuby.configuration.lmid_store_instance
        processor = PushProcessor.new(
          schema: self,
          lmid_store: store
        )
        processor.process(push_data, context)
      rescue ParseError => e
        {
          kind: "PushFailed",
          origin: "server",
          reason: "parse",
          message: e.message,
          mutationIDs: []
        }
      end

      # Execute a single mutation.
      # Used by PushProcessor for LMID-tracked mutations.
      # @param mutation_data [Hash] The mutation data from Zero
      # @param context [Hash] Context hash to pass to mutations
      # @param transact [Proc] Block that wraps transactional work
      # @return [Hash] Empty hash on success
      # @raise [MutationNotFoundError] If the mutation is not registered
      # @raise [ZeroRuby::Error] If the mutation fails
      def execute_mutation(mutation_data, context, &transact)
        name = normalize_mutation_name(mutation_data["name"])
        handler = mutations[name]
        raise MutationNotFoundError.new(name) unless handler

        raw_args = extract_args(mutation_data)
        params = transform_keys(raw_args)

        handler.new(params, context).call(&transact)
      rescue Dry::Struct::Error => e
        raise ValidationError.new(ErrorFormatter.format_struct_error(e))
      rescue Dry::Types::CoercionError => e
        raise ValidationError.new([ErrorFormatter.format_coercion_error(e)])
      rescue Dry::Types::ConstraintError => e
        raise ValidationError.new([ErrorFormatter.format_constraint_error(e)])
      end

      private

      # Validate push data structure per Zero protocol
      # Required fields: clientGroupID, mutations, pushVersion, timestamp, requestID
      # @raise [ParseError] If push data is malformed
      def validate_push_structure!(push_data)
        unless push_data.is_a?(Hash)
          raise ParseError.new("Push data must be a hash")
        end

        %w[clientGroupID mutations pushVersion timestamp requestID].each do |field|
          unless push_data.key?(field)
            raise ParseError.new("Missing required field: #{field}")
          end
        end

        unless push_data["mutations"].is_a?(Array)
          raise ParseError.new("Field 'mutations' must be an array")
        end
      end

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

      # Transform camelCase string keys to snake_case strings (deep).
      # Keys are kept as strings to prevent symbol table DoS attacks.
      # Symbolization happens later in coerce_and_validate! using schema-defined keys.
      # @param object [Object] The object to transform
      # @return [Object] Transformed object with string keys
      def transform_keys(object)
        case object
        when Hash
          object.each_with_object({}) do |(key, value), result|
            new_key = key.to_s.gsub(/([A-Z])/, '_\1').downcase.delete_prefix("_")
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
