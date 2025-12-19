# frozen_string_literal: true

require "time"
require_relative "base_type"

module ZeroRuby
  module Types
    # ISO8601DateTime type for datetime values.
    # Accepts ISO8601 formatted strings, Time, and DateTime objects.
    # Coerces to Time.
    class ISO8601DateTime < BaseType
      class << self
        def name
          "ISO8601DateTime"
        end

        def coerce_input(value, _ctx = nil)
          return nil if value.nil?

          case value
          when ::Time
            value
          when ::DateTime
            value.to_time
          when ::String
            coercion_error!(value, "empty string is not a valid #{name}") if value.empty?
            parse_iso8601(value)
          else
            coercion_error!(value, "#{format_value_for_error(value)} (#{value.class}) cannot be coerced to #{name}")
          end
        end

        private

        def parse_iso8601(value)
          Time.iso8601(value)
        rescue ArgumentError
          coercion_error!(value, "#{format_value_for_error(value)} is not a valid ISO8601 datetime")
        end
      end
    end
  end
end
