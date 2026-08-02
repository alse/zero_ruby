# frozen_string_literal: true

require "spec_helper"

# Pins the reference retry semantics (process-mutations.ts Transactor,
# last verified against tag zero/v1.8.0):
# a failed mutation transaction is retried once WITHOUT the mutator, advancing
# the LMID and persisting the error result. LMID races during that retry map
# to alreadyProcessed results or batch-fatal errors exactly like upstream.
class RetrySpecSuccessMutation < ZeroRuby::Mutation
  argument :id, ZeroRuby::Types::String

  def execute(**)
    nil
  end
end

class RetrySpecAppErrorMutation < ZeroRuby::Mutation
  argument :id, ZeroRuby::Types::String

  def execute(**)
    raise ZeroRuby::Error.new("Permanent error", details: {code: "ERR001"})
  end
end

class RetrySpecFalsyDetailsMutation < ZeroRuby::Mutation
  argument :id, ZeroRuby::Types::String

  def execute(**)
    raise ZeroRuby::Error.new("boom", details: 0)
  end
end

# Intentionally does not override #execute: the base class raises
# NotImplementedError, which is a ScriptError, not a StandardError.
class RetrySpecNotImplementedMutation < ZeroRuby::Mutation
  argument :id, ZeroRuby::Types::String
end

class RetrySpecPreTransactionErrorMutation < ZeroRuby::Mutation
  skip_auto_transaction
  argument :id, ZeroRuby::Types::String

  def execute(**)
    raise ZeroRuby::Error.new("Pre-transaction failure")
  end
end

class RetrySpecSchema < ZeroRuby::Schema
  mutation "items.create", handler: RetrySpecSuccessMutation
  mutation "items.appError", handler: RetrySpecAppErrorMutation
  mutation "items.falsyDetails", handler: RetrySpecFalsyDetailsMutation
  mutation "items.notImplemented", handler: RetrySpecNotImplementedMutation
  mutation "items.preError", handler: RetrySpecPreTransactionErrorMutation
end

# In-memory store with scripted fetch_and_increment outcomes so LMID races and
# infrastructure failures can be simulated deterministically. Each entry in
# `increments` is either an Integer (the post-increment LMID to return) or an
# Exception to raise.
class ScriptedLmidStore < ZeroRuby::LmidStore
  attr_reader :writes, :increment_calls

  def initialize(increments)
    @increments = increments
    @writes = []
    @increment_calls = 0
  end

  def transaction
    yield
  end

  def fetch_and_increment(_client_group_id, _client_id, upstream_schema:)
    @increment_calls += 1
    outcome = @increments.shift
    raise "ScriptedLmidStore ran out of scripted increments" if outcome.nil?
    raise outcome if outcome.is_a?(Exception)
    outcome
  end

  def write_mutation_result(client_group_id, client_id, mutation_id, result, upstream_schema:)
    @writes << {client_id: client_id, mutation_id: mutation_id, result: result}
  end

  def delete_mutation_results(args, upstream_schema:)
  end
end

describe "PushProcessor retry semantics" do
  def processor_with(increments)
    store = ScriptedLmidStore.new(increments)
    [ZeroRuby::PushProcessor.new(schema: RetrySpecSchema, lmid_store: store), store]
  end

  def push_with(mutations)
    {"pushVersion" => 1, "clientGroupID" => "group-1", "mutations" => mutations}
  end

  it "retries a transaction-phase infrastructure failure without the mutator and skips the mutation" do
    processor, store = processor_with([RuntimeError.new("db connection lost"), 1])
    push = push_with([{"id" => 1, "clientID" => "client-1", "name" => "items.create", "args" => [{"id" => "a"}]}])

    result = processor.process(push, {})

    expect(result).to eq({
      kind: "MutateResponse",
      mutations: [{id: {id: 1, clientID: "client-1"}, result: {error: "app", message: "db connection lost"}}]
    })
    # Retry persisted the error result alongside the LMID advance
    expect(store.increment_calls).to eq(2)
    expect(store.writes).to eq([{client_id: "client-1", mutation_id: 1, result: {error: "app", message: "db connection lost"}}])
  end

  it "returns alreadyProcessed when the retry detects a concurrent duplicate" do
    processor, store = processor_with([RuntimeError.new("db connection lost"), 2])
    push = push_with([{"id" => 1, "clientID" => "client-1", "name" => "items.create", "args" => [{"id" => "a"}]}])

    result = processor.process(push, {})

    expect(result).to eq({
      kind: "MutateResponse",
      mutations: [{
        id: {id: 1, clientID: "client-1"},
        result: {
          error: "alreadyProcessed",
          details: "Ignoring mutation from client-1 with ID 1 as it was already processed. Expected: 2"
        }
      }]
    })
    expect(store.writes).to be_empty
  end

  it "aborts with PushFailed oooMutation when the retry detects an out-of-order mutation" do
    processor, _store = processor_with([RuntimeError.new("db connection lost"), 1])
    push = push_with([{"id" => 5, "clientID" => "client-1", "name" => "items.create", "args" => [{"id" => "a"}]}])

    result = processor.process(push, {})

    expect(result).to eq({
      kind: "PushFailed",
      origin: "server",
      reason: "oooMutation",
      message: "Client client-1 sent mutation ID 5 but expected 1",
      mutationIDs: [{id: 5, clientID: "client-1"}]
    })
  end

  it "aborts with PushFailed database when the retry also fails" do
    processor, _store = processor_with([RuntimeError.new("db down"), RuntimeError.new("db still down")])
    push = push_with([
      {"id" => 1, "clientID" => "client-1", "name" => "items.create", "args" => [{"id" => "a"}]},
      {"id" => 2, "clientID" => "client-1", "name" => "items.create", "args" => [{"id" => "b"}]}
    ])

    result = processor.process(push, {})

    expect(result[:kind]).to eq("PushFailed")
    expect(result[:reason]).to eq("database")
    # Message and details mirror the reference's DatabaseTransactionError
    expect(result[:message]).to eq("Database transaction failed after opening: db still down")
    expect(result[:details]).to eq({name: "DatabaseTransactionError"})
    expect(result[:mutationIDs]).to eq([{id: 1, clientID: "client-1"}, {id: 2, clientID: "client-1"}])
  end

  it "persists application errors raised inside the transaction via the retry" do
    processor, store = processor_with([1, 1])
    push = push_with([{"id" => 1, "clientID" => "client-1", "name" => "items.appError", "args" => [{"id" => "a"}]}])

    result = processor.process(push, {})

    expected_result = {error: "app", message: "Permanent error", details: {code: "ERR001"}}
    expect(result).to eq({
      kind: "MutateResponse",
      mutations: [{id: {id: 1, clientID: "client-1"}, result: expected_result}]
    })
    expect(store.increment_calls).to eq(2)
    expect(store.writes).to eq([{client_id: "client-1", mutation_id: 1, result: expected_result}])
  end

  it "aborts with PushFailed internal when a pre-transaction failure persist hits a duplicate" do
    # Reference: persistPreTransactionFailure has no alreadyProcessed handling,
    # so the error escapes to the top-level catch-all (reason "internal").
    processor, _store = processor_with([2])
    push = push_with([{"id" => 1, "clientID" => "client-1", "name" => "items.preError", "args" => [{"id" => "a"}]}])

    result = processor.process(push, {})

    expect(result[:kind]).to eq("PushFailed")
    expect(result[:reason]).to eq("internal")
    expect(result[:message]).to eq("Ignoring mutation from client-1 with ID 1 as it was already processed. Expected: 2")
    expect(result[:mutationIDs]).to eq([{id: 1, clientID: "client-1"}])
  end

  it "aborts with PushFailed internal for CRUD-typed mutations" do
    processor, _store = processor_with([])
    push = push_with([{"type" => "crud", "id" => 1, "clientID" => "client-1", "name" => "_zero_crud", "args" => [{"ops" => []}]}])

    result = processor.process(push, {})

    expect(result[:kind]).to eq("PushFailed")
    expect(result[:reason]).to eq("internal")
    expect(result[:message]).to eq("Expected custom mutation")
    expect(result[:mutationIDs]).to eq([{id: 1, clientID: "client-1"}])
  end

  it "omits JS-falsy details like the reference (details: 0 is dropped)" do
    processor, store = processor_with([1, 1])
    push = push_with([{"id" => 1, "clientID" => "client-1", "name" => "items.falsyDetails", "args" => [{"id" => "a"}]}])

    result = processor.process(push, {})

    expect(result[:mutations][0][:result]).to eq({error: "app", message: "boom"})
    expect(store.writes[0][:result]).to eq({error: "app", message: "boom"})
  end

  it "converts non-StandardError exceptions (NotImplementedError) into app errors instead of raising" do
    processor, store = processor_with([1, 1])
    push = push_with([{"id" => 1, "clientID" => "client-1", "name" => "items.notImplemented", "args" => [{"id" => "a"}]}])

    result = processor.process(push, {})

    expect(result[:kind]).to eq("MutateResponse")
    expect(result[:mutations][0][:result]).to eq({
      error: "app",
      message: "Subclasses must implement #execute",
      details: {name: "NotImplementedError"}
    })
    expect(store.writes.length).to eq(1)
  end

  it "wraps non-ZeroRuby exception details with the error class name" do
    processor, store = processor_with([ArgumentError.new("bad argument"), 1])
    push = push_with([{"id" => 1, "clientID" => "client-1", "name" => "items.create", "args" => [{"id" => "a"}]}])

    result = processor.process(push, {})

    expect(result[:mutations][0][:result]).to eq({
      error: "app",
      message: "bad argument",
      details: {name: "ArgumentError"}
    })
    expect(store.writes[0][:result]).to eq({error: "app", message: "bad argument", details: {name: "ArgumentError"}})
  end
end
