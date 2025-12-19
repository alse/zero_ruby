# frozen_string_literal: true

module ZeroRuby
  # Provides shorthand constants for ZeroRuby types.
  # Include this module to use ID, Boolean, etc. without the ZeroRuby::Types:: prefix.
  #
  # This is automatically included in Mutation and InputObject, so you can write:
  #
  #   class PostCreate < ZeroRuby::Mutation
  #     argument :id, ID, required: true
  #     argument :title, String, required: true
  #     argument :active, Boolean, required: true
  #   end
  #
  # Note: String, Integer, and Float work automatically because Ruby's built-in
  # classes are resolved to ZeroRuby types by the argument system.
  module TypeNames
    ID = ZeroRuby::Types::ID
    Boolean = ZeroRuby::Types::Boolean
    BigInt = ZeroRuby::Types::BigInt
    ISO8601Date = ZeroRuby::Types::ISO8601Date
    ISO8601DateTime = ZeroRuby::Types::ISO8601DateTime
  end
end
