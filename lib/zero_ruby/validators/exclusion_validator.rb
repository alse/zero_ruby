# frozen_string_literal: true

require_relative "../validator"

module ZeroRuby
  module Validators
    # Validates that a value is NOT included in a given set.
    #
    # @example
    #   validates: { exclusion: { in: ["admin", "root", "system"] } }
    class ExclusionValidator < Validator
      def validate(mutation, ctx, value)
        return nil if value.nil?

        excluded = config[:in] || config[:within]
        return nil unless excluded

        if excluded.respond_to?(:include?) ? excluded.include?(value) : excluded.cover?(value)
          message = config[:message] || "is reserved"
          return message
        end

        nil
      end
    end

    Validator.register(:exclusion, ExclusionValidator)
  end
end
