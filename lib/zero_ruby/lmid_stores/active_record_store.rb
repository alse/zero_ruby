# frozen_string_literal: true

require_relative "../lmid_store"

module ZeroRuby
  module LmidStores
    # ActiveRecord-based LMID store using Zero's zero_0.clients table.
    # This store provides proper transaction support with atomic LMID updates
    # for concurrent access in production environments.
    #
    # Uses the same atomic increment pattern as Zero's TypeScript implementation.
    # @see https://github.com/rocicorp/mono/blob/main/packages/zero-server/src/zql-database.ts
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

      # Atomically increment and return the last mutation ID for a client.
      # Uses INSERT ... ON CONFLICT to handle both new and existing clients
      # in a single atomic operation, minimizing lock duration.
      #
      # @param client_group_id [String] The client group ID
      # @param client_id [String] The client ID
      # @return [Integer] The new last mutation ID (post-increment)
      def fetch_and_increment(client_group_id, client_id)
        table = model_class.quoted_table_name
        sql = model_class.sanitize_sql_array([<<~SQL.squish, {client_group_id:, client_id:}])
          INSERT INTO #{table} ("clientGroupID", "clientID", "lastMutationID")
          VALUES (:client_group_id, :client_id, 1)
          ON CONFLICT ("clientGroupID", "clientID")
          DO UPDATE SET "lastMutationID" = #{table}."lastMutationID" + 1
          RETURNING "lastMutationID"
        SQL

        model_class.connection.select_value(sql)
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
        ZeroRuby::ZeroClient
      end
    end
  end
end
