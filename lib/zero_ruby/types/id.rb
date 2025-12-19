# frozen_string_literal: true

require_relative "base_type"

module ZeroRuby
  module Types
    # ID type for unique identifiers (database PKs, FKs, etc.)
    # Accepts strings and integers, always coerces to String.
    class ID < BaseType
      class << self
        def name
          "ID"
        end

        def coerce_input(value, _ctx = nil)
          return nil if value.nil?

          case value
          when ::String
            coercion_error!(value, "empty string is not a valid #{name}") if value.empty?
            value
          when ::Integer
            value.to_s
          when ::Symbol
            value.to_s
          else
            coercion_error!(value, "#{format_value_for_error(value)} (#{value.class}) cannot be coerced to #{name}")
          end
        end
      end
    end
  end
end
