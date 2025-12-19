# frozen_string_literal: true

require "spec_helper"

describe ZeroRuby::LmidStore do
  describe "abstract interface" do
    let(:store) { described_class.new }

    it "raises NotImplementedError for fetch_and_increment" do
      expect { store.fetch_and_increment("group", "client") }
        .to raise_error(NotImplementedError)
    end

    it "raises NotImplementedError for transaction" do
      expect { store.transaction {} }
        .to raise_error(NotImplementedError)
    end
  end
end

describe ZeroRuby::LmidStores::ActiveRecordStore do
  let(:store) { described_class.new }

  it "returns 1 for new client" do
    result = store.fetch_and_increment("group-1", "client-1")
    expect(result).to eq(1)
  end

  it "increments existing value" do
    store.fetch_and_increment("group-1", "client-1")  # -> 1
    store.fetch_and_increment("group-1", "client-1")  # -> 2
    result = store.fetch_and_increment("group-1", "client-1")
    expect(result).to eq(3)
  end

  it "increments sequentially" do
    expect(store.fetch_and_increment("group-1", "client-1")).to eq(1)
    expect(store.fetch_and_increment("group-1", "client-1")).to eq(2)
    expect(store.fetch_and_increment("group-1", "client-1")).to eq(3)
  end

  it "maintains separate values for different clients" do
    store.fetch_and_increment("group-1", "client-1")  # -> 1
    store.fetch_and_increment("group-1", "client-1")  # -> 2
    store.fetch_and_increment("group-1", "client-2")  # -> 1

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
    store.fetch_and_increment("group-1", "client-1")  # -> 1

    expect {
      store.transaction do
        store.fetch_and_increment("group-1", "client-1")  # -> 2
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
end
