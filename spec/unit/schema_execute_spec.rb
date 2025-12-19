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

    mutation_result = result[:mutations][0]
    expect(mutation_result[:result][:error]).to eq("app")
    expect(mutation_result[:result][:message]).to match(/Unknown mutation/)
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
end
