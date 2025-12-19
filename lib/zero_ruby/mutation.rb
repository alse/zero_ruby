# frozen_string_literal: true

require_relative "argument"
require_relative "errors"
require_relative "validator"

module ZeroRuby
  # Mixin that provides the argument DSL for mutations.
  # Inspired by graphql-ruby's HasArguments pattern.
  module HasArguments
    def self.included(base)
      base.extend(ClassMethods)
    end

    module ClassMethods
      # Declare an argument for this mutation
      # @param name [Symbol] The argument name
      # @param type [Class] The type class (e.g., ZeroRuby::Types::String)
      # @param required [Boolean] Whether the argument is required
      # @param validates [Hash] Validation configuration
      # @param default [Object] Default value if not provided
      # @param description [String] Description of the argument
      def argument(name, type, required: true, validates: nil, default: Argument::NOT_PROVIDED, description: nil, **options)
        arguments[name.to_sym] = Argument.new(
          name: name,
          type: type,
          required: required,
          validates: validates,
          default: default,
          description: description,
          **options
        )
      end

      # Get all declared arguments for this mutation (including inherited)
      def arguments
        @arguments ||= if superclass.respond_to?(:arguments)
          superclass.arguments.dup
        else
          {}
        end
      end

      # Coerce and validate raw arguments
      # @param raw_args [Hash] Raw input arguments
      # @param ctx [Hash] The context hash
      # @return [Hash] Validated and coerced arguments
      # @raise [ZeroRuby::ValidationError] If validation fails
      def coerce_and_validate!(raw_args, ctx)
        validated = {}
        errors = []

        arguments.each do |name, arg|
          value = raw_args[name]

          # Check required
          if arg.required? && value.nil? && !arg.has_default?
            errors << "#{name} is required"
            next
          end

          # Apply default if needed, or nil for optional args without defaults
          if value.nil?
            validated[name] = arg.has_default? ? arg.default : nil
            next
          end

          # Type coercion
          begin
            coerced = arg.coerce(value, ctx)
          rescue CoercionError => e
            errors << "#{name}: #{e.message}"
            next
          end

          # Run validators
          if arg.validators.any?
            validation_errors = Validator.validate!(arg.validators, nil, ctx, coerced)
            validation_errors.each do |err|
              errors << "#{name} #{err}"
            end
          end

          validated[name] = coerced
        end

        raise ValidationError.new(errors) if errors.any?
        validated
      end
    end
  end

  # Base class for Zero mutations.
  # Provides argument DSL, validation, and error handling.
  #
  # @example
  #   class WorkCreate < ZeroRuby::Mutation
  #     argument :id, ID, required: true
  #     argument :title, String, required: true,
  #       validates: { length: { maximum: 200 } }
  #
  #     def execute(id:, title:)
  #       authorize! Work, to: :create?
  #       Work.create!(id: id, title: title)
  #     end
  #   end
  class Mutation
    include HasArguments
    include TypeNames

    # The context hash containing current_user, etc.
    attr_reader :ctx

    # Initialize a mutation with raw arguments and context
    # @param raw_args [Hash] Raw input arguments (will be coerced and validated)
    # @param ctx [Hash] The context hash
    def initialize(raw_args, ctx)
      @ctx = ctx
      @args = self.class.coerce_and_validate!(raw_args, ctx)
    end

    # Execute the mutation
    # @return [Hash] Empty hash on success
    # @raise [ZeroRuby::Error] On failure (formatted at boundary)
    def call
      execute(**@args)
      {}
    end

    private

    # Implement this method in subclasses to define mutation logic.
    # Arguments declared with `argument` are passed as keyword arguments.
    # Access context via ctx[:key] (e.g., ctx[:current_user]).
    # No return value needed - just perform the mutation.
    # Raise an exception to signal failure.
    def execute(**)
      raise NotImplementedError, "Subclasses must implement #execute"
    end
  end
end
