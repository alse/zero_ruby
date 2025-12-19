# frozen_string_literal: true

require_relative "zero_ruby/version"
require_relative "zero_ruby/configuration"
require_relative "zero_ruby/errors"

# Types (must be loaded before InputObject/Mutation which use them)
require_relative "zero_ruby/types/base_type"
require_relative "zero_ruby/types/string"
require_relative "zero_ruby/types/integer"
require_relative "zero_ruby/types/float"
require_relative "zero_ruby/types/boolean"
require_relative "zero_ruby/types/id"
require_relative "zero_ruby/types/big_int"
require_relative "zero_ruby/types/iso8601_date"
require_relative "zero_ruby/types/iso8601_date_time"

# Type name shortcuts (ID, Boolean, etc. without ZeroRuby::Types:: prefix)
# Must be loaded before InputObject/Mutation which include this module
require_relative "zero_ruby/type_names"

# Validators
require_relative "zero_ruby/validators/length_validator"
require_relative "zero_ruby/validators/numericality_validator"
require_relative "zero_ruby/validators/format_validator"
require_relative "zero_ruby/validators/inclusion_validator"
require_relative "zero_ruby/validators/exclusion_validator"
require_relative "zero_ruby/validators/allow_blank_validator"
require_relative "zero_ruby/validators/allow_null_validator"

# Core classes
require_relative "zero_ruby/argument"
require_relative "zero_ruby/validator"
require_relative "zero_ruby/input_object"
require_relative "zero_ruby/mutation"
require_relative "zero_ruby/schema"
require_relative "zero_ruby/typescript_generator"

# LMID (Last Mutation ID) Tracking
require_relative "zero_ruby/lmid_store"
require_relative "zero_ruby/lmid_stores/active_record_store"
require_relative "zero_ruby/push_processor"

# ZeroRuby - A Ruby gem for handling Zero mutations with type safety
#
# @example Basic usage with InputObject
#   # Define an input type
#   class Types::PostInput < ZeroRuby::InputObject
#     argument :id, ID, required: true
#     argument :title, String, required: true
#     argument :body, String, required: false
#   end
#
#   # Define a mutation
#   class Mutations::PostCreate < ZeroRuby::Mutation
#     argument :post_input, Types::PostInput, required: true
#     argument :notify, Boolean, required: false
#
#     def execute(post_input:, notify: false)
#       Post.create!(**post_input)
#       notify_subscribers if notify
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
  # Convenience method for quick type access
  module Types
    # Already defined in individual type files
  end
end
