# frozen_string_literal: true

require "dry-struct"
require_relative "types"
require_relative "type_names"

module ZeroRuby
  # Base class for input objects (nested argument types).
  # Uses Dry::Struct for type coercion and validation.
  #
  # Includes ZeroRuby::TypeNames for convenient type access via the Types module
  # (e.g., Types::String, Types::ID, Types::Boolean).
  #
  # @example
  #   class Types::PostInput < ZeroRuby::InputObject
  #     argument :id, Types::ID
  #     argument :title, Types::String.constrained(min_size: 1, max_size: 200)
  #     argument :body, Types::String.optional
  #     argument :published, Types::Boolean.default(false)
  #   end
  #
  #   class PostCreate < ZeroRuby::Mutation
  #     argument :post_input, Types::PostInput
  #     argument :notify, Types::Boolean.default(false)
  #
  #     def execute
  #       # args[:post_input].title, args[:post_input].body, etc.
  #       # Or use **args[:post_input] to splat into method calls
  #     end
  #   end
  class InputObject < Dry::Struct
    include ZeroRuby::TypeNames

    # Transform string keys to symbols (for JSON input)
    transform_keys(&:to_sym)

    # Use permissive schema that allows omitting optional attributes
    # This matches the behavior where missing optional keys are omitted from result
    schema schema.strict(false)

    class << self
      # Alias attribute to argument for DSL compatibility
      # @param name [Symbol] The argument name
      # @param type [Dry::Types::Type] The type (from ZeroRuby::Types)
      # @param description [String, nil] Optional description (stored for documentation, not passed to Dry::Struct)
      def argument(name, type, description: nil, **_options)
        # Store description for documentation/TypeScript generation
        argument_descriptions[name.to_sym] = description if description

        # Use attribute? for optional types (allows key to be omitted)
        # Use attribute for required types (key must be present)
        if optional_type?(type)
          attribute?(name, type)
        else
          attribute(name, type)
        end
      end

      # Get stored argument descriptions
      def argument_descriptions
        @argument_descriptions ||= {}
      end

      # Check if a type is optional (can accept nil or has a default)
      def optional_type?(type)
        return false unless type.respond_to?(:optional?)
        type.optional? || (type.respond_to?(:default?) && type.default?)
      end

      # Returns argument metadata for TypeScript generation
      # @return [Hash<Symbol, Hash>] Map of argument name to metadata
      def arguments_metadata
        schema.keys.each_with_object({}) do |key, hash|
          hash[key.name] = {
            type: key.type,
            required: key.required?,
            name: key.name
          }
        end
      end
    end
  end
end
