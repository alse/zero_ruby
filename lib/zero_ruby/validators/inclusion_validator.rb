# frozen_string_literal: true

require_relative "../validator"

module ZeroRuby
  module Validators
    # Validates that a value is included in a given set.
    #
    # @example
    #   validates: { inclusion: { in: ["draft", "published", "archived"] } }
    #   validates: { inclusion: { in: 1..10 } }
    class InclusionValidator < Validator
      def validate(mutation, ctx, value)
        return nil if value.nil?

        allowed = config[:in] || config[:within]
        return nil unless allowed

        unless allowed.respond_to?(:include?) ? allowed.include?(value) : allowed.cover?(value)
          message = config[:message] || "is not included in the list"
          return message
        end

        nil
      end
    end

    Validator.register(:inclusion, InclusionValidator)
  end
end
