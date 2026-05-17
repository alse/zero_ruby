# frozen_string_literal: true

require_relative "type_introspection"

module ZeroRuby
  # Schema-aware key transformer. Walks the declared type tree (mutation
  # arguments + nested InputObject attributes) and transforms wire keys
  # (camelCase) to declared names (snake_case) only at known boundaries.
  #
  # Opaque values — Hash/JSON columns, scalars, and any type that is not
  # an InputObject or Array of InputObject — pass through verbatim. This
  # prevents the gem from mangling user-defined keys stored inside JSONB
  # columns
  #
  # Output is always a string-keyed Hash, matching what
  # Mutation.coerce_and_validate! expects (it looks up args by name.to_s).
  class KeyTransformer
    # Per-class cache of compiled InputObject arg metadata. Bounded by the
    # number of declared InputObject classes; entries are frozen on insert.
    @input_object_args_cache = {}.compare_by_identity

    class << self
      include TypeIntrospection

      # @param raw_args [Hash] Raw input from the wire (string keys)
      # @param arguments_metadata [Hash<Symbol, Hash>] Shape
      #   {name_sym => {type: <dry-type>, ...}}. Same shape as
      #   Mutation.arguments and InputObject.arguments_metadata.
      # @return [Hash] String-keyed Hash with declared names; values
      #   transformed recursively only where the schema describes nested
      #   InputObjects or arrays of them.
      def transform(raw_args, arguments_metadata)
        return raw_args unless raw_args.is_a?(Hash)

        arguments_metadata.each_with_object({}) do |(name, config), result|
          key = find_wire_key(raw_args, name)
          next unless key
          result[name.to_s] = transform_value(raw_args[key], config[:type])
        end
      end

      private

      def transform_value(value, type)
        return value if value.nil?
        inner = strip_wrappers(type)

        if input_object_type?(inner)
          transform(value, input_object_arguments(inner))
        elsif array_type?(inner) && value.is_a?(Array)
          element_type = inner.member
          value.map { |v| transform_value(v, element_type) }
        else
          value
        end
      end

      def input_object_arguments(input_object_class)
        @input_object_args_cache[input_object_class] ||=
          input_object_class.arguments_metadata.freeze
      end

      # Snake-first, camel-fallback. If both keys exist, snake wins
      # (deterministic, predictable for users who pre-normalize).
      def find_wire_key(raw_args, name)
        snake = name.to_s
        return snake if raw_args.key?(snake)
        camel = to_camel_case(snake)
        return camel if camel != snake && raw_args.key?(camel)
        nil
      end
    end
  end
end
