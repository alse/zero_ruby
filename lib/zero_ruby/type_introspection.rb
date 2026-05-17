# frozen_string_literal: true

module ZeroRuby
  # Shared dry-types unwrapping helpers used by both the schema-aware key
  # transformer and the TypeScript generator. Both need to look through
  # Optional/Default/Constrained wrappers and detect InputObject / Array
  # types in the same way.
  module TypeIntrospection
    module_function

    def input_object_type?(type)
      type.is_a?(Class) && type < ZeroRuby::InputObject
    end

    def array_type?(type)
      type.respond_to?(:primitive) && type.primitive == Array
    end

    def sum_type?(type)
      type.respond_to?(:left) && type.respond_to?(:right)
    end

    def optional_type?(type)
      return false unless type.respond_to?(:optional?)
      type.optional? || (type.respond_to?(:default?) && type.default?)
    end

    def extract_non_nil_type(type)
      return nil unless sum_type?(type)
      if type.left.respond_to?(:primitive) && type.left.primitive == NilClass
        type.right
      elsif type.right.respond_to?(:primitive) && type.right.primitive == NilClass
        type.left
      end
    end

    # Convert a snake_case identifier to camelCase (e.g. some_value -> someValue).
    # Single-word names are returned unchanged.
    def to_camel_case(snake)
      snake = snake.to_s
      parts = snake.split("_")
      return snake if parts.length == 1
      parts.first + parts[1..].map(&:capitalize).join
    end

    # Strip Optional (Sum with NilClass), Default, and Constrained wrappers
    # to expose the underlying dry-type. Stops at the first "real" type so
    # callers can dispatch on input_object_type? / array_type? etc.
    def strip_wrappers(type)
      loop do
        if sum_type?(type) && (inner = extract_non_nil_type(type))
          type = inner
          next
        end

        if type.is_a?(Dry::Types::Default) || type.is_a?(Dry::Types::Constrained)
          type = type.type
          next
        end

        break
      end
      type
    end
  end
end
