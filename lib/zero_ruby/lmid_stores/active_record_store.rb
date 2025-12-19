# frozen_string_literal: true

require_relative "../lmid_store"

module ZeroRuby
  module LmidStores
    # ActiveRecord-based LMID store using Zero's zero_0.clients table.
    # This store provides proper transaction support and row-level locking
    # for concurrent access in production environments.
    #
    # @example Usage
    #   ZeroRuby.configure do |config|
    #     config.lmid_store = :active_record
    #   end
    class ActiveRecordStore < LmidStore
      # The model class to use for client records.
      # Defaults to ZeroRuby::ZeroClient.
      attr_reader :model_class

      def initialize(model_class: nil)
        @model_class = model_class || default_model_class
      end

      # Fetch the last mutation ID for a client with row-level locking.
      # Uses SELECT FOR UPDATE to prevent concurrent modifications.
      #
      # @param client_group_id [String] The client group ID
      # @param client_id [String] The client ID
      # @return [Integer, nil] The last mutation ID, or nil if not found
      def fetch_with_lock(client_group_id, client_id)
        record = model_class
          .lock("FOR UPDATE")
          .where('"clientGroupID" = ? AND "clientID" = ?', client_group_id, client_id)
          .first
        record&.send(:[], "lastMutationID")
      end

      # Update the last mutation ID for a client.
      # Creates the record if it doesn't exist (upsert).
      #
      # @param client_group_id [String] The client group ID
      # @param client_id [String] The client ID
      # @param mutation_id [Integer] The new last mutation ID
      def update(client_group_id, client_id, mutation_id)
        model_class.upsert(
          {"clientGroupID" => client_group_id, "clientID" => client_id, "lastMutationID" => mutation_id},
          unique_by: %w[clientGroupID clientID]
        )
      end

      # Execute a block within an ActiveRecord transaction.
      #
      # @yield The block to execute within the transaction
      # @return The result of the block
      def transaction(&block)
        model_class.transaction(&block)
      end

      private

      def default_model_class
        require_relative "../zero_client"
        ZeroRuby::ZeroClient
      end
    end
  end
end
