# frozen_string_literal: true

module ZeroRuby
  # ZeroClient model for LMID (Last Mutation ID) tracking.
  # Interfaces with Zero's <upstream_schema>.clients table, which is
  # automatically created and managed by zero-cache. The default
  # `table_name = "zero_0.clients"` matches Zero's out-of-the-box
  # `ZERO_APP_ID=zero` / `ZERO_SHARD_NUM=0` configuration.
  #
  # The model's `table_name` is only used for direct ActiveRecord access
  # (e.g. `ZeroClient.find_by(...)`). The ActiveRecordStore writes its
  # SQL against the schema name passed at request time, so deployments
  # with a non-default `ZERO_APP_ID` / `ZERO_SHARD_NUM` work without
  # mutating this model.
  #
  # Table schema (created by zero-cache):
  #   clientGroupID  TEXT    - The client group identifier
  #   clientID       TEXT    - The client identifier
  #   lastMutationID BIGINT  - The last processed mutation ID for this client
  #   userID         TEXT    - The user identifier (optional)
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
