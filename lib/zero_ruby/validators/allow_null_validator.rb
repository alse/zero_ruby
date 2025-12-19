# frozen_string_literal: true

require_relative "../validator"

module ZeroRuby
  module Validators
    # Validates that a value is not null when allow_null is false.
    #
    # @example
    #   validates: { allow_null: false }
    class AllowNullValidator < Validator
      def validate(mutation, ctx, value)
        # If allow_null is true (or truthy), null values are allowed
        return nil if config == true || config

        if value.nil?
          return "can't be null"
        end

        nil
      end
    end

    Validator.register(:allow_null, AllowNullValidator)
  end
end
