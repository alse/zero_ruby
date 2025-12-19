# frozen_string_literal: true

module ZeroRuby
  # Abstract base class for LMID (Last Mutation ID) storage backends.
  # Implementations must provide thread-safe access to client mutation IDs.
  #
  # @example Custom store implementation
  #   class RedisLmidStore < ZeroRuby::LmidStore
  #     def fetch_with_lock(client_group_id, client_id)
  #       # Redis-based implementation with WATCH/MULTI
  #     end
  #
  #     def update(client_group_id, client_id, mutation_id)
  #       # Redis SET
  #     end
  #
  #     def transaction
  #       # Redis MULTI/EXEC
  #     end
  #   end
  class LmidStore
    # Fetch the last mutation ID for a client, acquiring a lock for update.
    # This should be called within a transaction to ensure atomicity.
    #
    # @param client_group_id [String] The client group ID
    # @param client_id [String] The client ID
    # @return [Integer, nil] The last mutation ID, or nil if not found (new client)
    def fetch_with_lock(client_group_id, client_id)
      raise NotImplementedError, "#{self.class}#fetch_with_lock must be implemented"
    end

    # Update the last mutation ID for a client.
    # Creates the record if it doesn't exist (upsert behavior).
    #
    # @param client_group_id [String] The client group ID
    # @param client_id [String] The client ID
    # @param mutation_id [Integer] The new last mutation ID
    # @return [void]
    def update(client_group_id, client_id, mutation_id)
      raise NotImplementedError, "#{self.class}#update must be implemented"
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
