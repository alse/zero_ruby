# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "zero_ruby"
require "ostruct"
require "minitest/autorun"

module ZeroRuby
  module TestHelpers
    # Mock LMID store for testing. Provides the same interface as ActiveRecordStore
    # but stores data in memory. Only for use in tests.
    class MockLmidStore < LmidStore
      def initialize
        @data = {}
      end

      def fetch_with_lock(client_group_id, client_id)
        key = "#{client_group_id}:#{client_id}"
        @data[key]
      end

      def update(client_group_id, client_id, mutation_id)
        key = "#{client_group_id}:#{client_id}"
        @data[key] = mutation_id
      end

      def transaction(&block)
        yield
      end
    end
  end
end
