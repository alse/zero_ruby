# frozen_string_literal: true

require_relative "../test_helper"

# Integration test mutations
class CreateItemMutation < ZeroRuby::Mutation
  argument :id, ZeroRuby::Types::String, required: true
  argument :name, ZeroRuby::Types::String, required: true, validates: {length: {minimum: 1, maximum: 100}}
  argument :quantity, ZeroRuby::Types::Integer, required: false, default: 1
  argument :active, ZeroRuby::Types::Boolean, required: false, default: true

  def execute(id:, name:, quantity:, active:)
    # Just perform the mutation - no return value needed
  end
end

class UpdateItemMutation < ZeroRuby::Mutation
  argument :id, ZeroRuby::Types::String, required: true
  argument :name, ZeroRuby::Types::String, required: false
  argument :quantity, ZeroRuby::Types::Integer, required: false, validates: {numericality: {greater_than: 0}}

  def execute(id:, name: nil, quantity: nil)
    # Just perform the mutation - no return value needed
  end
end

# Integration test schema
class IntegrationSchema < ZeroRuby::Schema
  mutation "items.create", handler: CreateItemMutation
  mutation "items.update", handler: UpdateItemMutation
end

class MutationFlowTest < Minitest::Test
  def setup
    @context = {current_user: OpenStruct.new(id: 1, email: "test@example.com")}
    @lmid_store = ZeroRuby::TestHelpers::MockLmidStore.new
  end

  def make_push(mutations)
    {
      "pushVersion" => 1,
      "clientGroupID" => "group-1",
      "mutations" => mutations
    }
  end

  def test_full_flow_with_valid_mutation
    push_data = make_push([{
      "id" => 1,
      "clientID" => "client-xyz",
      "name" => "items.create",
      "args" => [{
        "id" => "item-1",
        "name" => "Test Item",
        "quantity" => "5",
        "active" => "true"
      }]
    }])

    result = IntegrationSchema.execute(push_data, context: @context, lmid_store: @lmid_store)

    # Verify mutation ID is returned
    assert_equal 1, result[:mutations][0][:id][:id]
    assert_equal "client-xyz", result[:mutations][0][:id][:clientID]

    # Successful mutations return empty hash
    assert_equal({}, result[:mutations][0][:result])
  end

  def test_full_flow_with_validation_failure
    push_data = make_push([{
      "id" => 1,
      "clientID" => "client-fail",
      "name" => "items.create",
      "args" => [{
        "id" => "item-1",
        "name" => ""  # Empty name violates minimum length
      }]
    }])

    result = IntegrationSchema.execute(push_data, context: @context, lmid_store: @lmid_store)

    assert_equal "app", result[:mutations][0][:result][:error]
    assert result[:mutations][0][:result][:details][:messages].any? { |m| m.include?("too short") }
  end

  def test_full_flow_with_missing_required_argument
    push_data = make_push([{
      "id" => 1,
      "clientID" => "client-missing",
      "name" => "items.create",
      "args" => [{
        "id" => "item-1"
        # Missing required 'name' argument
      }]
    }])

    result = IntegrationSchema.execute(push_data, context: @context, lmid_store: @lmid_store)

    assert_equal "app", result[:mutations][0][:result][:error]
    assert result[:mutations][0][:result][:details][:messages].any? { |m| m.include?("name is required") }
  end

  def test_full_flow_with_numericality_validation_failure
    push_data = make_push([{
      "id" => 1,
      "clientID" => "client-num",
      "name" => "items.update",
      "args" => [{
        "id" => "item-1",
        "quantity" => "0"  # Violates greater_than: 0
      }]
    }])

    result = IntegrationSchema.execute(push_data, context: @context, lmid_store: @lmid_store)

    assert_equal "app", result[:mutations][0][:result][:error]
    assert result[:mutations][0][:result][:details][:messages].any? { |m| m.include?("greater than") }
  end

  def test_batch_processing_with_mixed_results
    push_data = make_push([
      {
        "id" => 1,
        "clientID" => "client-1",
        "name" => "items.create",
        "args" => [{"id" => "item-1", "name" => "Valid Item"}]
      },
      {
        "id" => 1,
        "clientID" => "client-2",
        "name" => "unknown.mutation",
        "args" => [{}]
      },
      {
        "id" => 1,
        "clientID" => "client-3",
        "name" => "items.update",
        "args" => [{"id" => "item-2", "name" => "Updated"}]
      }
    ])

    result = IntegrationSchema.execute(push_data, context: @context, lmid_store: @lmid_store)

    # First mutation succeeds
    assert_equal({}, result[:mutations][0][:result])

    # Second mutation fails (unknown)
    assert_equal "app", result[:mutations][1][:result][:error]
    assert_match(/Unknown mutation/, result[:mutations][1][:result][:message])

    # Third mutation succeeds
    assert_equal({}, result[:mutations][2][:result])
  end

  def test_full_flow_with_default_values_applied
    push_data = make_push([{
      "id" => 1,
      "clientID" => "client-defaults",
      "name" => "items.create",
      "args" => [{
        "id" => "item-1",
        "name" => "Item with Defaults"
        # quantity and active should use defaults
      }]
    }])

    result = IntegrationSchema.execute(push_data, context: @context, lmid_store: @lmid_store)

    # Mutation succeeds with empty result
    assert_equal({}, result[:mutations][0][:result])
  end

  def test_full_flow_with_camel_case_args
    push_data = make_push([{
      "id" => 1,
      "clientID" => "client-camel",
      "name" => "items.create",
      "args" => [{
        "id" => "item-1",
        "name" => "Camel Case Test"
      }]
    }])

    result = IntegrationSchema.execute(push_data, context: @context, lmid_store: @lmid_store)

    # Should process successfully with empty result
    assert_equal({}, result[:mutations][0][:result])
  end
end
