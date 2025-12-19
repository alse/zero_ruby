# frozen_string_literal: true

require_relative "../validator"

module ZeroRuby
  module Validators
    # Validates that a value matches a regular expression.
    #
    # @example
    #   validates: { format: { with: /\A[a-z0-9_]+\z/ } }
    #   validates: { format: { without: /[<>]/ } }
    class FormatValidator < Validator
      def validate(mutation, ctx, value)
        return nil if value.nil?

        str_value = value.to_s
        errors = []

        if config[:with] && !str_value.match?(config[:with])
          message = config[:message] || "is invalid"
          errors << message
        end

        if config[:without] && str_value.match?(config[:without])
          message = config[:message] || "is invalid"
          errors << message
        end

        errors.empty? ? nil : errors
      end
    end

    Validator.register(:format, FormatValidator)
  end
end
