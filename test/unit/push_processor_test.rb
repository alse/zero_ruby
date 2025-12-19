# frozen_string_literal: true

require_relative "../test_helper"

# Test mutation that succeeds
class SuccessMutation < ZeroRuby::Mutation
  argument :id, ZeroRuby::Types::String, required: true

  def execute(id:)
    # Success - return empty hash
  end
end

# Test mutation that raises Error (will be retried)
class RetryableMutation < ZeroRuby::Mutation
  argument :id, ZeroRuby::Types::String, required: true

  @@call_count = 0

  def self.reset_count!
    @@call_count = 0
  end

  def self.call_count
    @@call_count
  end

  def execute(id:)
    @@call_count += 1
    if @@call_count < 3
      raise ZeroRuby::Error.new("Temporary error")
    end
    # Third call succeeds
  end
end

# Test mutation that always fails
class FailingMutation < ZeroRuby::Mutation
  argument :id, ZeroRuby::Types::String, required: true

  def execute(id:)
    raise ZeroRuby::Error.new("Permanent error", details: {code: "ERR001"})
  end
end

# Schema for push processor tests
class PushSchema < ZeroRuby::Schema
  mutation "items.create", handler: SuccessMutation
  mutation "items.retry", handler: RetryableMutation
  mutation "items.fail", handler: FailingMutation
end

class PushProcessorTest < Minitest::Test
  def setup
    @store = ZeroRuby::TestHelpers::MockLmidStore.new
    @processor = ZeroRuby::PushProcessor.new(
      schema: PushSchema,
      lmid_store: @store,
      max_retries: 3
    )
    @context = {current_user: OpenStruct.new(id: 1)}
    RetryableMutation.reset_count!
  end

  def test_accepts_supported_push_version
    push_data = {
      "pushVersion" => 1,
      "clientGroupID" => "group-1",
      "mutations" => []
    }

    result = @processor.process(push_data, @context)
    assert_equal({mutations: []}, result)
  end

  def test_processes_first_mutation_for_new_client
    push_data = {
      "pushVersion" => 1,
      "clientGroupID" => "group-1",
      "mutations" => [
        {"id" => 1, "clientID" => "client-1", "name" => "items.create", "args" => [{"id" => "item-1"}]}
      ]
    }

    result = @processor.process(push_data, @context)

    assert_equal 1, result[:mutations].length
    assert_equal({id: 1, clientID: "client-1"}, result[:mutations][0][:id])
    assert_equal({}, result[:mutations][0][:result])

    # LMID should be updated
    assert_equal 1, @store.fetch_with_lock("group-1", "client-1")
  end

  def test_processes_sequential_mutations
    push_data = {
      "pushVersion" => 1,
      "clientGroupID" => "group-1",
      "mutations" => [
        {"id" => 1, "clientID" => "client-1", "name" => "items.create", "args" => [{"id" => "item-1"}]},
        {"id" => 2, "clientID" => "client-1", "name" => "items.create", "args" => [{"id" => "item-2"}]},
        {"id" => 3, "clientID" => "client-1", "name" => "items.create", "args" => [{"id" => "item-3"}]}
      ]
    }

    result = @processor.process(push_data, @context)

    assert_equal 3, result[:mutations].length
    assert_equal({}, result[:mutations][0][:result])
    assert_equal({}, result[:mutations][1][:result])
    assert_equal({}, result[:mutations][2][:result])
    assert_equal 3, @store.fetch_with_lock("group-1", "client-1")
  end

  def test_detects_already_processed_mutation
    # Process first mutation
    @store.update("group-1", "client-1", 5)

    # Try to process mutation 3 (already processed since last_id is 5)
    push_data = {
      "pushVersion" => 1,
      "clientGroupID" => "group-1",
      "mutations" => [
        {"id" => 3, "clientID" => "client-1", "name" => "items.create", "args" => [{"id" => "item-1"}]}
      ]
    }

    result = @processor.process(push_data, @context)

    assert_equal 1, result[:mutations].length
    assert_equal "alreadyProcessed", result[:mutations][0][:result][:error]
    # LMID should not change
    assert_equal 5, @store.fetch_with_lock("group-1", "client-1")
  end

  def test_detects_out_of_order_mutation
    # Set LMID to 1, expect mutation 2
    @store.update("group-1", "client-1", 1)

    # Try to process mutation 5 (out of order, expected 2)
    push_data = {
      "pushVersion" => 1,
      "clientGroupID" => "group-1",
      "mutations" => [
        {"id" => 5, "clientID" => "client-1", "name" => "items.create", "args" => [{"id" => "item-1"}]}
      ]
    }

    result = @processor.process(push_data, @context)

    assert_equal 1, result[:mutations].length
    assert_equal "ooo", result[:mutations][0][:result][:error]
    assert_match(/expected 2/, result[:mutations][0][:result][:message])
    # LMID should not change
    assert_equal 1, @store.fetch_with_lock("group-1", "client-1")
  end

  def test_stops_batch_on_out_of_order
    # Set LMID to 1, expect mutation 2
    @store.update("group-1", "client-1", 1)

    # First mutation is out of order, second should not be processed
    push_data = {
      "pushVersion" => 1,
      "clientGroupID" => "group-1",
      "mutations" => [
        {"id" => 5, "clientID" => "client-1", "name" => "items.create", "args" => [{"id" => "item-1"}]},
        {"id" => 6, "clientID" => "client-1", "name" => "items.create", "args" => [{"id" => "item-2"}]}
      ]
    }

    result = @processor.process(push_data, @context)

    # Only first mutation should be in results (batch halted)
    assert_equal 1, result[:mutations].length
    assert_equal "ooo", result[:mutations][0][:result][:error]
  end

  def test_continues_batch_on_already_processed
    # Set LMID to 5
    @store.update("group-1", "client-1", 5)

    # First mutation is already processed, second is valid
    push_data = {
      "pushVersion" => 1,
      "clientGroupID" => "group-1",
      "mutations" => [
        {"id" => 3, "clientID" => "client-1", "name" => "items.create", "args" => [{"id" => "item-1"}]},
        {"id" => 6, "clientID" => "client-1", "name" => "items.create", "args" => [{"id" => "item-2"}]}
      ]
    }

    result = @processor.process(push_data, @context)

    assert_equal 2, result[:mutations].length
    assert_equal "alreadyProcessed", result[:mutations][0][:result][:error]
    assert_equal({}, result[:mutations][1][:result])
    assert_equal 6, @store.fetch_with_lock("group-1", "client-1")
  end

  def test_retries_on_application_error
    push_data = {
      "pushVersion" => 1,
      "clientGroupID" => "group-1",
      "mutations" => [
        {"id" => 1, "clientID" => "client-1", "name" => "items.retry", "args" => [{"id" => "item-1"}]}
      ]
    }

    result = @processor.process(push_data, @context)

    # Should succeed after 3 attempts
    assert_equal({}, result[:mutations][0][:result])
    assert_equal 3, RetryableMutation.call_count
  end

  def test_returns_error_after_max_retries
    push_data = {
      "pushVersion" => 1,
      "clientGroupID" => "group-1",
      "mutations" => [
        {"id" => 1, "clientID" => "client-1", "name" => "items.fail", "args" => [{"id" => "item-1"}]}
      ]
    }

    result = @processor.process(push_data, @context)

    assert_equal "app", result[:mutations][0][:result][:error]
    assert_equal "Permanent error", result[:mutations][0][:result][:message]
    assert_equal({code: "ERR001"}, result[:mutations][0][:result][:details])
  end

  def test_handles_multiple_clients_in_same_batch
    push_data = {
      "pushVersion" => 1,
      "clientGroupID" => "group-1",
      "mutations" => [
        {"id" => 1, "clientID" => "client-1", "name" => "items.create", "args" => [{"id" => "item-1"}]},
        {"id" => 1, "clientID" => "client-2", "name" => "items.create", "args" => [{"id" => "item-2"}]},
        {"id" => 2, "clientID" => "client-1", "name" => "items.create", "args" => [{"id" => "item-3"}]}
      ]
    }

    result = @processor.process(push_data, @context)

    assert_equal 3, result[:mutations].length
    assert_equal({}, result[:mutations][0][:result])
    assert_equal({}, result[:mutations][1][:result])
    assert_equal({}, result[:mutations][2][:result])

    assert_equal 2, @store.fetch_with_lock("group-1", "client-1")
    assert_equal 1, @store.fetch_with_lock("group-1", "client-2")
  end

  def test_handles_unknown_mutation
    push_data = {
      "pushVersion" => 1,
      "clientGroupID" => "group-1",
      "mutations" => [
        {"id" => 1, "clientID" => "client-1", "name" => "unknown.mutation", "args" => [{}]}
      ]
    }

    result = @processor.process(push_data, @context)

    assert_equal "app", result[:mutations][0][:result][:error]
    assert_match(/Unknown mutation/, result[:mutations][0][:result][:message])
  end
end
