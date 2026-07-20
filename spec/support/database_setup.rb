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

        # Create zero-cache's tables under the given upstream schema.
        # Defaults to "zero_0" (matches ZERO_APP_ID=zero, ZERO_SHARD_NUM=0).
        def setup_schema!(name = "zero_0")
          connection = ActiveRecord::Base.connection
          quoted = connection.quote_column_name(name)

          connection.execute("CREATE SCHEMA IF NOT EXISTS #{quoted}")

          connection.execute(<<~SQL)
            CREATE TABLE IF NOT EXISTS #{quoted}.clients (
              "clientGroupID" TEXT NOT NULL,
              "clientID" TEXT NOT NULL,
              "lastMutationID" BIGINT NOT NULL DEFAULT 0,
              "userID" TEXT,
              PRIMARY KEY ("clientGroupID", "clientID")
            )
          SQL

          connection.execute(<<~SQL)
            CREATE TABLE IF NOT EXISTS #{quoted}.mutations (
              "clientGroupID" TEXT NOT NULL,
              "clientID" TEXT NOT NULL,
              "mutationID" BIGINT NOT NULL,
              "result" JSON NOT NULL,
              PRIMARY KEY ("clientGroupID", "clientID", "mutationID")
            )
          SQL
        end

        def truncate!(name = "zero_0")
          conn = ActiveRecord::Base.connection
          quoted = conn.quote_column_name(name)
          conn.execute("TRUNCATE TABLE #{quoted}.clients, #{quoted}.mutations")
        end
      end
    end

    module MutationResultHelpers
      def get_mutation_result(client_group_id, client_id, mutation_id, schema: "zero_0")
        conn = ActiveRecord::Base.connection
        table = "#{conn.quote_column_name(schema)}.#{conn.quote_column_name("mutations")}"
        sql = ActiveRecord::Base.sanitize_sql_array([<<~SQL.squish, {client_group_id:, client_id:, mutation_id:}])
          SELECT "result"::text FROM #{table}
          WHERE "clientGroupID" = :client_group_id
          AND "clientID" = :client_id
          AND "mutationID" = :mutation_id
        SQL
        conn.select_value(sql)
      end

      def insert_mutation_result(client_group_id, client_id, mutation_id, result, schema: "zero_0")
        conn = ActiveRecord::Base.connection
        table = "#{conn.quote_column_name(schema)}.#{conn.quote_column_name("mutations")}"
        result_json = result.to_json
        sql = ActiveRecord::Base.sanitize_sql_array([<<~SQL.squish, {client_group_id:, client_id:, mutation_id:, result: result_json}])
          INSERT INTO #{table} ("clientGroupID", "clientID", "mutationID", "result")
          VALUES (:client_group_id, :client_id, :mutation_id, :result::text::json)
        SQL
        conn.execute(sql)
      end
    end
  end
end
