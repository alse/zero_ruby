# frozen_string_literal: true

require_relative "../validator"

module ZeroRuby
  module Validators
    # Validates the length of a string or array value.
    #
    # @example
    #   validates: { length: { minimum: 1, maximum: 200 } }
    #   validates: { length: { is: 10 } }
    #   validates: { length: { in: 5..10 } }
    class LengthValidator < Validator
      def validate(mutation, ctx, value)
        return nil if value.nil?

        length = value.respond_to?(:length) ? value.length : value.to_s.length
        errors = []

        if config[:minimum] && length < config[:minimum]
          errors << "is too short (minimum is #{config[:minimum]})"
        end

        if config[:maximum] && length > config[:maximum]
          errors << "is too long (maximum is #{config[:maximum]})"
        end

        if config[:is] && length != config[:is]
          errors << "is the wrong length (should be #{config[:is]})"
        end

        if config[:in] && !config[:in].cover?(length)
          errors << "length is not in #{config[:in]}"
        end

        errors.empty? ? nil : errors
      end
    end

    Validator.register(:length, LengthValidator)
  end
end
