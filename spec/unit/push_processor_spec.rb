# frozen_string_literal: true

require "spec_helper"

# Test mutation that succeeds (auto_transact: true, default)
# Calls transact for backward compatibility - acts as no-op in auto mode
class SuccessMutation < ZeroRuby::Mutation
  argument :id, ZeroRuby::Types::String

  def execute(**)
    transact { nil }
  end
end

# Test mutation that succeeds without calling transact (auto_transact: true)
class AutoTransactMutation < ZeroRuby::Mutation
  argument :id, ZeroRuby::Types::String

  def execute(**)
    # No transact call - entire execute is wrapped automatically
    nil
  end
end

# Test auto_transact mutation that raises an error
class AutoTransactFailingMutation < ZeroRuby::Mutation
  argument :id, ZeroRuby::Types::String

  @@call_count = 0

  def self.reset_count!
    @@call_count = 0
  end

  def self.call_count
    @@call_count
  end

  def execute(**)
    @@call_count += 1
    raise ZeroRuby::Error.new("Auto transact error")
  end
end

# Test mutation that always fails
class FailingMutation < ZeroRuby::Mutation
  argument :id, ZeroRuby::Types::String

  def execute(**)
    transact do
      raise ZeroRuby::Error.new("Permanent error", details: {code: "ERR001"})
    end
  end
end

# Test mutation that raises ValidationError (should NOT be retried)
class ValidationFailingMutation < ZeroRuby::Mutation
  argument :id, ZeroRuby::Types::String

  @@call_count = 0

  def self.reset_count!
    @@call_count = 0
  end

  def self.call_count
    @@call_count
  end

  def execute(**)
    transact do
      @@call_count += 1
      raise ZeroRuby::ValidationError.new(["id is invalid"])
    end
  end
end

# Test mutation that raises error BEFORE calling transact (pre-transaction phase)
# Uses skip_auto_transaction to test 3-phase model
class PreTransactionErrorMutation < ZeroRuby::Mutation
  skip_auto_transaction
  argument :id, ZeroRuby::Types::String

  def execute(**)
    raise ZeroRuby::ValidationError.new(["Pre-transaction validation failed"])
    # Never reaches transact
  end
end

# Test mutation that raises RETRYABLE error before transact (should NOT be retried)
# Uses skip_auto_transaction to test 3-phase model
class PreTransactionRetryableErrorMutation < ZeroRuby::Mutation
  skip_auto_transaction
  argument :id, ZeroRuby::Types::String

  @@call_count = 0

  def self.reset_count!
    @@call_count = 0
  end

  def self.call_count
    @@call_count
  end

  def execute(**)
    @@call_count += 1
    raise ZeroRuby::Error.new("Pre-transaction retryable error")
    # Never reaches transact
  end
end

# Test mutation that raises error AFTER transact returns (post-commit phase)
# Uses skip_auto_transaction to test 3-phase model
class PostCommitErrorMutation < ZeroRuby::Mutation
  skip_auto_transaction
  argument :id, ZeroRuby::Types::String

  def execute(**)
    transact { nil }
    raise ZeroRuby::Error.new("Post-commit error")
  end
end

# Test mutation that doesn't call transact at all (skip_auto_transaction)
# Should raise TransactNotCalledError
class NoTransactMutation < ZeroRuby::Mutation
  skip_auto_transaction
  argument :id, ZeroRuby::Types::String

  def execute(**)
    # Intentionally doesn't call transact - should fail
    nil
  end
end

# Test mutation that raises ActiveRecord::StatementInvalid
class StatementInvalidMutation < ZeroRuby::Mutation
  argument :id, ZeroRuby::Types::String

  def execute(**)
    raise ActiveRecord::StatementInvalid.new("PG::UniqueViolation: duplicate key")
  end
end

# Test mutation that raises a generic (non-ZeroRuby) exception
class GenericExceptionMutation < ZeroRuby::Mutation
  argument :id, ZeroRuby::Types::String

  def execute(**)
    raise "Something unexpected happened"
  end
end

# Test mutation that raises TransactionError directly
class DatabaseTransactionMutation < ZeroRuby::Mutation
  argument :id, ZeroRuby::Types::String

  def execute(**)
    raise ZeroRuby::TransactionError.new("Deadlock detected")
  end
end

# Test skip_auto_transaction mutation that raises ActiveRecord::StatementInvalid inside transact
class ManualStatementInvalidMutation < ZeroRuby::Mutation
  skip_auto_transaction
  argument :id, ZeroRuby::Types::String

  def execute(**)
    transact do
      raise ActiveRecord::StatementInvalid.new("PG::ForeignKeyViolation: constraint violated")
    end
  end
end

# Test skip_auto_transaction mutation that raises generic exception inside transact
class ManualGenericExceptionMutation < ZeroRuby::Mutation
  skip_auto_transaction
  argument :id, ZeroRuby::Types::String

  def execute(**)
    transact do
      raise "Manual unexpected error"
    end
  end
end

# Schema for push processor tests
class PushSchema < ZeroRuby::Schema
  mutation "items.create", handler: SuccessMutation
  mutation "items.auto", handler: AutoTransactMutation
  mutation "items.auto_fail", handler: AutoTransactFailingMutation
  mutation "items.fail", handler: FailingMutation
  mutation "items.validate", handler: ValidationFailingMutation
  mutation "items.pre_error", handler: PreTransactionErrorMutation
  mutation "items.pre_error_retryable", handler: PreTransactionRetryableErrorMutation
  mutation "items.post_error", handler: PostCommitErrorMutation
  mutation "items.no_transact", handler: NoTransactMutation
  mutation "items.statement_invalid", handler: StatementInvalidMutation
  mutation "items.generic_exception", handler: GenericExceptionMutation
  mutation "items.db_transaction", handler: DatabaseTransactionMutation
  mutation "items.manual_statement_invalid", handler: ManualStatementInvalidMutation
  mutation "items.manual_generic_exception", handler: ManualGenericExceptionMutation
end

describe ZeroRuby::PushProcessor do
  let(:store) { ZeroRuby::LmidStores::ActiveRecordStore.new }
  let(:processor) do
    described_class.new(
      schema: PushSchema,
      lmid_store: store
    )
  end
  let(:context) { {current_user: OpenStruct.new(id: 1)} }
  let(:success) { {} }

  before do
    ValidationFailingMutation.reset_count!
    PreTransactionRetryableErrorMutation.reset_count!
    AutoTransactFailingMutation.reset_count!
  end

  it "processes first mutation for new client" do
    push_data = {
      "pushVersion" => 1,
      "clientGroupID" => "group-1",
      "mutations" => [
        {"id" => 1, "clientID" => "client-1", "name" => "items.create", "args" => [{"id" => "item-1"}]}
      ]
    }

    result = processor.process(push_data, context)

    expect(result[:mutations].length).to eq(1)
    expect(result[:mutations][0][:id]).to eq({id: 1, clientID: "client-1"})
    expect(result[:mutations][0][:result]).to eq(success)
    expect(get_lmid("group-1", "client-1")).to eq(1)
  end

  it "processes sequential mutations" do
    push_data = {
      "pushVersion" => 1,
      "clientGroupID" => "group-1",
      "mutations" => [
        {"id" => 1, "clientID" => "client-1", "name" => "items.create", "args" => [{"id" => "item-1"}]},
        {"id" => 2, "clientID" => "client-1", "name" => "items.create", "args" => [{"id" => "item-2"}]},
        {"id" => 3, "clientID" => "client-1", "name" => "items.create", "args" => [{"id" => "item-3"}]}
      ]
    }

    result = processor.process(push_data, context)

    expect(result[:mutations].length).to eq(3)
    expect(result[:mutations][0][:result]).to eq(success)
    expect(result[:mutations][1][:result]).to eq(success)
    expect(result[:mutations][2][:result]).to eq(success)
    expect(get_lmid("group-1", "client-1")).to eq(3)
  end

  it "detects already processed mutation" do
    set_lmid("group-1", "client-1", 5)

    push_data = {
      "pushVersion" => 1,
      "clientGroupID" => "group-1",
      "mutations" => [
        {"id" => 3, "clientID" => "client-1", "name" => "items.create", "args" => [{"id" => "item-1"}]}
      ]
    }

    result = processor.process(push_data, context)

    expect(result[:mutations].length).to eq(1)
    expect(result[:mutations][0][:result][:error]).to eq("alreadyProcessed")
    expect(result[:mutations][0][:result][:details]).to match(/already processed/)
    expect(get_lmid("group-1", "client-1")).to eq(5)
  end

  it "detects out of order mutation" do
    set_lmid("group-1", "client-1", 1)

    push_data = {
      "pushVersion" => 1,
      "clientGroupID" => "group-1",
      "mutations" => [
        {"id" => 5, "clientID" => "client-1", "name" => "items.create", "args" => [{"id" => "item-1"}]}
      ]
    }

    result = processor.process(push_data, context)

    expect(result[:kind]).to eq("PushFailed")
    expect(result[:origin]).to eq("server")
    expect(result[:reason]).to eq("oooMutation")
    expect(result[:message]).to match(/expected 2/)
    expect(result[:mutationIDs]).to eq([{id: 5, clientID: "client-1"}])
    expect(get_lmid("group-1", "client-1")).to eq(1)
  end

  it "stops batch on out of order and returns all unprocessed IDs" do
    set_lmid("group-1", "client-1", 1)

    push_data = {
      "pushVersion" => 1,
      "clientGroupID" => "group-1",
      "mutations" => [
        {"id" => 5, "clientID" => "client-1", "name" => "items.create", "args" => [{"id" => "item-1"}]},
        {"id" => 6, "clientID" => "client-1", "name" => "items.create", "args" => [{"id" => "item-2"}]}
      ]
    }

    result = processor.process(push_data, context)

    expect(result[:kind]).to eq("PushFailed")
    expect(result[:reason]).to eq("oooMutation")
    expect(result[:mutationIDs]).to eq([
      {id: 5, clientID: "client-1"},
      {id: 6, clientID: "client-1"}
    ])
  end

  it "continues batch on already processed" do
    set_lmid("group-1", "client-1", 5)

    push_data = {
      "pushVersion" => 1,
      "clientGroupID" => "group-1",
      "mutations" => [
        {"id" => 3, "clientID" => "client-1", "name" => "items.create", "args" => [{"id" => "item-1"}]},
        {"id" => 6, "clientID" => "client-1", "name" => "items.create", "args" => [{"id" => "item-2"}]}
      ]
    }

    result = processor.process(push_data, context)

    expect(result[:mutations].length).to eq(2)
    expect(result[:mutations][0][:result][:error]).to eq("alreadyProcessed")
    expect(result[:mutations][1][:result]).to eq(success)
    expect(get_lmid("group-1", "client-1")).to eq(6)
  end

  it "does not retry ValidationError" do
    push_data = {
      "pushVersion" => 1,
      "clientGroupID" => "group-1",
      "mutations" => [
        {"id" => 1, "clientID" => "client-1", "name" => "items.validate", "args" => [{"id" => "item-1"}]}
      ]
    }

    result = processor.process(push_data, context)

    expect(result[:mutations][0][:result][:error]).to eq("app")
    expect(result[:mutations][0][:result][:message]).to include("id is invalid")
    expect(ValidationFailingMutation.call_count).to eq(1)
  end

  it "returns error on mutation failure" do
    push_data = {
      "pushVersion" => 1,
      "clientGroupID" => "group-1",
      "mutations" => [
        {"id" => 1, "clientID" => "client-1", "name" => "items.fail", "args" => [{"id" => "item-1"}]}
      ]
    }

    result = processor.process(push_data, context)

    expect(result[:mutations][0][:result][:error]).to eq("app")
    expect(result[:mutations][0][:result][:message]).to eq("Permanent error")
    expect(result[:mutations][0][:result][:details]).to eq({code: "ERR001"})
  end

  it "handles multiple clients in same batch" do
    push_data = {
      "pushVersion" => 1,
      "clientGroupID" => "group-1",
      "mutations" => [
        {"id" => 1, "clientID" => "client-1", "name" => "items.create", "args" => [{"id" => "item-1"}]},
        {"id" => 1, "clientID" => "client-2", "name" => "items.create", "args" => [{"id" => "item-2"}]},
        {"id" => 2, "clientID" => "client-1", "name" => "items.create", "args" => [{"id" => "item-3"}]}
      ]
    }

    result = processor.process(push_data, context)

    expect(result[:mutations].length).to eq(3)
    expect(result[:mutations][0][:result]).to eq(success)
    expect(result[:mutations][1][:result]).to eq(success)
    expect(result[:mutations][2][:result]).to eq(success)

    expect(get_lmid("group-1", "client-1")).to eq(2)
    expect(get_lmid("group-1", "client-2")).to eq(1)
  end

  it "handles unknown mutation" do
    push_data = {
      "pushVersion" => 1,
      "clientGroupID" => "group-1",
      "mutations" => [
        {"id" => 1, "clientID" => "client-1", "name" => "unknown.mutation", "args" => [{}]}
      ]
    }

    result = processor.process(push_data, context)

    expect(result[:mutations][0][:result][:error]).to eq("app")
    expect(result[:mutations][0][:result][:message]).to match(/Unknown mutation/)
  end

  describe "auto_transact behavior" do
    it "processes mutation without explicit transact call when auto_transact is true (default)" do
      push_data = {
        "pushVersion" => 1,
        "clientGroupID" => "group-auto",
        "mutations" => [
          {"id" => 1, "clientID" => "client-auto", "name" => "items.auto", "args" => [{"id" => "item-1"}]}
        ]
      }

      result = processor.process(push_data, context)

      expect(result[:mutations].length).to eq(1)
      expect(result[:mutations][0][:id]).to eq({id: 1, clientID: "client-auto"})
      expect(result[:mutations][0][:result]).to eq(success)
      expect(get_lmid("group-auto", "client-auto")).to eq(1)
    end

    it "returns error on failure in auto_transact mode without retry" do
      push_data = {
        "pushVersion" => 1,
        "clientGroupID" => "group-auto",
        "mutations" => [
          {"id" => 1, "clientID" => "client-auto-retry", "name" => "items.auto_fail", "args" => [{"id" => "item-1"}]}
        ]
      }

      result = processor.process(push_data, context)

      expect(result[:mutations][0][:result][:error]).to eq("app")
      # No retry - should be called exactly once
      expect(AutoTransactFailingMutation.call_count).to eq(1)
    end

    it "advances LMID on error in auto_transact mode" do
      push_data = {
        "pushVersion" => 1,
        "clientGroupID" => "group-auto",
        "mutations" => [
          {"id" => 1, "clientID" => "client-auto-err", "name" => "items.auto_fail", "args" => [{"id" => "item-1"}]}
        ]
      }

      result = processor.process(push_data, context)

      expect(result[:mutations][0][:result][:error]).to eq("app")
      # LMID should be advanced even on error
      expect(get_lmid("group-auto", "client-auto-err")).to eq(1)
    end

    it "allows transact call in auto_transact mode (backward compatibility)" do
      # SuccessMutation calls transact {} - should work as a no-op in auto mode
      push_data = {
        "pushVersion" => 1,
        "clientGroupID" => "group-auto",
        "mutations" => [
          {"id" => 1, "clientID" => "client-compat", "name" => "items.create", "args" => [{"id" => "item-1"}]}
        ]
      }

      result = processor.process(push_data, context)

      expect(result[:mutations][0][:result]).to eq(success)
      expect(get_lmid("group-auto", "client-compat")).to eq(1)
    end
  end

  describe "phase-based error handling (skip_auto_transaction)" do
    describe "pre-transaction errors" do
      it "advances LMID on pre-transaction error" do
        push_data = {
          "pushVersion" => 1,
          "clientGroupID" => "group-phase",
          "mutations" => [
            {"id" => 1, "clientID" => "client-pre", "name" => "items.pre_error", "args" => [{"id" => "item-1"}]}
          ]
        }

        result = processor.process(push_data, context)

        expect(result[:mutations][0][:result][:error]).to eq("app")
        expect(result[:mutations][0][:result][:message]).to include("Pre-transaction")
        # LMID should be advanced even though error was pre-transaction
        expect(get_lmid("group-phase", "client-pre")).to eq(1)
      end

      it "does not retry retryable errors in pre-transaction phase" do
        push_data = {
          "pushVersion" => 1,
          "clientGroupID" => "group-phase",
          "mutations" => [
            {"id" => 1, "clientID" => "client-pre-retry", "name" => "items.pre_error_retryable", "args" => [{"id" => "item-1"}]}
          ]
        }

        result = processor.process(push_data, context)

        expect(result[:mutations][0][:result][:error]).to eq("app")
        # Should only be called once - no retry for pre-transaction errors
        expect(PreTransactionRetryableErrorMutation.call_count).to eq(1)
      end
    end

    describe "transaction errors" do
      it "advances LMID on transaction error" do
        push_data = {
          "pushVersion" => 1,
          "clientGroupID" => "group-phase",
          "mutations" => [
            {"id" => 1, "clientID" => "client-tx", "name" => "items.fail", "args" => [{"id" => "item-1"}]}
          ]
        }

        result = processor.process(push_data, context)

        expect(result[:mutations][0][:result][:error]).to eq("app")
        # LMID should be advanced after transaction error
        expect(get_lmid("group-phase", "client-tx")).to eq(1)
      end
    end

    describe "post-commit errors" do
      it "returns error but doesn't double-advance LMID" do
        push_data = {
          "pushVersion" => 1,
          "clientGroupID" => "group-phase",
          "mutations" => [
            {"id" => 1, "clientID" => "client-post", "name" => "items.post_error", "args" => [{"id" => "item-1"}]}
          ]
        }

        result = processor.process(push_data, context)

        expect(result[:mutations][0][:result][:error]).to eq("app")
        expect(result[:mutations][0][:result][:message]).to include("Post-commit")
        # LMID was advanced inside the transaction, should be exactly 1
        expect(get_lmid("group-phase", "client-post")).to eq(1)
      end
    end

    describe "transact not called (skip_auto_transaction)" do
      it "raises TransactNotCalledError when skip_auto_transaction mutation doesn't call transact" do
        push_data = {
          "pushVersion" => 1,
          "clientGroupID" => "group-phase",
          "mutations" => [
            {"id" => 1, "clientID" => "client-notx", "name" => "items.no_transact", "args" => [{"id" => "item-1"}]}
          ]
        }

        result = processor.process(push_data, context)

        expect(result[:mutations][0][:result][:error]).to eq("app")
        expect(result[:mutations][0][:result][:message]).to include("must call transact")
      end
    end
  end

  describe "database and system error handling" do
    it "converts ActiveRecord::StatementInvalid to PushFailed" do
      push_data = {
        "pushVersion" => 1,
        "clientGroupID" => "group-db",
        "mutations" => [
          {"id" => 1, "clientID" => "client-stmt", "name" => "items.statement_invalid", "args" => [{"id" => "item-1"}]}
        ]
      }

      result = processor.process(push_data, context)

      expect(result[:kind]).to eq("PushFailed")
      expect(result[:origin]).to eq("server")
      expect(result[:reason]).to eq("database")
      expect(result[:message]).to include("Transaction failed")
      expect(result[:message]).to include("UniqueViolation")
      expect(result[:mutationIDs]).to eq([{id: 1, clientID: "client-stmt"}])
    end

    it "converts generic exceptions to PushFailed" do
      push_data = {
        "pushVersion" => 1,
        "clientGroupID" => "group-db",
        "mutations" => [
          {"id" => 1, "clientID" => "client-generic", "name" => "items.generic_exception", "args" => [{"id" => "item-1"}]}
        ]
      }

      result = processor.process(push_data, context)

      expect(result[:kind]).to eq("PushFailed")
      expect(result[:origin]).to eq("server")
      expect(result[:reason]).to eq("database")
      expect(result[:message]).to include("Transaction failed")
      expect(result[:message]).to include("Something unexpected")
      expect(result[:mutationIDs]).to eq([{id: 1, clientID: "client-generic"}])
    end

    it "handles TransactionError and returns PushFailed with unprocessed mutations" do
      push_data = {
        "pushVersion" => 1,
        "clientGroupID" => "group-db",
        "mutations" => [
          {"id" => 1, "clientID" => "client-dbtx", "name" => "items.db_transaction", "args" => [{"id" => "item-1"}]},
          {"id" => 2, "clientID" => "client-dbtx", "name" => "items.create", "args" => [{"id" => "item-2"}]}
        ]
      }

      result = processor.process(push_data, context)

      expect(result[:kind]).to eq("PushFailed")
      expect(result[:origin]).to eq("server")
      expect(result[:reason]).to eq("database")
      expect(result[:message]).to eq("Deadlock detected")
      # Both mutations should be in unprocessed list
      expect(result[:mutationIDs]).to eq([
        {id: 1, clientID: "client-dbtx"},
        {id: 2, clientID: "client-dbtx"}
      ])
    end

    context "with skip_auto_transaction (manual transact)" do
      it "converts ActiveRecord::StatementInvalid to PushFailed" do
        push_data = {
          "pushVersion" => 1,
          "clientGroupID" => "group-manual",
          "mutations" => [
            {"id" => 1, "clientID" => "client-manual-stmt", "name" => "items.manual_statement_invalid", "args" => [{"id" => "item-1"}]}
          ]
        }

        result = processor.process(push_data, context)

        expect(result[:kind]).to eq("PushFailed")
        expect(result[:reason]).to eq("database")
        expect(result[:message]).to include("ForeignKeyViolation")
      end

      it "converts generic exceptions to PushFailed" do
        push_data = {
          "pushVersion" => 1,
          "clientGroupID" => "group-manual",
          "mutations" => [
            {"id" => 1, "clientID" => "client-manual-generic", "name" => "items.manual_generic_exception", "args" => [{"id" => "item-1"}]}
          ]
        }

        result = processor.process(push_data, context)

        expect(result[:kind]).to eq("PushFailed")
        expect(result[:reason]).to eq("database")
        expect(result[:message]).to include("Manual unexpected error")
      end
    end
  end

  describe "persist_lmid_on_application_error failure" do
    it "logs warning but returns error response when LMID persistence fails" do
      # Stub the store to fail on the second transaction (the error recovery one)
      call_count = 0
      allow(store).to receive(:transaction).and_wrap_original do |original, &block|
        call_count += 1
        if call_count == 1
          # First call: normal transaction that will be rolled back due to app error
          original.call(&block)
        else
          # Second call: persist_lmid_on_application_error - simulate failure
          raise StandardError.new("Connection lost")
        end
      end

      push_data = {
        "pushVersion" => 1,
        "clientGroupID" => "group-lmid-fail",
        "mutations" => [
          {"id" => 1, "clientID" => "client-lmid", "name" => "items.auto_fail", "args" => [{"id" => "item-1"}]}
        ]
      }

      # Capture stderr and verify warning is logged
      result = nil
      expect {
        result = processor.process(push_data, context)
      }.to output(/Failed to persist LMID after application error/).to_stderr

      # Should still return the mutation error response (not raise)
      expect(result[:mutations]).to be_a(Array)
      expect(result[:mutations][0][:result][:error]).to eq("app")
      expect(result[:mutations][0][:result][:message]).to eq("Auto transact error")
    end
  end

  def set_lmid(client_group_id, client_id, mutation_id)
    ZeroRuby::ZeroClient.upsert(
      {"clientGroupID" => client_group_id, "clientID" => client_id, "lastMutationID" => mutation_id},
      unique_by: %w[clientGroupID clientID]
    )
  end

  def get_lmid(client_group_id, client_id)
    ZeroRuby::ZeroClient.find_by(
      "clientGroupID" => client_group_id,
      "clientID" => client_id
    )&.[]("lastMutationID")
  end
end
