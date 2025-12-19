# frozen_string_literal: true

module ZeroRuby
  module Types
    # Base class for all types. Provides the interface for type coercion.
    class BaseType
      class << self
        def name
          raise NotImplementedError, "Subclasses must implement .name"
        end

        def coerce_input(value, _ctx = nil)
          raise NotImplementedError, "Subclasses must implement .coerce_input"
        end

        def valid?(value)
          coerce_input(value)
          true
        rescue CoercionError
          false
        end

        protected

        # Helper to raise CoercionError with consistent formatting
        # @param value [Object] The invalid value
        # @param message [String, nil] Custom message (optional)
        def coercion_error!(value, message = nil)
          displayed_value = format_value_for_error(value)
          msg = message || "#{displayed_value} is not a valid #{name}"
          raise CoercionError.new(msg, value: value, expected_type: name)
        end

        private

        # Format a value for display in error messages
        # Truncates long strings and handles various types
        def format_value_for_error(value)
          case value
          when ::String
            truncated = (value.length > 50) ? "#{value[0, 50]}..." : value
            "'#{truncated}'"
          when ::Symbol
            ":#{value}"
          when ::NilClass
            "nil"
          else
            value.inspect.then { |s| (s.length > 50) ? "#{s[0, 50]}..." : s }
          end
        end
      end
    end
  end
end
