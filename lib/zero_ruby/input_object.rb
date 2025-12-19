# frozen_string_literal: true

require_relative "argument"
require_relative "errors"
require_relative "validator"

module ZeroRuby
  # Base class for input objects (nested argument types).
  # Similar to GraphQL-Ruby's InputObject pattern.
  #
  # @example
  #   class Types::PostInput < ZeroRuby::InputObject
  #     argument :id, ID, required: true
  #     argument :title, String, required: true
  #     argument :body, String, required: false
  #   end
  #
  #   class PostCreate < ZeroRuby::Mutation
  #     argument :post_input, Types::PostInput, required: true
  #     argument :notify, Boolean, required: false
  #
  #     def execute(post_input:, notify: nil)
  #       Post.create!(**post_input)
  #     end
  #   end
  class InputObject
    include TypeNames

    class << self
      # Declare an argument for this input object
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

      # Get all declared arguments (including inherited)
      def arguments
        @arguments ||= if superclass.respond_to?(:arguments)
          superclass.arguments.dup
        else
          {}
        end
      end

      # Coerce and validate raw input
      # @param raw_args [Hash] Raw input
      # @param ctx [Hash] The context hash
      # @return [Hash] Validated and coerced hash (only includes keys present in input or with defaults)
      # @raise [ZeroRuby::ValidationError] If validation fails
      def coerce(value, ctx)
        return nil if value.nil?
        return nil unless value.is_a?(Hash)

        validated = {}
        errors = []

        arguments.each do |name, arg|
          key_present = value.key?(name) || value.key?(name.to_s)
          val = if key_present
            value[name].nil? ? value[name.to_s] : value[name]
          end

          # Check required
          if arg.required? && !key_present && !arg.has_default?
            errors << "#{name} is required"
            next
          end

          # Apply default if key not present
          if !key_present && arg.has_default?
            validated[name] = arg.default
            next
          end

          # Skip if key not present (don't add to validated hash)
          next unless key_present

          # Handle nil values - include in hash but skip coercion
          if val.nil?
            validated[name] = nil
            next
          end

          # Type coercion (handles nested InputObjects)
          begin
            coerced = arg.coerce(val, ctx)
          rescue CoercionError => e
            errors << "#{name}: #{e.message}"
            next
          rescue ValidationError => e
            # Nested InputObject validation errors - prefix with field name
            e.errors.each do |err|
              errors << "#{name}.#{err}"
            end
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
end
