# frozen_string_literal: true

require "spec_helper"

# Test schema for execute tests
class ExecuteTestMutation < ZeroRuby::Mutation
  argument :id, ZeroRuby::Types::String

  def execute(**)
    transact { nil }
  end
end

class ExecuteTestSchema < ZeroRuby::Schema
  mutation "test.create", handler: ExecuteTestMutation
end

describe "Schema#execute" do
  let(:context) { {current_user: OpenStruct.new(id: 42)} }
  let(:lmid_store) { ZeroRuby::LmidStores::ActiveRecordStore.new }
  let(:success) { {} }

  it "processes valid mutation" do
    push_data = {
      "pushVersion" => 1,
      "clientGroupID" => "group-1",
      "mutations" => [{
        "id" => 1,
        "clientID" => "client-1",
        "name" => "test.create",
        "args" => [{"id" => "item-123"}]
      }],
      "timestamp" => 1703001234567,
      "requestID" => "req-001"
    }

    result = ExecuteTestSchema.execute(push_data, context: context, lmid_store: lmid_store)

    expect(result[:kind]).to eq("MutateResponse")
    expect(result[:userID]).to eq("42")
    expect(result[:mutations].length).to eq(1)
    mutation_result = result[:mutations][0]
    expect(mutation_result[:id][:id]).to eq(1)
    expect(mutation_result[:result]).to eq(success)
  end

  it "returns error for unknown mutation" do
    push_data = {
      "pushVersion" => 1,
      "clientGroupID" => "group-1",
      "mutations" => [{
        "id" => 1,
        "clientID" => "client-1",
        "name" => "unknown.mutation",
        "args" => [{}]
      }],
      "timestamp" => 1703001234567,
      "requestID" => "req-002"
    }

    result = ExecuteTestSchema.execute(push_data, context: context, lmid_store: lmid_store)

    expect(result[:kind]).to eq("MutateResponse")
    mutation_result = result[:mutations][0]
    expect(mutation_result[:result][:error]).to eq("app")
    expect(mutation_result[:result][:message]).to match(/could not find mutator/)
  end

  it "rejects unsupported push version" do
    push_data = {
      "pushVersion" => 999,
      "clientGroupID" => "group-1",
      "mutations" => [],
      "timestamp" => 1703001234567,
      "requestID" => "req-003"
    }

    result = ExecuteTestSchema.execute(push_data, context: context, lmid_store: lmid_store)

    expect(result[:kind]).to eq("PushFailed")
    expect(result[:origin]).to eq("server")
    expect(result[:reason]).to eq("unsupportedPushVersion")
    expect(result[:message]).to match(/999/)
    expect(result[:mutationIDs]).to eq([])
  end

  describe "userID extraction" do
    let(:push_data) do
      {
        "pushVersion" => 1,
        "clientGroupID" => "group-uid",
        "mutations" => [{
          "id" => 1,
          "clientID" => "client-uid",
          "name" => "test.create",
          "args" => [{"id" => "item-1"}]
        }],
        "timestamp" => 1703001234567,
        "requestID" => "req-uid"
      }
    end

    it "echoes user_id from explicit context[:user_id]" do
      result = ExecuteTestSchema.execute(
        push_data,
        context: {user_id: "user-123"},
        lmid_store: lmid_store
      )
      expect(result[:kind]).to eq("MutateResponse")
      expect(result[:userID]).to eq("user-123")
    end

    it "derives user_id from context[:current_user].id" do
      result = ExecuteTestSchema.execute(
        push_data,
        context: {current_user: OpenStruct.new(id: 42)},
        lmid_store: lmid_store
      )
      expect(result[:userID]).to eq("42")
    end

    it "prefers context[:user_id] over current_user.id" do
      result = ExecuteTestSchema.execute(
        push_data,
        context: {user_id: "explicit", current_user: OpenStruct.new(id: 99)},
        lmid_store: lmid_store
      )
      expect(result[:userID]).to eq("explicit")
    end

    it "omits userID when neither user_id nor current_user is set" do
      result = ExecuteTestSchema.execute(
        push_data,
        context: {},
        lmid_store: lmid_store
      )
      expect(result[:kind]).to eq("MutateResponse")
      expect(result).not_to have_key(:userID)
    end

    it "omits userID when current_user has nil id" do
      result = ExecuteTestSchema.execute(
        push_data,
        context: {current_user: OpenStruct.new(id: nil)},
        lmid_store: lmid_store
      )
      expect(result).not_to have_key(:userID)
    end
  end

  describe "upstream_schema sourcing" do
    let(:alt_schema) { "zero_test" }

    before do
      ZeroRuby::TestHelpers::DatabaseSetup.setup_schema!(alt_schema)
      ZeroRuby::TestHelpers::DatabaseSetup.truncate!(alt_schema)
    end

    it "routes LMID writes through context[:upstream_schema]" do
      push_data = {
        "pushVersion" => 1,
        "clientGroupID" => "group-alt",
        "mutations" => [{
          "id" => 1,
          "clientID" => "client-alt",
          "name" => "test.create",
          "args" => [{"id" => "item-1"}]
        }],
        "timestamp" => 1703001234567,
        "requestID" => "req-alt"
      }

      ExecuteTestSchema.execute(
        push_data,
        context: {upstream_schema: alt_schema},
        lmid_store: lmid_store
      )

      # LMID landed in the alternate schema
      alt_row = ActiveRecord::Base.connection.select_one(<<~SQL.squish)
        SELECT "lastMutationID" FROM #{alt_schema}.clients
        WHERE "clientGroupID" = 'group-alt' AND "clientID" = 'client-alt'
      SQL
      expect(alt_row).not_to be_nil
      expect(alt_row["lastMutationID"]).to eq(1)

      # Default schema is untouched
      default_row = ZeroRuby::ZeroClient.find_by(
        "clientGroupID" => "group-alt",
        "clientID" => "client-alt"
      )
      expect(default_row).to be_nil
    end

    it "defaults to zero_0 when context omits upstream_schema" do
      push_data = {
        "pushVersion" => 1,
        "clientGroupID" => "group-default",
        "mutations" => [{
          "id" => 1,
          "clientID" => "client-default",
          "name" => "test.create",
          "args" => [{"id" => "item-1"}]
        }],
        "timestamp" => 1703001234567,
        "requestID" => "req-default"
      }

      ExecuteTestSchema.execute(push_data, context: {}, lmid_store: lmid_store)

      default_row = ZeroRuby::ZeroClient.find_by(
        "clientGroupID" => "group-default",
        "clientID" => "client-default"
      )
      expect(default_row).not_to be_nil
      expect(default_row["lastMutationID"]).to eq(1)
    end
  end
end
