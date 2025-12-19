# frozen_string_literal: true

require_relative "base_type"

module ZeroRuby
  module Types
    class String < BaseType
      class << self
        def name
          "String"
        end

        def coerce_input(value, _ctx = nil)
          return nil if value.nil?
          value.to_s
        end
      end
    end
  end
end
