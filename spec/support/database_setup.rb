# frozen_string_literal: true

require "active_record"

module ZeroRuby
  module TestHelpers
    module DatabaseSetup
      class << self
        def connect!
          # Use TEST_DATABASE_NAME for tests, default to localhost
          # This ignores DATABASE_URL and other production env vars
          database_name = ENV.fetch("TEST_DATABASE_NAME") {
            ENV.fetch("DATABASE_NAME", "zero_ruby_test")
          }

          ActiveRecord::Base.establish_connection(
            adapter: "postgresql",
            database: database_name,
            host: ENV.fetch("TEST_DATABASE_HOST", "localhost"),
            port: ENV.fetch("TEST_DATABASE_PORT", "5432").to_i,
            username: ENV["TEST_DATABASE_USER"],
            password: ENV["TEST_DATABASE_PASSWORD"]
          )
        end

        def setup_schema!
          connection = ActiveRecord::Base.connection

          # Create the zero_0 schema if it doesn't exist
          connection.execute("CREATE SCHEMA IF NOT EXISTS zero_0")

          # Create the clients table matching zero-cache's schema
          connection.execute(<<~SQL)
            CREATE TABLE IF NOT EXISTS zero_0.clients (
              "clientGroupID" TEXT NOT NULL,
              "clientID" TEXT NOT NULL,
              "lastMutationID" BIGINT NOT NULL DEFAULT 0,
              "userID" TEXT,
              PRIMARY KEY ("clientGroupID", "clientID")
            )
          SQL
        end

        def truncate!
          ActiveRecord::Base.connection.execute("TRUNCATE TABLE zero_0.clients")
        end
      end
    end
  end
end
