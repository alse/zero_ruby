# frozen_string_literal: true

module ZeroRuby
  # ZeroClient model for LMID (Last Mutation ID) tracking.
  # This model interfaces with Zero's zero_0.clients table, which is
  # automatically created and managed by zero-cache.
  #
  # Table Schema (created by zero-cache):
  #   clientGroupID  TEXT   - The client group identifier
  #   clientID       TEXT   - The client identifier
  #   lastMutationID INTEGER - The last processed mutation ID for this client
  #   userID         TEXT   - The user identifier (optional)
  #
  # @note Do NOT run migrations for this table - zero-cache manages it.
  # @see https://zero.rocicorp.dev/docs/mutators
  class ZeroClient < ActiveRecord::Base
    self.table_name = "zero_0.clients"
    self.primary_key = nil # Composite key: clientGroupID + clientID

    def readonly?
      # Allow updates through the LMID store's direct SQL
      false
    end
  end
end
