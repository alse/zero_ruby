# frozen_string_literal: true

require_relative "types"
require_relative "type_names"
require_relative "errors"
require_relative "error_formatter"

module ZeroRuby
  # Base class for Zero mutations.
  # Provides argument DSL with dry-types validation.
  #
  # Includes ZeroRuby::TypeNames for convenient type access via the Types module
  # (e.g., Types::String, Types::ID, Types::Boolean).
  #
  # By default (auto_transact: true), the entire execute method runs inside
  # a transaction with LMID tracking. For 3-phase control, set auto_transact false.
  #
  # @example Simple mutation (auto_transact: true, default)
  #   class WorkCreate < ZeroRuby::Mutation
  #     argument :id, Types::ID
  #     argument :title, Types::String.constrained(max_size: 200)
  #
  #     def execute(id:, title:)
  #       authorize! Work, to: :create?
  #       Work.create!(id: id, title: title)  # Runs inside auto-wrapped transaction
  #     end
  #   end
  #
  # @example 3-phase mutation (skip_auto_transaction)
  #   class WorkUpdate < ZeroRuby::Mutation
  #     skip_auto_transaction
  #
  #     argument :id, Types::ID
  #     argument :title, Types::String
  #
  #     def execute(id:, title:)
  #       work = Work.find(id)
  #       authorize! work, to: :update?  # Pre-transaction
  #
  #       transact do
  #         work.update!(title: title)   # Transaction
  #       end
  #
  #       notify_update(work)            # Post-commit
  #     end
  #   end
  class Mutation
    include ZeroRuby::TypeNames

    # The context hash containing current_user, etc.
    attr_reader :ctx

    # The validated arguments hash
    attr_reader :args

    class << self
      # Opt-out of auto-transaction wrapping.
      # By default, execute is wrapped in a transaction with LMID tracking.
      # Call this to use explicit 3-phase model where you must call transact { }.
      #
      # @return [void]
      def skip_auto_transaction
        @skip_auto_transaction = true
      end

      # Check if auto-transaction is skipped for this mutation
      # @return [Boolean] true if skip_auto_transaction was called
      def skip_auto_transaction?
        @skip_auto_transaction == true
      end

      # Declare an argument for this mutation
      # @param name [Symbol] The argument name
      # @param type [Dry::Types::Type] The type (from ZeroRuby::Types or dry-types)
      # @param description [String, nil] Optional description for documentation
      def argument(name, type, description: nil)
        arguments[name.to_sym] = {
          type: type,
          description: description,
          name: name.to_sym
        }
      end

      # Get all declared arguments for this mutation (including inherited)
      # @return [Hash<Symbol, Hash>] Map of argument name to config
      def arguments
        @arguments ||= if superclass.respond_to?(:arguments)
          superclass.arguments.dup
        else
          {}
        end
      end

      # Coerce and validate raw arguments.
      # Collects ALL validation errors (missing fields, type coercion, constraints)
      # and raises a single ValidationError with all issues.
      #
      # Uses type.try(value) which returns a Result instead of raising, allowing
      # us to collect all errors in one pass rather than failing on the first one.
      # Works for both Dry::Types (scalars) and Dry::Struct (InputObjects).
      #
      # @param raw_args [Hash] Raw input arguments (string keys from JSON)
      # @return [Hash] Validated and coerced arguments (symbol keys, may contain InputObject instances)
      # @raise [ZeroRuby::ValidationError] If any validation fails
      def coerce_and_validate!(raw_args)
        # Result hash: symbol keys → coerced values (strings, integers, InputObject instances, etc.)
        # eg:
        # raw_args:  {"name" => "test", "count" => "5"}  # string keys, raw values
        # validated: {name: "test", count: 5}            # symbol keys, coerced values
        validated = {}
        errors = []

        arguments.each do |name, config|
          type = config[:type]
          str_key = name.to_s
          key_present = raw_args.key?(str_key)
          value = raw_args[str_key]
          is_input_object = input_object_type?(type)

          # Missing key: use default if available, otherwise error if required
          unless key_present
            if has_default?(type)
              validated[name] = get_default(type)
            elsif required_type?(type)
              errors << "#{name} is required"
            end
            # Optional fields without defaults are simply omitted from result
            next
          end

          # Explicit null: InputObjects always allow nil (they handle optionality internally),
          # scalars only allow nil if the type is optional
          if value.nil?
            if is_input_object || !required_type?(type)
              validated[name] = nil
            else
              errors << "#{name} is required"
            end
            next
          end

          # Coerce value: type.try returns Result instead of raising, so we can
          # collect all errors. Works for both Dry::Types and Dry::Struct.
          result = type.try(value)
          if result.failure?
            errors << format_type_error(name, result.error, is_input_object)
          else
            validated[name] = result.input
          end
        end

        raise ValidationError.new(errors) if errors.any?
        validated
      end

      private

      # Check if a type is an InputObject class
      def input_object_type?(type)
        type.is_a?(Class) && type < InputObject
      end

      # Check if a type has a default value
      def has_default?(type)
        type.respond_to?(:default?) && type.default?
      end

      # Get the default value for a type
      def get_default(type)
        return nil unless has_default?(type)
        type[]
      end

      # Check if a type is required (not optional and not with default)
      def required_type?(type)
        return true unless type.respond_to?(:optional?)
        !type.optional? && !has_default?(type)
      end

      # Format a type error (coercion or constraint failure)
      # @param name [Symbol] The field name
      # @param error [Exception] The error from try.failure
      # @param is_input_object [Boolean] Whether this is an InputObject type
      # @return [String] Formatted error message
      def format_type_error(name, error, is_input_object = false)
        if is_input_object && error.is_a?(Dry::Struct::Error)
          # InputObject errors get prefixed with field name
          ErrorFormatter.format_struct_error(error).map { |m| "#{name}.#{m}" }.first
        else
          message = case error
          when Dry::Types::CoercionError
            ErrorFormatter.format_coercion_error(error)
          when Dry::Types::ConstraintError
            ErrorFormatter.format_constraint_error(error)
          else
            error.message
          end
          "#{name}: #{message}"
        end
      end
    end

    # Initialize a mutation with raw arguments and context
    # @param raw_args [Hash] Raw input arguments (will be coerced and validated)
    # @param ctx [Hash] The context hash
    def initialize(raw_args, ctx)
      @ctx = ctx
      @args = self.class.coerce_and_validate!(raw_args)
    end

    # Execute the mutation
    # @param transact_proc [Proc] Block that wraps transactional work (internal use)
    # @return [Hash] Empty hash on success, or {data: ...} if execute returns a Hash
    # @raise [ZeroRuby::Error] On failure (formatted at boundary)
    # @raise [ZeroRuby::TransactNotCalledError] If skip_auto_transaction and transact not called
    def call(&transact_proc)
      @transact_proc = transact_proc
      @transact_called = false

      if self.class.skip_auto_transaction?
        # Manual mode: Use defined mutation calls transact {}
        data = execute(**@args)
        raise TransactNotCalledError.new unless @transact_called
      else
        # Auto mode: wrap entire execute in transaction
        data = transact_proc.call { execute(**@args) }
      end

      result = {}
      result[:data] = data if data.is_a?(Hash) && !data.empty?
      result
    end

    private

    # Wrap database operations in a transaction with LMID tracking.
    # Used by user defined mutation.
    #
    # Behavior depends on skip_auto_transaction:
    # - Default (no skip) - Just executes the block (already in transaction)
    # - skip_auto_transaction - Wraps block in transaction via transact_proc
    #
    # For skip_auto_transaction mutations, you MUST call this method.
    # For default mutations, calling this is optional (no-op, just runs block).
    #
    # @yield Block containing database operations
    # @return [Object] Result of the block
    def transact(&block)
      raise "transact requires a block" unless block_given?
      @transact_called = true

      if self.class.skip_auto_transaction?
        # Manual mode - actually call the transact_proc to start transaction
        @transact_proc.call(&block)
      else
        # Auto mode - already in transaction, just execute the block
        block.call
      end
    end

    # Convenience method to access current_user from context.
    # Override in your ApplicationMutation if you need different behavior.
    def current_user
      ctx[:current_user]
    end

    # Implement this method in subclasses to define mutation logic.
    # Arguments are passed as keyword arguments matching your declared arguments.
    # Access context via ctx[:key] or use the current_user helper.
    #
    # By default (auto_transact: true), the entire execute method runs inside
    # a transaction with LMID tracking. Just write your database operations directly.
    #
    # For 3-phase control, use `skip_auto_transaction` and call transact { ... }:
    # - Pre-transaction: code before transact (auth, validation)
    # - Transaction: code inside transact { } (database operations)
    # - Post-commit: code after transact returns (side effects)
    #
    # @example Simple mutation (default auto_transact: true)
    #   def execute(id:, title:)
    #     authorize! Post, to: :create?
    #     Post.create!(id: id, title: title)
    #   end
    #
    # @example 3-phase mutation (skip_auto_transaction)
    #   def execute(id:, title:)
    #     authorize! Post, to: :create?     # Pre-transaction
    #     result = transact do
    #       Post.create!(id: id, title: title)  # Transaction
    #     end
    #     NotificationService.notify(result.id)  # Post-commit
    #     {id: result.id}
    #   end
    def execute(**args)
      raise NotImplementedError, "Subclasses must implement #execute"
    end
  end
end
