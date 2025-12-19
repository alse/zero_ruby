# frozen_string_literal: true

require_relative "../test_helper"
require "json"

# Test schema for execute tests
class ExecuteTestMutation < ZeroRuby::Mutation
  argument :id, ZeroRuby::Types::String, required: true

  def execute(id:)
    # Just perform the mutation - no return value needed
  end
end

class ExecuteTestSchema < ZeroRuby::Schema
  mutation "test.create", handler: ExecuteTestMutation
end

class SchemaExecuteTest < Minitest::Test
  def setup
    @context = {current_user: OpenStruct.new(id: 42)}
    @lmid_store = ZeroRuby::TestHelpers::MockLmidStore.new
  end

  def test_execute_processes_valid_mutation
    push_data = {
      "pushVersion" => 1,
      "clientGroupID" => "group-1",
      "mutations" => [{
        "id" => 1,
        "clientID" => "client-1",
        "name" => "test.create",
        "args" => [{"id" => "item-123"}]
      }]
    }

    result = ExecuteTestSchema.execute(push_data, context: @context, lmid_store: @lmid_store)

    assert_equal 1, result[:mutations].length
    mutation_result = result[:mutations][0]
    assert_equal 1, mutation_result[:id][:id]
    assert_equal({}, mutation_result[:result])
  end

  def test_execute_handles_empty_mutations_array
    push_data = {
      "pushVersion" => 1,
      "clientGroupID" => "group-1",
      "mutations" => []
    }

    result = ExecuteTestSchema.execute(push_data, context: @context, lmid_store: @lmid_store)

    assert_equal({mutations: []}, result)
  end

  def test_execute_handles_missing_mutations_key
    push_data = {
      "pushVersion" => 1,
      "clientGroupID" => "group-1",
      "other" => "data"
    }

    result = ExecuteTestSchema.execute(push_data, context: @context, lmid_store: @lmid_store)

    assert_equal({mutations: []}, result)
  end

  def test_execute_processes_batch_of_mutations
    push_data = {
      "pushVersion" => 1,
      "clientGroupID" => "group-1",
      "mutations" => [
        {"id" => 1, "clientID" => "c1", "name" => "test.create", "args" => [{"id" => "a"}]},
        {"id" => 1, "clientID" => "c2", "name" => "test.create", "args" => [{"id" => "b"}]}
      ]
    }

    result = ExecuteTestSchema.execute(push_data, context: @context, lmid_store: @lmid_store)

    assert_equal 2, result[:mutations].length
    assert_equal({}, result[:mutations][0][:result])
    assert_equal({}, result[:mutations][1][:result])
  end

  def test_execute_returns_error_for_unknown_mutation
    push_data = {
      "pushVersion" => 1,
      "clientGroupID" => "group-1",
      "mutations" => [{
        "id" => 1,
        "clientID" => "client-1",
        "name" => "unknown.mutation",
        "args" => [{}]
      }]
    }

    result = ExecuteTestSchema.execute(push_data, context: @context, lmid_store: @lmid_store)

    mutation_result = result[:mutations][0]
    assert_equal "app", mutation_result[:result][:error]
    assert_match(/Unknown mutation/, mutation_result[:result][:message])
  end

  def test_execute_rejects_unsupported_push_version
    push_data = {
      "pushVersion" => 999,
      "clientGroupID" => "group-1",
      "mutations" => []
    }

    result = ExecuteTestSchema.execute(push_data, context: @context, lmid_store: @lmid_store)

    assert_equal "PushFailed", result[:error][:kind]
    assert_equal "UnsupportedPushVersion", result[:error][:reason]
    assert_match(/999/, result[:error][:message])
  end
end
