# frozen_string_literal: true

require_relative "../validator"

module ZeroRuby
  module Validators
    # Validates numeric constraints on a value.
    #
    # @example
    #   validates: { numericality: { greater_than: 0 } }
    #   validates: { numericality: { less_than_or_equal_to: 100 } }
    #   validates: { numericality: { equal_to: 42 } }
    #   validates: { numericality: { odd: true } }
    #   validates: { numericality: { even: true } }
    class NumericalityValidator < Validator
      def validate(mutation, ctx, value)
        return nil if value.nil?

        unless value.is_a?(Numeric)
          return "is not a number"
        end

        errors = []

        if config[:greater_than] && value <= config[:greater_than]
          errors << "must be greater than #{config[:greater_than]}"
        end

        if config[:greater_than_or_equal_to] && value < config[:greater_than_or_equal_to]
          errors << "must be greater than or equal to #{config[:greater_than_or_equal_to]}"
        end

        if config[:less_than] && value >= config[:less_than]
          errors << "must be less than #{config[:less_than]}"
        end

        if config[:less_than_or_equal_to] && value > config[:less_than_or_equal_to]
          errors << "must be less than or equal to #{config[:less_than_or_equal_to]}"
        end

        if config[:equal_to] && value != config[:equal_to]
          errors << "must be equal to #{config[:equal_to]}"
        end

        if config[:other_than] && value == config[:other_than]
          errors << "must be other than #{config[:other_than]}"
        end

        if config[:odd] && value.to_i.even?
          errors << "must be odd"
        end

        if config[:even] && value.to_i.odd?
          errors << "must be even"
        end

        errors.empty? ? nil : errors
      end
    end

    Validator.register(:numericality, NumericalityValidator)
  end
end
