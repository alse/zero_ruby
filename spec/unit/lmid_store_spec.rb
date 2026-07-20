# frozen_string_literal: true

require "spec_helper"

describe ZeroRuby::LmidStore do
  describe "abstract interface" do
    let(:store) { described_class.new }

    it "raises NotImplementedError for fetch_and_increment" do
      expect { store.fetch_and_increment("group", "client", upstream_schema: "zero_0") }
        .to raise_error(NotImplementedError)
    end

    it "raises NotImplementedError for transaction" do
      expect { store.transaction {} }
        .to raise_error(NotImplementedError)
    end

    it "raises NotImplementedError for write_mutation_result" do
      expect { store.write_mutation_result("group", "client", 1, {}, upstream_schema: "zero_0") }
        .to raise_error(NotImplementedError)
    end

    it "raises NotImplementedError for delete_mutation_results" do
      expect { store.delete_mutation_results({}, upstream_schema: "zero_0") }
        .to raise_error(NotImplementedError)
    end
  end
end

describe ZeroRuby::LmidStores::ActiveRecordStore do
  let(:store) { described_class.new }
  let(:schema) { "zero_0" }

  it "returns 1 for new client" do
    result = store.fetch_and_increment("group-1", "client-1", upstream_schema: schema)
    expect(result).to eq(1)
  end

  it "increments existing value" do
    store.fetch_and_increment("group-1", "client-1", upstream_schema: schema)  # -> 1
    store.fetch_and_increment("group-1", "client-1", upstream_schema: schema)  # -> 2
    result = store.fetch_and_increment("group-1", "client-1", upstream_schema: schema)
    expect(result).to eq(3)
  end

  it "increments sequentially" do
    expect(store.fetch_and_increment("group-1", "client-1", upstream_schema: schema)).to eq(1)
    expect(store.fetch_and_increment("group-1", "client-1", upstream_schema: schema)).to eq(2)
    expect(store.fetch_and_increment("group-1", "client-1", upstream_schema: schema)).to eq(3)
  end

  it "maintains separate values for different clients" do
    store.fetch_and_increment("group-1", "client-1", upstream_schema: schema)  # -> 1
    store.fetch_and_increment("group-1", "client-1", upstream_schema: schema)  # -> 2
    store.fetch_and_increment("group-1", "client-2", upstream_schema: schema)  # -> 1

    # Query directly to verify
    client1 = ZeroRuby::ZeroClient.find_by(
      "clientGroupID" => "group-1",
      "clientID" => "client-1"
    )
    client2 = ZeroRuby::ZeroClient.find_by(
      "clientGroupID" => "group-1",
      "clientID" => "client-2"
    )

    expect(client1["lastMutationID"]).to eq(2)
    expect(client2["lastMutationID"]).to eq(1)
  end

  it "executes transaction block" do
    result = store.transaction { 42 }
    expect(result).to eq(42)
  end

  it "rolls back on error" do
    store.fetch_and_increment("group-1", "client-1", upstream_schema: schema)  # -> 1

    expect {
      store.transaction do
        store.fetch_and_increment("group-1", "client-1", upstream_schema: schema)  # -> 2
        raise "boom"
      end
    }.to raise_error("boom")

    # Value should be rolled back to 1
    client = ZeroRuby::ZeroClient.find_by(
      "clientGroupID" => "group-1",
      "clientID" => "client-1"
    )
    expect(client["lastMutationID"]).to eq(1)
  end

  describe "alternate upstream_schema" do
    let(:alt_schema) { "zero_test" }

    before do
      ZeroRuby::TestHelpers::DatabaseSetup.setup_schema!(alt_schema)
      ZeroRuby::TestHelpers::DatabaseSetup.truncate!(alt_schema)
    end

    it "routes fetch_and_increment to the requested schema" do
      result = store.fetch_and_increment("group-1", "client-1", upstream_schema: alt_schema)
      expect(result).to eq(1)

      # Default schema is untouched
      default_row = ZeroRuby::ZeroClient.find_by(
        "clientGroupID" => "group-1",
        "clientID" => "client-1"
      )
      expect(default_row).to be_nil

      # Alternate schema has the row
      alt_row = ActiveRecord::Base.connection.select_one(<<~SQL.squish)
        SELECT "lastMutationID" FROM #{alt_schema}.clients
        WHERE "clientGroupID" = 'group-1' AND "clientID" = 'client-1'
      SQL
      expect(alt_row["lastMutationID"]).to eq(1)
    end

    it "routes write_mutation_result and delete_mutation_results to the requested schema" do
      store.write_mutation_result("g", "c", 1, {error: "app", message: "boom"}, upstream_schema: alt_schema)
      expect(get_mutation_result("g", "c", 1, schema: alt_schema)).not_to be_nil
      expect(get_mutation_result("g", "c", 1, schema: schema)).to be_nil

      store.delete_mutation_results({"clientGroupID" => "g", "clientID" => "c", "upToMutationID" => 1}, upstream_schema: alt_schema)
      expect(get_mutation_result("g", "c", 1, schema: alt_schema)).to be_nil
    end
  end
end
