# frozen_string_literal: true

require "spec_helper"

# Integration coverage for the current zero-cache wire contract, pinned
# against the reference implementation (zero-server/src/process-mutations.ts
# and the zero-protocol schemas). Last verified against tag zero/v1.8.0 —
# update this note when re-verifying per AGENTS.md.
class WireCompatSuccessMutation < ZeroRuby::Mutation
  argument :id, ZeroRuby::Types::String

  def execute(**)
    nil
  end
end

class WireCompatDbErrorMutation < ZeroRuby::Mutation
  argument :id, ZeroRuby::Types::String

  def execute(**)
    raise ZeroRuby::TransactionError.new("Deadlock detected", details: {retryable: true})
  end
end

class WireCompatAppErrorMutation < ZeroRuby::Mutation
  argument :id, ZeroRuby::Types::String

  def execute(**)
    raise ZeroRuby::Error.new("boom", details: {code: "E1"})
  end
end

class WireCompatSchema < ZeroRuby::Schema
  mutation "posts.create", handler: WireCompatSuccessMutation
  mutation "posts.dbError", handler: WireCompatDbErrorMutation
  mutation "posts.appError", handler: WireCompatAppErrorMutation
end

describe "Zero wire compatibility" do
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

  def get_lmid(client_group_id, client_id)
    ZeroRuby::ZeroClient.find_by(
      "clientGroupID" => client_group_id,
      "clientID" => client_id
    )&.[]("lastMutationID")
  end

  describe "unknown mutations" do
    it "advances the LMID and persists the app error result (client must not resend forever)" do
      push_data = make_push([
        {"id" => 1, "clientID" => "client-1", "name" => "posts.nope", "args" => [{}]}
      ])

      result = WireCompatSchema.execute(push_data, context: {}, lmid_store: lmid_store)

      expect(result).to eq({
        kind: "MutateResponse",
        mutations: [{
          id: {id: 1, clientID: "client-1"},
          result: {error: "app", message: "could not find mutator posts.nope"}
        }]
      })
      expect(get_lmid("group-1", "client-1")).to eq(1)
      persisted = get_mutation_result("group-1", "client-1", 1)
      expect(JSON.parse(persisted)).to eq({"error" => "app", "message" => "could not find mutator posts.nope"})
    end

    it "continues the batch after an unknown mutation" do
      push_data = make_push([
        {"id" => 1, "clientID" => "client-1", "name" => "posts.nope", "args" => [{}]},
        {"id" => 2, "clientID" => "client-1", "name" => "posts.create", "args" => [{"id" => "a"}]}
      ])

      result = WireCompatSchema.execute(push_data, context: {}, lmid_store: lmid_store)

      expect(result[:mutations].length).to eq(2)
      expect(result[:mutations][1][:result]).to eq({})
      expect(get_lmid("group-1", "client-1")).to eq(2)
    end
  end

  describe "redelivery after a lost response" do
    # zero-cache resends a mutation whenever it never received the response.
    # The reference (Transactor#transact) answers the resend with a
    # per-mutation alreadyProcessed result so the mutation gets resolved;
    # a top-level PushFailed would make zero-cache retry the same mutation
    # forever, permanently wedging the client group.

    it "answers a redelivered unknown mutation with alreadyProcessed and continues the batch" do
      first = make_push([
        {"id" => 1, "clientID" => "client-1", "name" => "posts.nope", "args" => [{}]}
      ])
      WireCompatSchema.execute(first, context: {}, lmid_store: lmid_store)
      expect(get_lmid("group-1", "client-1")).to eq(1)

      redelivery = make_push([
        {"id" => 1, "clientID" => "client-1", "name" => "posts.nope", "args" => [{}]},
        {"id" => 2, "clientID" => "client-1", "name" => "posts.create", "args" => [{"id" => "a"}]}
      ])
      result = WireCompatSchema.execute(redelivery, context: {}, lmid_store: lmid_store)

      expect(result[:kind]).to eq("MutateResponse")
      expect(result[:mutations][0]).to eq({
        id: {id: 1, clientID: "client-1"},
        result: {
          error: "alreadyProcessed",
          details: "Ignoring mutation from client-1 with ID 1 as it was already processed. Expected: 2"
        }
      })
      expect(result[:mutations][1][:result]).to eq({})
      expect(get_lmid("group-1", "client-1")).to eq(2)
    end

    it "answers a redelivered validation failure with alreadyProcessed" do
      bad_args = make_push([
        {"id" => 1, "clientID" => "client-1", "name" => "posts.create", "args" => [{}]}
      ])

      first = WireCompatSchema.execute(bad_args, context: {}, lmid_store: lmid_store)
      expect(first[:mutations][0][:result][:error]).to eq("app")
      expect(get_lmid("group-1", "client-1")).to eq(1)

      result = WireCompatSchema.execute(bad_args, context: {}, lmid_store: lmid_store)

      expect(result[:kind]).to eq("MutateResponse")
      expect(result[:mutations][0][:result]).to eq({
        error: "alreadyProcessed",
        details: "Ignoring mutation from client-1 with ID 1 as it was already processed. Expected: 2"
      })
      expect(get_lmid("group-1", "client-1")).to eq(1)
    end
  end

  describe "ambient ActiveRecord transactions" do
    # Apps sometimes call Schema.execute from inside an open transaction
    # (around_action, service objects, transactional test fixtures). The
    # per-mutation transaction must still roll back independently, like the
    # reference's connection-owned transactions do.
    it "preserves rollback and LMID semantics when execute runs inside an app transaction" do
      push_data = make_push([
        {"id" => 1, "clientID" => "client-1", "name" => "posts.appError", "args" => [{"id" => "a"}]}
      ])

      result = nil
      ActiveRecord::Base.transaction do
        result = WireCompatSchema.execute(push_data, context: {}, lmid_store: lmid_store)
      end

      expect(result[:mutations][0][:result]).to eq({error: "app", message: "boom", details: {code: "E1"}})
      expect(get_lmid("group-1", "client-1")).to eq(1)
      persisted = get_mutation_result("group-1", "client-1", 1)
      expect(JSON.parse(persisted)).to eq({"error" => "app", "message" => "boom", "details" => {"code" => "E1"}})
    end
  end

  describe "userID echo" do
    let(:push_data) { make_push([{"id" => 1, "clientID" => "client-1", "name" => "posts.create", "args" => [{"id" => "a"}]}]) }

    it "omits userID when no identity was provided (zero-cache falls back to client identity)" do
      result = WireCompatSchema.execute(push_data, context: {}, lmid_store: lmid_store)
      expect(result).not_to have_key(:userID)
    end

    it "echoes the current_user id as a string" do
      result = WireCompatSchema.execute(push_data, context: {current_user: OpenStruct.new(id: 42)}, lmid_store: lmid_store)
      expect(result[:userID]).to eq("42")
    end

    it "echoes an explicit user_id" do
      result = WireCompatSchema.execute(push_data, context: {user_id: "jwt-sub-9"}, lmid_store: lmid_store)
      expect(result[:userID]).to eq("jwt-sub-9")
    end

    it "echoes an explicit nil user_id as null (server-validated logged out)" do
      result = WireCompatSchema.execute(push_data, context: {user_id: nil}, lmid_store: lmid_store)
      expect(result).to have_key(:userID)
      expect(result[:userID]).to be_nil
    end

    it "omits userID when current_user is present but has no id" do
      result = WireCompatSchema.execute(push_data, context: {current_user: OpenStruct.new(id: nil)}, lmid_store: lmid_store)
      expect(result).not_to have_key(:userID)
    end
  end

  describe "push body parsing (pushBodySchema strictness)" do
    it "rejects non-numeric mutation ids" do
      push_data = make_push([{"id" => "one", "clientID" => "client-1", "name" => "posts.create", "args" => [{}]}])

      result = WireCompatSchema.execute(push_data, context: {}, lmid_store: lmid_store)

      expect(result[:kind]).to eq("PushFailed")
      expect(result[:reason]).to eq("parse")
      expect(result[:message]).to eq("Failed to parse push body: mutation field 'id' must be a number")
    end

    it "rejects non-array args" do
      push_data = make_push([{"id" => 1, "clientID" => "client-1", "name" => "posts.create", "args" => {"id" => "a"}}])

      result = WireCompatSchema.execute(push_data, context: {}, lmid_store: lmid_store)

      expect(result[:kind]).to eq("PushFailed")
      expect(result[:reason]).to eq("parse")
      expect(result[:message]).to eq("Failed to parse push body: mutation field 'args' must be an array")
    end

    it "rejects non-string clientGroupID" do
      push_data = make_push([])
      push_data["clientGroupID"] = 123

      result = WireCompatSchema.execute(push_data, context: {}, lmid_store: lmid_store)

      expect(result[:kind]).to eq("PushFailed")
      expect(result[:reason]).to eq("parse")
      expect(result[:message]).to eq("Failed to parse push body: field 'clientGroupID' must be a string")
    end

    it "tolerates unknown extra fields (passthrough parsing)" do
      push_data = make_push([{"type" => "custom", "id" => 1, "clientID" => "client-1", "name" => "posts.create", "args" => [{"id" => "a"}], "timestamp" => 1703001234567}])
      push_data["schemaVersion"] = 3
      push_data["auth"] = "deprecated-token"
      push_data["traceparent"] = "00-abc-def-01"

      result = WireCompatSchema.execute(push_data, context: {}, lmid_store: lmid_store)

      expect(result[:kind]).to eq("MutateResponse")
      expect(result[:mutations][0][:result]).to eq({})
    end
  end

  describe "unsupported push version" do
    it "uses the reference message format" do
      push_data = make_push([{"id" => 1, "clientID" => "client-1", "name" => "posts.create", "args" => [{}]}], push_version: 2)

      result = WireCompatSchema.execute(push_data, context: {}, lmid_store: lmid_store)

      expect(result).to eq({
        kind: "PushFailed",
        origin: "server",
        reason: "unsupportedPushVersion",
        message: "Unsupported push version: 2",
        mutationIDs: [{id: 1, clientID: "client-1"}]
      })
    end
  end

  describe "PushFailed details" do
    it "includes error details in database failures" do
      push_data = make_push([{"id" => 1, "clientID" => "client-1", "name" => "posts.dbError", "args" => [{"id" => "a"}]}])

      result = WireCompatSchema.execute(push_data, context: {}, lmid_store: lmid_store)

      expect(result[:kind]).to eq("PushFailed")
      expect(result[:reason]).to eq("database")
      expect(result[:details]).to eq({retryable: true})
    end
  end

  describe "_zero_cleanupResults argument validation (cleanupResultsArgSchema)" do
    def cleanup_push(args)
      make_push([{
        "type" => "custom",
        "id" => 0,
        "clientID" => "client-1",
        "name" => "_zero_cleanupResults",
        "args" => [args],
        "timestamp" => 1703001234567
      }])
    end

    before do
      insert_mutation_result("group-1", "client-1", 1, {error: "app", message: "e1"})
      insert_mutation_result("group-1", "client-1", 2, {error: "app", message: "e2"})
      insert_mutation_result("group-1", "client-2", 1, {error: "app", message: "e3"})
    end

    it "deletes results for the legacy single shape" do
      result = WireCompatSchema.execute(cleanup_push({"clientGroupID" => "group-1", "clientID" => "client-1", "upToMutationID" => 1}), context: {}, lmid_store: lmid_store)

      expect(result).to eq({kind: "MutateResponse", mutations: []})
      expect(get_mutation_result("group-1", "client-1", 1)).to be_nil
      expect(get_mutation_result("group-1", "client-1", 2)).not_to be_nil
      expect(get_mutation_result("group-1", "client-2", 1)).not_to be_nil
    end

    it "deletes all results for listed clients in the bulk shape" do
      result = WireCompatSchema.execute(cleanup_push({"type" => "bulk", "clientGroupID" => "group-1", "clientIDs" => ["client-1"]}), context: {}, lmid_store: lmid_store)

      expect(result).to eq({kind: "MutateResponse", mutations: []})
      expect(get_mutation_result("group-1", "client-1", 1)).to be_nil
      expect(get_mutation_result("group-1", "client-1", 2)).to be_nil
      expect(get_mutation_result("group-1", "client-2", 1)).not_to be_nil
    end

    it "skips bulk cleanup with an empty clientIDs list (schema requires at least one)" do
      expect {
        result = WireCompatSchema.execute(cleanup_push({"type" => "bulk", "clientGroupID" => "group-1", "clientIDs" => []}), context: {}, lmid_store: lmid_store)
        expect(result).to eq({kind: "MutateResponse", mutations: []})
      }.to output(/invalid args/).to_stderr

      expect(get_mutation_result("group-1", "client-1", 1)).not_to be_nil
    end

    it "skips cleanup with an unknown type value" do
      expect {
        WireCompatSchema.execute(cleanup_push({"type" => "everything", "clientGroupID" => "group-1"}), context: {}, lmid_store: lmid_store)
      }.to output(/invalid args/).to_stderr

      expect(get_mutation_result("group-1", "client-1", 1)).not_to be_nil
    end

    it "skips cleanup args carrying unknown extra keys (valita strict mode)" do
      expect {
        WireCompatSchema.execute(cleanup_push({"clientGroupID" => "group-1", "clientID" => "client-1", "upToMutationID" => 5, "extra" => true}), context: {}, lmid_store: lmid_store)
      }.to output(/invalid args/).to_stderr

      expect(get_mutation_result("group-1", "client-1", 1)).not_to be_nil
    end

    it "skips single cleanup missing upToMutationID" do
      expect {
        WireCompatSchema.execute(cleanup_push({"clientGroupID" => "group-1", "clientID" => "client-1"}), context: {}, lmid_store: lmid_store)
      }.to output(/invalid args/).to_stderr

      expect(get_mutation_result("group-1", "client-1", 1)).not_to be_nil
    end
  end
end
