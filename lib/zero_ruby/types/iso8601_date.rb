# frozen_string_literal: true

require "date"
require_relative "base_type"

module ZeroRuby
  module Types
    # ISO8601Date type for date values.
    # Accepts ISO8601 formatted date strings, Date, Time, and DateTime objects.
    # Coerces to Date.
    class ISO8601Date < BaseType
      class << self
        def name
          "ISO8601Date"
        end

        def coerce_input(value, _ctx = nil)
          return nil if value.nil?

          case value
          when ::Date
            value
          when ::Time, ::DateTime
            value.to_date
          when ::String
            coercion_error!(value, "empty string is not a valid #{name}") if value.empty?
            parse_iso8601_date(value)
          else
            coercion_error!(value, "#{format_value_for_error(value)} (#{value.class}) cannot be coerced to #{name}")
          end
        end

        private

        def parse_iso8601_date(value)
          Date.iso8601(value)
        rescue ArgumentError
          coercion_error!(value, "#{format_value_for_error(value)} is not a valid ISO8601 date")
        end
      end
    end
  end
end
