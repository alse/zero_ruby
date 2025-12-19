# frozen_string_literal: true

require "dry-types"

module ZeroRuby
  # Type definitions using dry-types.
  #
  # When inheriting from ZeroRuby::Mutation or ZeroRuby::InputObject, types are
  # available via the Types module (e.g., Types::String, Types::ID).
  #
  # @example Basic usage
  #   class MyMutation < ZeroRuby::Mutation
  #     argument :id, Types::ID
  #     argument :name, Types::String
  #     argument :count, Types::Integer.optional
  #     argument :active, Types::Boolean.default(false)
  #   end
  #
  # @example With constraints
  #   class MyMutation < ZeroRuby::Mutation
  #     argument :title, Types::String.constrained(min_size: 1, max_size: 200)
  #     argument :count, Types::Integer.constrained(gt: 0)
  #     argument :status, Types::String.constrained(included_in: %w[draft published])
  #   end
  module Types
    include Dry.Types()

    # Params types for JSON input
    # These handle string coercions common in form/JSON data

    # String type (passes through strings, coerces nil)
    String = Params::String

    # Coerces string numbers to integers (e.g., "42" -> 42)
    Integer = Params::Integer

    # Coerces string numbers to floats (e.g., "3.14" -> 3.14)
    Float = Params::Float

    # Coerces string booleans (e.g., "true" -> true, "false" -> false)
    Boolean = Params::Bool

    # Non-empty string ID type
    ID = Params::String.constrained(filled: true)

    # ISO8601 date string -> Date object
    ISO8601Date = Params::Date

    # ISO8601 datetime string -> DateTime object
    ISO8601DateTime = Params::DateTime
  end
end
