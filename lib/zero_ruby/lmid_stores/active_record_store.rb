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

      # Write a mutation result to the zero_0.mutations table.
      #
      # @param client_group_id [String] The client group ID
      # @param client_id [String] The client ID
      # @param mutation_id [Integer] The mutation ID
      # @param result [Hash, String] The mutation result. Hashes are serialized to JSON for storage.
      def write_mutation_result(client_group_id, client_id, mutation_id, result)
        result_json = begin
          result.is_a?(String) ? result : result.to_json
        rescue JSON::GeneratorError, Encoding::UndefinedConversionError
          {error: "app", message: "Error result could not be serialized"}.to_json
        end
        sql = model_class.sanitize_sql_array([<<~SQL.squish, {client_group_id:, client_id:, mutation_id:, result: result_json}])
          INSERT INTO zero_0.mutations ("clientGroupID", "clientID", "mutationID", "result")
          VALUES (:client_group_id, :client_id, :mutation_id, :result::text::json)
        SQL

        model_class.connection.execute(sql)
      end

      # Delete mutation results from the zero_0.mutations table.
      #
      # @param args [Hash] Cleanup arguments
      def delete_mutation_results(args)
        client_group_id = args["clientGroupID"]

        sql = if args["type"] == "bulk"
          client_ids = args["clientIDs"]
          model_class.sanitize_sql_array([<<~SQL.squish, {client_group_id:}])
            DELETE FROM zero_0.mutations
            WHERE "clientGroupID" = :client_group_id
            AND "clientID" = ANY(ARRAY[#{client_ids.map { |id| model_class.connection.quote(id) }.join(",")}])
          SQL
        else
          client_id = args["clientID"]
          up_to_mutation_id = args["upToMutationID"]
          model_class.sanitize_sql_array([<<~SQL.squish, {client_group_id:, client_id:, up_to_mutation_id:}])
            DELETE FROM zero_0.mutations
            WHERE "clientGroupID" = :client_group_id
            AND "clientID" = :client_id
            AND "mutationID" <= :up_to_mutation_id
          SQL
        end

        model_class.connection.execute(sql)
      end

      private

      def default_model_class
        ZeroRuby::ZeroClient
      end
    end
  end
end
