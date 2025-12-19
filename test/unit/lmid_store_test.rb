# frozen_string_literal: true

require_relative "../test_helper"

class LmidStoreInterfaceTest < Minitest::Test
  def test_abstract_fetch_with_lock_raises
    store = ZeroRuby::LmidStore.new
    assert_raises(NotImplementedError) do
      store.fetch_with_lock("group", "client")
    end
  end

  def test_abstract_update_raises
    store = ZeroRuby::LmidStore.new
    assert_raises(NotImplementedError) do
      store.update("group", "client", 1)
    end
  end

  def test_abstract_transaction_raises
    store = ZeroRuby::LmidStore.new
    assert_raises(NotImplementedError) do
      store.transaction {}
    end
  end
end

class MockLmidStoreTest < Minitest::Test
  def setup
    @store = ZeroRuby::TestHelpers::MockLmidStore.new
  end

  def test_fetch_returns_nil_for_new_client
    result = @store.fetch_with_lock("group-1", "client-1")
    assert_nil result
  end

  def test_update_and_fetch
    @store.update("group-1", "client-1", 5)
    result = @store.fetch_with_lock("group-1", "client-1")
    assert_equal 5, result
  end

  def test_different_clients_have_separate_values
    @store.update("group-1", "client-1", 5)
    @store.update("group-1", "client-2", 10)

    assert_equal 5, @store.fetch_with_lock("group-1", "client-1")
    assert_equal 10, @store.fetch_with_lock("group-1", "client-2")
  end

  def test_transaction_executes_block
    result = @store.transaction { 42 }
    assert_equal 42, result
  end
end
