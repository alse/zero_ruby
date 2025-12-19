# frozen_string_literal: true

module ZeroRuby
  # Provides access to ZeroRuby::Types via the Types constant.
  # Automatically included in Mutation and InputObject classes.
  #
  # @example Usage in mutations
  #   class PostCreate < ZeroRuby::Mutation
  #     argument :id, Types::ID
  #     argument :title, Types::String
  #     argument :active, Types::Boolean
  #   end
  module TypeNames
    Types = ZeroRuby::Types
  end
end
