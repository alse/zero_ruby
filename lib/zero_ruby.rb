# frozen_string_literal: true

require_relative "zero_ruby/version"
require_relative "zero_ruby/configuration"
require_relative "zero_ruby/errors"

# Types module (dry-types based)
require_relative "zero_ruby/types"

# Provides Types constant for accessing ZeroRuby::Types
require_relative "zero_ruby/type_names"

# Core classes
require_relative "zero_ruby/input_object"
require_relative "zero_ruby/mutation"
require_relative "zero_ruby/schema"
require_relative "zero_ruby/typescript_generator"

# LMID (Last Mutation ID) Tracking
require_relative "zero_ruby/lmid_store"
require_relative "zero_ruby/lmid_stores/active_record_store"
require_relative "zero_ruby/zero_client"
require_relative "zero_ruby/push_processor"

# ZeroRuby - A Ruby gem for handling Zero mutations with type safety
#
# @example Basic usage with InputObject
#   # Define an input type
#   class Types::PostInput < ZeroRuby::InputObject
#     argument :id, ZeroRuby::Types::ID
#     argument :title, ZeroRuby::Types::String.constrained(min_size: 1, max_size: 200)
#     argument :body, ZeroRuby::Types::String.optional
#   end
#
#   # Define a mutation
#   class Mutations::PostCreate < ZeroRuby::Mutation
#     argument :post_input, Types::PostInput
#     argument :notify, ZeroRuby::Types::Boolean.default(false)
#
#     def execute
#       Post.create!(**args[:post_input])
#       notify_subscribers if args[:notify]
#     end
#   end
#
#   # Register in schema
#   class ZeroSchema < ZeroRuby::Schema
#     mutation "posts.create", handler: Mutations::PostCreate
#   end
#
#   # Use in controller (Rails example)
#   class ZeroController < ApplicationController
#     def push
#       if request.get?
#         render plain: ZeroSchema.to_typescript, content_type: "text/plain"
#       else
#         body = JSON.parse(request.body.read)
#         result = ZeroSchema.execute(body, context: {current_user: current_user})
#         render json: result
#       end
#     end
#   end
module ZeroRuby
end
