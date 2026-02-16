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

          # Create the mutations table matching zero-cache's schema
          connection.execute(<<~SQL)
            CREATE TABLE IF NOT EXISTS zero_0.mutations (
              "clientGroupID" TEXT NOT NULL,
              "clientID" TEXT NOT NULL,
              "mutationID" BIGINT NOT NULL,
              "result" JSON NOT NULL,
              PRIMARY KEY ("clientGroupID", "clientID", "mutationID")
            )
          SQL
        end

        def truncate!
          ActiveRecord::Base.connection.execute("TRUNCATE TABLE zero_0.clients, zero_0.mutations")
        end
      end
    end

    module MutationResultHelpers
      def get_mutation_result(client_group_id, client_id, mutation_id)
        sql = ActiveRecord::Base.sanitize_sql_array([<<~SQL.squish, {client_group_id:, client_id:, mutation_id:}])
          SELECT "result"::text FROM zero_0.mutations
          WHERE "clientGroupID" = :client_group_id
          AND "clientID" = :client_id
          AND "mutationID" = :mutation_id
        SQL
        ActiveRecord::Base.connection.select_value(sql)
      end

      def insert_mutation_result(client_group_id, client_id, mutation_id, result)
        result_json = result.to_json
        sql = ActiveRecord::Base.sanitize_sql_array([<<~SQL.squish, {client_group_id:, client_id:, mutation_id:, result: result_json}])
          INSERT INTO zero_0.mutations ("clientGroupID", "clientID", "mutationID", "result")
          VALUES (:client_group_id, :client_id, :mutation_id, :result::text::json)
        SQL
        ActiveRecord::Base.connection.execute(sql)
      end
    end
  end
end
