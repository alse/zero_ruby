# frozen_string_literal: true

require "spec_helper"

# Test mutations for response format tests
class ResponseSuccessMutation < ZeroRuby::Mutation
  argument :id, ZeroRuby::Types::String

  def execute(**)
    transact { nil }
  end
end

class ResponseErrorMutation < ZeroRuby::Mutation
  argument :id, ZeroRuby::Types::String

  def execute(**)
    transact do
      raise ZeroRuby::Error.new("User not authorized to create posts")
    end
  end
end

class ResponseErrorWithDetailsMutation < ZeroRuby::Mutation
  argument :id, ZeroRuby::Types::String

  def execute(**)
    transact do
      raise ZeroRuby::Error.new("Post creation failed", details: {code: "RATE_LIMITED", retryAfter: 60})
    end
  end
end

class ResponseValidationMutation < ZeroRuby::Mutation
  argument :title, ZeroRuby::Types::String
  argument :body, ZeroRuby::Types::String.constrained(min_size: 10)

  def execute(**)
    transact { nil }
  end
end

class ResponseDataMutation < ZeroRuby::Mutation
  argument :id, ZeroRuby::Types::String

  def execute(id:)
    transact do
      {createdId: id, status: "created"}
    end
  end
end

class ResponseDatabaseErrorMutation < ZeroRuby::Mutation
  argument :id, ZeroRuby::Types::String

  def execute(**)
    transact do
      raise ZeroRuby::TransactionError.new("Connection lost to database")
    end
  end
end

class ResponseUnexpectedErrorMutation < ZeroRuby::Mutation
  argument :id, ZeroRuby::Types::String

  def execute(**)
    transact do
      raise "Unexpected kaboom"
    end
  end
end

class ResponseInternalErrorMutation < ZeroRuby::Mutation
  argument :id, ZeroRuby::Types::String

  def execute(**)
    transact do
      raise ZeroRuby::InternalError.new("Unexpected server error")
    end
  end
end

# Test schema for response format tests
class ResponseFormatSchema < ZeroRuby::Schema
  mutation "posts.create", handler: ResponseSuccessMutation
  mutation "posts.update", handler: ResponseSuccessMutation
  mutation "posts.error", handler: ResponseErrorMutation
  mutation "posts.errorWithDetails", handler: ResponseErrorWithDetailsMutation
  mutation "posts.validate", handler: ResponseValidationMutation
  mutation "posts.createWithData", handler: ResponseDataMutation
  mutation "posts.databaseError", handler: ResponseDatabaseErrorMutation
  mutation "posts.unexpectedError", handler: ResponseUnexpectedErrorMutation
  mutation "posts.internalError", handler: ResponseInternalErrorMutation
end

describe "Response Format Integration" do
  let(:context) { {} }
  let(:lmid_store) { ZeroRuby::LmidStores::ActiveRecordStore.new }

  def make_push(mutations, push_version: 1, client_group_id: "group-1")
    {
      "pushVersion" => push_version,
      "clientGroupID" => client_group_id,
      "mutations" => mutations,
      "timestamp" => 1703001234567,
      "requestID" => "req-#{SecureRandom.hex(4)}"
    }
  end

  describe "Top-level responses" do
    it "returns PushFailed for unsupported push version" do
      push_data = make_push([], push_version: 999)

      result = ResponseFormatSchema.execute(push_data, context: context, lmid_store: lmid_store)

      expect(result).to eq({
        kind: "PushFailed",
        origin: "server",
        reason: "unsupportedPushVersion",
        message: "Unsupported push version: 999. Expected: 1",
        mutationIDs: []
      })
    end

    it "returns PushFailed for out of order mutation" do
      # First, process mutation ID 1 to set up state
      setup_push = make_push([{
        "id" => 1,
        "clientID" => "client-abc",
        "name" => "posts.create",
        "args" => [{"id" => "post-1"}]
      }])
      ResponseFormatSchema.execute(setup_push, context: context, lmid_store: lmid_store)

      # Now send mutation ID 5 when expected is 2
      push_data = make_push([
        {
          "id" => 5,
          "clientID" => "client-abc",
          "name" => "posts.create",
          "args" => [{"id" => "post-5"}]
        },
        {
          "id" => 6,
          "clientID" => "client-abc",
          "name" => "posts.update",
          "args" => [{"id" => "post-6"}]
        }
      ])

      result = ResponseFormatSchema.execute(push_data, context: context, lmid_store: lmid_store)

      expect(result).to eq({
        kind: "PushFailed",
        origin: "server",
        reason: "oooMutation",
        message: "Client client-abc sent mutation ID 5 but expected 2",
        mutationIDs: [
          {id: 5, clientID: "client-abc"},
          {id: 6, clientID: "client-abc"}
        ]
      })
    end

    it "returns PushFailed for malformed push data (not a hash)" do
      result = ResponseFormatSchema.execute("invalid", context: context, lmid_store: lmid_store)

      expect(result).to eq({
        kind: "PushFailed",
        origin: "server",
        reason: "parse",
        message: "Push data must be a hash",
        mutationIDs: []
      })
    end

    it "returns PushFailed for missing clientGroupID" do
      push_data = {"pushVersion" => 1, "mutations" => [], "timestamp" => 123, "requestID" => "req-1"}

      result = ResponseFormatSchema.execute(push_data, context: context, lmid_store: lmid_store)

      expect(result).to eq({
        kind: "PushFailed",
        origin: "server",
        reason: "parse",
        message: "Missing required field: clientGroupID",
        mutationIDs: []
      })
    end

    it "returns PushFailed for missing timestamp" do
      push_data = {"pushVersion" => 1, "clientGroupID" => "group-1", "mutations" => [], "requestID" => "req-1"}

      result = ResponseFormatSchema.execute(push_data, context: context, lmid_store: lmid_store)

      expect(result).to eq({
        kind: "PushFailed",
        origin: "server",
        reason: "parse",
        message: "Missing required field: timestamp",
        mutationIDs: []
      })
    end

    it "returns PushFailed for missing requestID" do
      push_data = {"pushVersion" => 1, "clientGroupID" => "group-1", "mutations" => [], "timestamp" => 123}

      result = ResponseFormatSchema.execute(push_data, context: context, lmid_store: lmid_store)

      expect(result).to eq({
        kind: "PushFailed",
        origin: "server",
        reason: "parse",
        message: "Missing required field: requestID",
        mutationIDs: []
      })
    end

    it "returns PushFailed when mutations is not an array" do
      push_data = {
        "pushVersion" => 1,
        "clientGroupID" => "group-1",
        "mutations" => "invalid",
        "timestamp" => 123,
        "requestID" => "req-1"
      }

      result = ResponseFormatSchema.execute(push_data, context: context, lmid_store: lmid_store)

      expect(result).to eq({
        kind: "PushFailed",
        origin: "server",
        reason: "parse",
        message: "Field 'mutations' must be an array",
        mutationIDs: []
      })
    end
  end

  describe "Mutation results" do
    it "returns success result" do
      push_data = make_push([{
        "id" => 1,
        "clientID" => "client-abc",
        "name" => "posts.create",
        "args" => [{"id" => "post-1"}]
      }])

      result = ResponseFormatSchema.execute(push_data, context: context, lmid_store: lmid_store)

      expect(result).to eq({
        mutations: [
          {id: {id: 1, clientID: "client-abc"}, result: {}}
        ]
      })
    end

    it "returns success result with data" do
      push_data = make_push([{
        "id" => 1,
        "clientID" => "client-abc",
        "name" => "posts.createWithData",
        "args" => [{"id" => "post-1"}]
      }])

      result = ResponseFormatSchema.execute(push_data, context: context, lmid_store: lmid_store)

      expect(result).to eq({
        mutations: [
          {
            id: {id: 1, clientID: "client-abc"},
            result: {data: {createdId: "post-1", status: "created"}}
          }
        ]
      })
    end

    it "returns application error (generic)" do
      push_data = make_push([{
        "id" => 1,
        "clientID" => "client-abc",
        "name" => "posts.error",
        "args" => [{"id" => "post-1"}]
      }])

      result = ResponseFormatSchema.execute(push_data, context: context, lmid_store: lmid_store)

      expect(result).to eq({
        mutations: [
          {
            id: {id: 1, clientID: "client-abc"},
            result: {
              error: "app",
              message: "User not authorized to create posts"
            }
          }
        ]
      })
    end

    it "returns application error (with details)" do
      push_data = make_push([{
        "id" => 1,
        "clientID" => "client-abc",
        "name" => "posts.errorWithDetails",
        "args" => [{"id" => "post-1"}]
      }])

      result = ResponseFormatSchema.execute(push_data, context: context, lmid_store: lmid_store)

      expect(result).to eq({
        mutations: [
          {
            id: {id: 1, clientID: "client-abc"},
            result: {
              error: "app",
              message: "Post creation failed",
              details: {code: "RATE_LIMITED", retryAfter: 60}
            }
          }
        ]
      })
    end

    it "returns validation error" do
      push_data = make_push([{
        "id" => 1,
        "clientID" => "client-abc",
        "name" => "posts.validate",
        "args" => [{}]  # Missing required title and body
      }])

      result = ResponseFormatSchema.execute(push_data, context: context, lmid_store: lmid_store)

      expect(result).to eq({
        mutations: [
          {
            id: {id: 1, clientID: "client-abc"},
            result: {
              error: "app",
              message: "title is required, body is required",
              details: {
                messages: ["title is required", "body is required"]
              }
            }
          }
        ]
      })
    end

    it "returns already processed error" do
      # First, process mutation ID 3
      setup_push = make_push([
        {"id" => 1, "clientID" => "client-abc", "name" => "posts.create", "args" => [{"id" => "p1"}]},
        {"id" => 2, "clientID" => "client-abc", "name" => "posts.create", "args" => [{"id" => "p2"}]},
        {"id" => 3, "clientID" => "client-abc", "name" => "posts.create", "args" => [{"id" => "p3"}]},
        {"id" => 4, "clientID" => "client-abc", "name" => "posts.create", "args" => [{"id" => "p4"}]},
        {"id" => 5, "clientID" => "client-abc", "name" => "posts.create", "args" => [{"id" => "p5"}]}
      ])
      ResponseFormatSchema.execute(setup_push, context: context, lmid_store: lmid_store)

      # Now try to process mutation ID 3 again (already processed, last was 5)
      push_data = make_push([{
        "id" => 3,
        "clientID" => "client-abc",
        "name" => "posts.create",
        "args" => [{"id" => "post-3"}]
      }])

      result = ResponseFormatSchema.execute(push_data, context: context, lmid_store: lmid_store)

      expect(result).to eq({
        mutations: [
          {
            id: {id: 3, clientID: "client-abc"},
            result: {
              error: "alreadyProcessed",
              details: "Mutation 3 already processed for client client-abc. Last mutation ID: 5"
            }
          }
        ]
      })
    end

    it "returns mutation not found error" do
      push_data = make_push([{
        "id" => 1,
        "clientID" => "client-abc",
        "name" => "posts.delete",
        "args" => [{}]
      }])

      result = ResponseFormatSchema.execute(push_data, context: context, lmid_store: lmid_store)

      expect(result).to eq({
        mutations: [
          {
            id: {id: 1, clientID: "client-abc"},
            result: {
              error: "app",
              message: "Unknown mutation: posts.delete"
            }
          }
        ]
      })
    end

    it "returns mixed batch results" do
      # Note: Each mutation uses a different clientID because the LMID is tracked
      # per-client, and failed mutations roll back their LMID increment
      push_data = make_push([
        {
          "id" => 1,
          "clientID" => "client-1",
          "name" => "posts.create",
          "args" => [{"id" => "post-1"}]
        },
        {
          "id" => 1,
          "clientID" => "client-2",
          "name" => "posts.validate",
          "args" => [{}]  # Will fail validation - missing title
        },
        {
          "id" => 1,
          "clientID" => "client-3",
          "name" => "posts.create",
          "args" => [{"id" => "post-3"}]
        }
      ])

      result = ResponseFormatSchema.execute(push_data, context: context, lmid_store: lmid_store)

      expect(result).to eq({
        mutations: [
          {id: {id: 1, clientID: "client-1"}, result: {}},
          {
            id: {id: 1, clientID: "client-2"},
            result: {
              error: "app",
              message: "title is required, body is required",
              details: {messages: ["title is required", "body is required"]}
            }
          },
          {id: {id: 1, clientID: "client-3"}, result: {}}
        ]
      })
    end

    it "returns PushFailed for database failures" do
      push_data = make_push([{
        "id" => 1,
        "clientID" => "client-abc",
        "name" => "posts.databaseError",
        "args" => [{"id" => "post-1"}]
      }])

      result = ResponseFormatSchema.execute(push_data, context: context, lmid_store: lmid_store)

      expect(result).to eq({
        kind: "PushFailed",
        origin: "server",
        reason: "database",
        message: "Connection lost to database",
        mutationIDs: [{id: 1, clientID: "client-abc"}]
      })
    end

    it "wraps unexpected errors as TransactionError" do
      push_data = make_push([{
        "id" => 1,
        "clientID" => "client-abc",
        "name" => "posts.unexpectedError",
        "args" => [{"id" => "post-1"}]
      }])

      result = ResponseFormatSchema.execute(push_data, context: context, lmid_store: lmid_store)

      expect(result).to eq({
        kind: "PushFailed",
        origin: "server",
        reason: "database",
        message: "Transaction failed: Unexpected kaboom",
        mutationIDs: [{id: 1, clientID: "client-abc"}]
      })
    end

    it "returns app error for unexpected exceptions" do
      push_data = make_push([{
        "id" => 1,
        "clientID" => "client-abc",
        "name" => "posts.internalError",
        "args" => [{"id" => "post-1"}]
      }])

      result = ResponseFormatSchema.execute(push_data, context: context, lmid_store: lmid_store)

      expect(result).to eq({
        mutations: [
          {
            id: {id: 1, clientID: "client-abc"},
            result: {
              error: "app",
              message: "Unexpected server error"
            }
          }
        ]
      })
    end
  end
end
