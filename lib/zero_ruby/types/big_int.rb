# frozen_string_literal: true

require_relative "base_type"

module ZeroRuby
  module Types
    # BigInt type for large integers beyond 32-bit range.
    # Ruby's Integer handles arbitrary precision natively.
    # Accepts integers and numeric strings, coerces to Integer.
    class BigInt < BaseType
      class << self
        def name
          "BigInt"
        end

        def coerce_input(value, _ctx = nil)
          return nil if value.nil?
          return value if value.is_a?(::Integer)

          if value.is_a?(::String)
            coercion_error!(value, "empty string is not a valid #{name}") if value.empty?
            result = Kernel.Integer(value, exception: false)
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
