# frozen_string_literal: true

module ZeroRuby
  # Abstract base class for LMID (Last Mutation ID) storage backends.
  # Implementations must provide thread-safe access to client mutation IDs.
  #
  # This follows the same atomic increment pattern as Zero's TypeScript implementation.
  # @see https://github.com/rocicorp/mono/blob/main/packages/zero-server/src/zql-database.ts
  #
  # @example Custom store implementation
  #   class RedisLmidStore < ZeroRuby::LmidStore
  #     def fetch_and_increment(client_group_id, client_id)
  #       # Atomically increment and return the new last mutation ID
  #     end
  #
  #     def transaction
  #       # Redis MULTI/EXEC
  #     end
  #   end
  class LmidStore
    # Atomically increment and return the last mutation ID for a client.
    # Creates the record with ID 1 if it doesn't exist.
    #
    # This must be atomic to prevent race conditions - the increment and
    # return should happen in a single operation.
    #
    # @param client_group_id [String] The client group ID
    # @param client_id [String] The client ID
    # @param upstream_schema [String] Postgres schema name owned by zero-cache (e.g. "zero_0")
    # @return [Integer] The new last mutation ID (post-increment)
    def fetch_and_increment(client_group_id, client_id, upstream_schema:)
      raise NotImplementedError, "#{self.class}#fetch_and_increment must be implemented"
    end

    # Execute a block within a transaction.
    # The transaction should support rollback on error.
    #
    # @yield The block to execute within the transaction
    # @return The result of the block
    def transaction(&block)
      raise NotImplementedError, "#{self.class}#transaction must be implemented"
    end

    # Persist a mutation result so clients can read it via replication.
    # Used to surface error results back to the client.
    #
    # @param client_group_id [String] The client group ID
    # @param client_id [String] The client ID
    # @param mutation_id [Integer] The mutation ID
    # @param result [Hash, String] The mutation result to persist
    # @param upstream_schema [String] Postgres schema name owned by zero-cache (e.g. "zero_0")
    def write_mutation_result(client_group_id, client_id, mutation_id, result, upstream_schema:)
      raise NotImplementedError, "#{self.class}#write_mutation_result must be implemented"
    end

    # Delete mutation results, called by _zero_cleanupResults to remove acknowledged results.
    #
    # @param args [Hash] Cleanup arguments from the _zero_cleanupResults mutation.
    #   For legacy (no "type") and explicit single ({"type" => "single"}):
    #     { "clientGroupID" => String, "clientID" => String, "upToMutationID" => Integer }
    #   For bulk format:
    #     { "type" => "bulk", "clientGroupID" => String, "clientIDs" => Array<String> }
    # @param upstream_schema [String] Postgres schema name owned by zero-cache (e.g. "zero_0")
    def delete_mutation_results(args, upstream_schema:)
      raise NotImplementedError, "#{self.class}#delete_mutation_results must be implemented"
    end
  end
end
