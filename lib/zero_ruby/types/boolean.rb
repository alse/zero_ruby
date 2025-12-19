# frozen_string_literal: true

require_relative "base_type"

module ZeroRuby
  module Types
    class Boolean < BaseType
      TRUTHY_VALUES = [true, "true", "1", 1].freeze
      FALSY_VALUES = [false, "false", "0", 0].freeze

      class << self
        def name
          "Boolean"
        end

        def coerce_input(value, _ctx = nil)
          return nil if value.nil?

          if TRUTHY_VALUES.include?(value)
            true
          elsif FALSY_VALUES.include?(value)
            false
          else
            coercion_error!(value, "#{format_value_for_error(value)} is not a valid #{name}; expected true, false, \"true\", \"false\", 0, or 1")
          end
        end
      end
    end
  end
end
