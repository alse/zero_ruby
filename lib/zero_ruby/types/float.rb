# frozen_string_literal: true

require_relative "base_type"

module ZeroRuby
  module Types
    class Float < BaseType
      class << self
        def name
          "Float"
        end

        def coerce_input(value, _ctx = nil)
          return nil if value.nil?
          return value if value.is_a?(::Float)

          if value.is_a?(::Integer)
            value.to_f
          elsif value.is_a?(::String)
            coercion_error!(value, "empty string is not a valid #{name}") if value.empty?
            result = Kernel.Float(value, exception: false)
            coercion_error!(value) if result.nil?
            result
          else
            coercion_error!(value, "#{format_value_for_error(value)} (#{value.class}) cannot be coerced to #{name}")
          end
        end
      end
    end
  end
end
