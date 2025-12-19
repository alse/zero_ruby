# frozen_string_literal: true

# Example controller for handling Zero push requests.
# Mount this at POST /zero/push (mutations) and GET /zero/push (types) in your routes.
#
# @example routes.rb
#   match "/zero/push", to: "zero#push", via: [:get, :post]
class ZeroController < ApplicationController
  # Skip CSRF for API endpoint
  # skip_before_action :verify_authenticity_token

  def push
    if request.get?
      # GET requests return TypeScript type definitions
      render plain: ZeroSchema.to_typescript, content_type: "text/plain; charset=utf-8"
    else
      # POST requests process mutations
      body = JSON.parse(request.body.read)

      # Build context hash with whatever your mutations need.
      # Access in mutations via ctx[:current_user], ctx[:request_id], etc.
      context = {
        current_user: current_user,
        request_id: request.request_id
      }

      result = ZeroSchema.execute(body, context: context)
      render json: result
    end
  rescue JSON::ParserError => e
    render json: {
      error: {
        kind: "PushFailed",
        reason: "Parse",
        message: "Invalid JSON: #{e.message}"
      }
    }, status: :bad_request
  end
end
