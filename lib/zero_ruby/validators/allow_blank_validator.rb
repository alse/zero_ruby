# frozen_string_literal: true

require_relative "../validator"

module ZeroRuby
  module Validators
    # Validates that a value is not blank when allow_blank is false.
    #
    # @example
    #   validates: { allow_blank: false }
    class AllowBlankValidator < Validator
      def validate(mutation, ctx, value)
        # If allow_blank is true (or truthy), blank values are allowed
        return nil if config == true || config

        # Check if value is blank (nil, empty string, or whitespace-only string)
        is_blank = value.nil? ||
          (value.respond_to?(:empty?) && value.empty?) ||
          (value.is_a?(::String) && value.strip.empty?)

        if is_blank
          return "can't be blank"
        end

        nil
      end
    end

    Validator.register(:allow_blank, AllowBlankValidator)
  end
end
