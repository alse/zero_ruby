# frozen_string_literal: true

module ZeroRuby
  # Processes Zero push requests with LMID tracking, version validation,
  # and transaction support. This implements the same protocol as
  # Zero's TypeScript implementation.
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
    attr_reader :schema, :lmid_store

    # @param schema [Class] The schema class for mutation processing
    # @param lmid_store [LmidStore] The LMID store instance
    def initialize(schema:, lmid_store:)
      @schema = schema
      @lmid_store = lmid_store
    end

    # Process a Zero push request
    #
    # @param push_data [Hash] The parsed push request body
    # @param context [Hash] Context to pass to mutations
    # @return [Hash] The response hash
    def process(push_data, context)
      client_group_id = push_data["clientGroupID"]
      mutations = push_data["mutations"] || []
      results = []

      mutations.each_with_index do |mutation_data, index|
        result = process_mutation_with_lmid(mutation_data, client_group_id, context)
        results << result
      rescue OutOfOrderMutationError => e
        # Return top-level PushFailedBody with all unprocessed mutation IDs
        unprocessed_ids = mutations[index..].map { |m| {id: m["id"], clientID: m["clientID"]} }
        return {
          kind: "PushFailed",
          origin: "server",
          reason: "oooMutation",
          message: e.message,
          mutationIDs: unprocessed_ids
        }
      rescue TransactionError => e
        # Database errors trigger top-level PushFailed per Zero protocol
        unprocessed_ids = mutations[index..].map { |m| {id: m["id"], clientID: m["clientID"]} }
        return {
          kind: "PushFailed",
          origin: "server",
          reason: "database",
          message: e.message,
          mutationIDs: unprocessed_ids
        }
      end

      {mutations: results}
    end

    private

    # Process a single mutation with LMID validation, transaction support, and phase tracking.
    #
    # The Mutation#call method decides whether to auto-wrap execute in a transaction
    # (default behavior) or pass control to user code (skip_auto_transaction mode).
    #
    # Phase tracking enables correct LMID semantics:
    # - Pre-transaction error: LMID advanced in separate transaction
    # - Transaction error: LMID advanced in separate transaction (original tx rolled back)
    # - Post-commit error: LMID already committed with transaction
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
          last_mutation_id = lmid_store.fetch_and_increment(client_group_id, client_id)
          check_lmid!(client_id, mutation_id, last_mutation_id)
          user_block.call
        end
        phase = :post_commit
        result
      }

      result = schema.execute_mutation(mutation_data, context, &transact_proc)
      {id: mutation_id_obj, result: result}
    rescue MutationNotFoundError, MutationAlreadyProcessedError => e
      # Known skip conditions - return error response, batch continues
      {id: mutation_id_obj, result: format_error_response(e)}
    rescue OutOfOrderMutationError, TransactionError
      # Batch-terminating errors - bubble up to process() for PushFailed response
      raise
    rescue ZeroRuby::Error => e
      # Application errors - advance LMID based on phase, return error response
      # Pre-transaction/transaction: LMID advanced separately
      # Post-commit: LMID already committed with transaction
      if phase != :post_commit
        persist_lmid_on_application_error(client_group_id, client_id)
      end
      {id: mutation_id_obj, result: format_error_response(e)}
    rescue => e
      # Unexpected errors - wrap and bubble up as batch-terminating
      raise TransactionError.new("Transaction failed: #{e.message}")
    end

    # Persist LMID advancement after an application error.
    # Called for pre-transaction and transaction errors to prevent replay attacks.
    def persist_lmid_on_application_error(client_group_id, client_id)
      lmid_store.transaction do
        lmid_store.fetch_and_increment(client_group_id, client_id)
      end
    rescue => e
      warn "Failed to persist LMID after application error: #{e.message}"
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
          last_mutation_id: last_mutation_id - 1
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
      result = {error: error.error_type}

      case error
      when ValidationError
        result[:message] = error.message
        result[:details] = {messages: error.errors}
      when MutationAlreadyProcessedError
        result[:details] = error.message
      else
        result[:message] = error.message
        result[:details] = error.details if error.details
      end

      result
    end
  end
end
