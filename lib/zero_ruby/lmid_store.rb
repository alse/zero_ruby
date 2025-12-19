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
    # @return [Integer] The new last mutation ID (post-increment)
    def fetch_and_increment(client_group_id, client_id)
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
  end
end
