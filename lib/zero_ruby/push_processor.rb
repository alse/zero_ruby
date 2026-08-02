# frozen_string_literal: true

require "json"

module ZeroRuby
  # Processes Zero push requests with LMID tracking, version validation,
  # and transaction support. This implements the same protocol as
  # Zero's TypeScript implementation (zero-server v1.8).
  #
  # @example Basic usage
  #   processor = PushProcessor.new(
  #     schema: ZeroSchema,
  #     lmid_store: ZeroRuby.configuration.lmid_store_instance
  #   )
  #   result = processor.process(push_data, context)
  #
  # @see https://github.com/rocicorp/mono/blob/main/packages/zero-server/src/process-mutations.ts
  # @see https://github.com/rocicorp/mono/blob/main/packages/zero-server/src/zql-database.ts
  class PushProcessor
    attr_reader :schema, :lmid_store, :user_id, :upstream_schema

    # @param schema [Class] The schema class for mutation processing
    # @param lmid_store [LmidStore] The LMID store instance
    # @param user_id [String, nil] Authenticated user ID echoed in MutateResponse.
    #   Should be derived from server-verified credentials (e.g. a JWT subject),
    #   not from request body data.
    # @param user_id_provided [Boolean, nil] Whether the caller explicitly
    #   determined the user identity. When true and user_id is nil, the
    #   response includes "userID": null (an explicit "logged out" assertion
    #   that zero-cache treats as server-validated). When false/nil with a nil
    #   user_id, userID is omitted and zero-cache falls back to the
    #   client-claimed identity.
    # @param upstream_schema [String] Postgres schema name owned by zero-cache.
    #   Defaults to "zero_0" (the default ZERO_APP_ID=zero, ZERO_SHARD_NUM=0).
    #   zero-cache sends the actual value via the "schema" query parameter.
    def initialize(schema:, lmid_store:, user_id: nil, user_id_provided: nil, upstream_schema: "zero_0")
      @schema = schema
      @lmid_store = lmid_store
      @user_id = user_id
      @user_id_provided = user_id_provided.nil? ? !user_id.nil? : user_id_provided
      @upstream_schema = upstream_schema
    end

    # Process a Zero push request
    #
    # @param push_data [Hash] The parsed push request body
    # @param context [Hash] Context to pass to mutations
    # @return [Hash] The response hash. On success:
    #   {kind: "MutateResponse", mutations: [...], userID: "..."} (userID
    #   omitted unless the user identity was provided).
    #   On failure: {kind: "PushFailed", ...}.
    def process(push_data, context)
      client_group_id = push_data["clientGroupID"]
      mutations = push_data["mutations"] || []
      results = []

      mutations.each_with_index do |mutation_data, index|
        mutation_type = mutation_data["type"]

        if mutation_data["name"] == "_zero_cleanupResults" && (mutation_type.nil? || mutation_type == "custom")
          handle_cleanup_results(mutation_data)
          next
        end

        # The reference asserts m.type === 'custom'; CRUD mutations abort the
        # push with PushFailed{internal} via the catch-all below.
        if !mutation_type.nil? && mutation_type != "custom"
          raise InternalError.new("Expected custom mutation")
        end

        result = process_mutation_with_lmid(mutation_data, client_group_id, context)
        results << result
      rescue OutOfOrderMutationError => e
        return push_failed_body("oooMutation", e, mutations[index..])
      rescue TransactionError => e
        return push_failed_body("database", e, mutations[index..])
      rescue StandardError, ScriptError, SystemStackError => e
        # Anything else that escapes per-mutation handling maps to the
        # reference implementation's catch-all: PushFailed{reason: "internal"}.
        # ScriptError/SystemStackError are included because the reference's
        # try/catch catches every throwable; process-control exceptions
        # (SignalException, SystemExit, NoMemoryError) still propagate.
        return push_failed_body("internal", e, mutations[index..])
      end

      response = {kind: "MutateResponse", mutations: results}
      response[:userID] = @user_id if @user_id_provided
      response
    end

    private

    # Build a top-level PushFailedBody listing all unprocessed mutation IDs
    # (including the failing mutation itself).
    def push_failed_body(reason, error, unprocessed_mutations)
      body = {
        kind: "PushFailed",
        origin: "server",
        reason: reason,
        message: error.message,
        mutationIDs: unprocessed_mutations.map { |m| {id: m["id"], clientID: m["clientID"]} }
      }
      details = error.respond_to?(:details) ? error.details : nil
      body[:details] = details if emit_details?(details)
      body
    end

    # The reference guards details emission with JS truthiness
    # (`details ? {details} : {}`), so falsy JSON values (null, false, 0, "",
    # NaN) are omitted while empty arrays/objects are kept.
    def emit_details?(details)
      return false if details.nil? || details == false || details == "" || details == 0
      return false if details.is_a?(Float) && details.nan?
      true
    end

    # Process a single mutation with LMID validation, transaction support, and
    # phase tracking, mirroring the three-phase model of the TS reference:
    #
    # - Pre-transaction error: LMID advanced + error persisted in a separate
    #   transaction; per-mutation app error result.
    # - Transaction error: the reference retries the transaction once WITHOUT
    #   the mutator, advancing the LMID and persisting the error result. Our
    #   persist_mutation_failure call is that retry. If it succeeds the
    #   mutation is skipped with an app error result; if it fails the push
    #   aborts (PushFailed{database}), except an alreadyProcessed race which
    #   yields an alreadyProcessed result and an out-of-order race which
    #   aborts with PushFailed{oooMutation}.
    # - Post-commit error: LMID already committed; app error result, nothing
    #   persisted.
    def process_mutation_with_lmid(mutation_data, client_group_id, context)
      mutation_id = mutation_data["id"]
      client_id = mutation_data["clientID"]
      mutation_id_obj = {id: mutation_id, clientID: client_id}
      mutation_name = mutation_data["name"]

      handler_class = schema.handler_for(mutation_name)
      raise MutationNotFoundError.new(mutation_name) unless handler_class

      phase = :pre_transaction

      transact_proc = proc { |&user_block|
        phase = :transaction
        result = lmid_store.transaction do
          last_mutation_id = lmid_store.fetch_and_increment(client_group_id, client_id, upstream_schema: @upstream_schema)
          check_lmid!(client_id, mutation_id, last_mutation_id)
          begin
            user_block.call
          rescue ZeroRuby::Error
            raise
          rescue StandardError, ScriptError, SystemStackError => e
            raise ZeroRuby::Error.new(e.message, details: extract_details(e))
          end
        end
        phase = :post_commit
        result
      }

      result = schema.execute_mutation(mutation_data, context, &transact_proc)
      {id: mutation_id_obj, result: result}
    rescue MutationAlreadyProcessedError => e
      # Duplicate mutation - return error result, batch continues. The
      # transaction that detected the duplicate rolled back its increment.
      {id: mutation_id_obj, result: format_error_response(e)}
    rescue OutOfOrderMutationError, TransactionError
      # Batch-terminating errors - bubble up to process() for PushFailed response
      raise
    rescue MutationNotFoundError => e
      # The reference resolves the mutator inside the transaction, after the
      # LMID check (zero-server PushProcessor#processMutation), so an unknown
      # mutation follows the transaction-failure path: the LMID advances and
      # the app error result is persisted, permanently skipping the mutation.
      # A redelivered duplicate yields an alreadyProcessed result instead of
      # aborting the push.
      error_response = format_error_response(e)
      resolved = resolve_failure_persistence(:transaction, client_group_id, client_id, mutation_id, error_response)
      {id: mutation_id_obj, result: resolved}
    rescue ZeroRuby::Error => e
      # Application errors - advance LMID based on phase, return error response
      error_response = format_error_response(e)
      resolved = resolve_failure_persistence(phase, client_group_id, client_id, mutation_id, error_response)
      {id: mutation_id_obj, result: resolved}
    rescue StandardError, ScriptError, SystemStackError => e
      # Infrastructure/unexpected errors. The reference wraps these as
      # application errors and (except post-commit) retries once without the
      # mutator; only a failing retry aborts the push.
      error_response = {error: "app", message: e.message}
      details = extract_details(e)
      error_response[:details] = details if emit_details?(details)
      resolved = resolve_failure_persistence(phase, client_group_id, client_id, mutation_id, error_response)
      {id: mutation_id_obj, result: resolved}
    end

    # Advance the LMID and persist the error result according to the phase the
    # failure occurred in. Returns the mutation result to respond with.
    def resolve_failure_persistence(phase, client_group_id, client_id, mutation_id, error_response)
      case phase
      when :post_commit
        # LMID already committed with the transaction; nothing to persist.
        error_response
      when :transaction
        # Retry without the mutator. An alreadyProcessed race during the
        # retry becomes the mutation's result (reference: Transactor#transact).
        begin
          persist_mutation_failure(client_group_id, client_id, mutation_id, error_response)
          error_response
        rescue MutationAlreadyProcessedError => e
          format_error_response(e)
        end
      else # :pre_transaction
        # Reference: persistPreTransactionFailure. An alreadyProcessed race
        # here is not caught and maps to PushFailed{internal} upstream, so we
        # let it propagate to process()'s catch-all.
        persist_mutation_failure(client_group_id, client_id, mutation_id, error_response)
        error_response
      end
    end

    # Persist LMID advancement and mutation error result after a failure, in
    # one transaction (the reference's "retry without mutator"). Re-checks the
    # LMID like the reference does:
    # - MutationAlreadyProcessedError propagates (handled per phase by caller)
    # - OutOfOrderMutationError propagates (batch aborts with PushFailed{oooMutation})
    # - other failures escalate to TransactionError (PushFailed{database});
    #   silently losing the LMID advance would desync the client.
    def persist_mutation_failure(client_group_id, client_id, mutation_id, error_result)
      opened = false
      lmid_store.transaction do
        opened = true
        last_mutation_id = lmid_store.fetch_and_increment(client_group_id, client_id, upstream_schema: @upstream_schema)
        check_lmid!(client_id, mutation_id, last_mutation_id)
        lmid_store.write_mutation_result(client_group_id, client_id, mutation_id, error_result, upstream_schema: @upstream_schema)
      end
    rescue MutationAlreadyProcessedError, OutOfOrderMutationError, TransactionError
      raise
    rescue StandardError, ScriptError, SystemStackError => e
      warn "[ZeroRuby] Failed to persist mutation failure for " \
           "client_group=#{client_group_id} client=#{client_id} mutation=#{mutation_id}: " \
           "#{e.class}: #{e.message}"
      # Message and details mirror the reference's DatabaseTransactionError
      # (process-mutations.ts), which zero-cache forwards to the client.
      message = if opened
        "Database transaction failed after opening: #{e.message}"
      else
        "Failed to open database transaction: #{e.message}"
      end
      raise TransactionError.new(message, details: {name: "DatabaseTransactionError"})
    end

    # Handle _zero_cleanupResults mutations by deleting acknowledged results.
    # Errors are caught and logged as warnings without propagating, matching
    # the Zero protocol behavior where cleanup failures must not abort the push batch.
    def handle_cleanup_results(mutation_data)
      args = mutation_data["args"]
      args = args.first if args.is_a?(Array)
      unless valid_cleanup_args?(args)
        warn "[ZeroRuby] _zero_cleanupResults: invalid args: #{args.inspect}"
        return
      end
      lmid_store.transaction do
        lmid_store.delete_mutation_results(args, upstream_schema: @upstream_schema)
      end
    rescue StandardError, ScriptError, SystemStackError => e
      warn "[ZeroRuby] _zero_cleanupResults failed for " \
           "clientGroupID=#{args&.dig("clientGroupID")}: #{e.class}: #{e.message}"
    end

    # Validate cleanup args against the shapes of Zero's cleanupResultsArgSchema:
    # - legacy (no type) / "single": {clientGroupID:, clientID:, upToMutationID:}
    # - "bulk": {clientGroupID:, clientIDs: [at least one]}
    # The reference validates in valita strict mode, so unknown extra keys
    # also invalidate the args (cleanup is skipped with a warning).
    def valid_cleanup_args?(args)
      return false unless args.is_a?(Hash) && args["clientGroupID"].is_a?(String)

      case args["type"]
      when "bulk"
        client_ids = args["clientIDs"]
        client_ids.is_a?(Array) && !client_ids.empty? && client_ids.all?(String) &&
          (args.keys - %w[type clientGroupID clientIDs]).empty?
      when "single", nil
        allowed = args.key?("type") ? %w[type clientGroupID clientID upToMutationID] : %w[clientGroupID clientID upToMutationID]
        args["clientID"].is_a?(String) && args["upToMutationID"].is_a?(Numeric) &&
          (args.keys - allowed).empty?
      else
        false
      end
    end

    # Validate LMID against the post-increment value.
    # The received mutation ID should equal the new last mutation ID.
    #
    # @raise [MutationAlreadyProcessedError] If mutation was already processed
    # @raise [OutOfOrderMutationError] If mutation arrived out of order
    def check_lmid!(client_id, received_id, last_mutation_id)
      if received_id < last_mutation_id
        raise MutationAlreadyProcessedError.new(
          client_id: client_id,
          received_id: received_id,
          last_mutation_id: last_mutation_id
        )
      elsif received_id > last_mutation_id
        raise OutOfOrderMutationError.new(
          client_id: client_id,
          received_id: received_id,
          expected_id: last_mutation_id
        )
      end
    end

    # Format an error into Zero protocol response
    def format_error_response(error)
      case error
      when ValidationError
        {error: "app", message: error.message, details: {messages: error.errors}}
      when MutationAlreadyProcessedError
        {error: "alreadyProcessed", details: error.message}
      else
        result = {error: error.error_type, message: error.message}
        result[:details] = error.details if emit_details?(error.details)
        result
      end
    end

    # Extract JSON-serializable details from arbitrary errors, mirroring the
    # reference's getErrorDetails (used by wrapWithApplicationError): use the
    # error's own details when serializable, else fall back to the error class
    # name for non-generic errors.
    def extract_details(error)
      if error.respond_to?(:details)
        begin
          details = error.details
          unless details.nil?
            JSON.generate(details) # verify serializability
            return details
          end
        rescue JSON::GeneratorError, Encoding::UndefinedConversionError
          # fall through to class-name fallback
        end
      end

      class_name = error.class.name
      return {name: class_name} unless ["RuntimeError", "StandardError"].include?(class_name)
      nil
    end
  end
end
