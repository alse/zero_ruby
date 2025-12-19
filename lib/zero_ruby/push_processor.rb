# frozen_string_literal: true

module ZeroRuby
  # Processes Zero push requests with LMID tracking, version validation,
  # and transaction support. This implements the same protocol as
  # Zero's process-mutations.ts.
  #
  # @example Basic usage
  #   processor = PushProcessor.new(
  #     schema: ZeroSchema,
  #     lmid_store: ZeroRuby.configuration.lmid_store_instance
  #   )
  #   result = processor.process(push_data, context)
  #
  # @see https://github.com/rocicorp/mono/blob/main/packages/zero-server/src/process-mutations.ts
  class PushProcessor
    attr_reader :schema, :lmid_store, :max_retries

    # @param schema [Class] The schema class for mutation processing
    # @param lmid_store [LmidStore] The LMID store instance
    # @param max_retries [Integer] Maximum retry attempts for retryable errors
    def initialize(schema:, lmid_store:, max_retries: 3)
      @schema = schema
      @lmid_store = lmid_store
      @max_retries = max_retries
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

      mutations.each do |mutation_data|
        result = process_mutation_with_lmid(mutation_data, client_group_id, context)
        results << result

        # If we hit an out-of-order error, stop processing the batch
        break if result[:result][:error] == "ooo"
      end

      {mutations: results}
    end

    private

    # Process a single mutation with LMID validation and transaction support
    def process_mutation_with_lmid(mutation_data, client_group_id, context)
      mutation_id = mutation_data["id"]
      client_id = mutation_data["clientID"]

      mutation_id_obj = {
        id: mutation_id,
        clientID: client_id
      }

      lmid_store.transaction do
        check_lmid!(client_group_id, client_id, mutation_id)

        result = execute_with_retry(mutation_data, context)
        lmid_store.update(client_group_id, client_id, mutation_id)

        {id: mutation_id_obj, result: result}
      end
    rescue ZeroRuby::Error => e
      {id: mutation_id_obj, result: format_error_response(e)}
    end

    # Validate LMID, raising on duplicate or out-of-order
    # @raise [MutationAlreadyProcessedError] If mutation was already processed
    # @raise [OutOfOrderMutationError] If mutation arrived out of order
    def check_lmid!(client_group_id, client_id, received_id)
      last_mutation_id = lmid_store.fetch_with_lock(client_group_id, client_id)
      last_mutation_id ||= 0
      expected_id = last_mutation_id + 1

      if received_id < expected_id
        raise MutationAlreadyProcessedError.new(
          client_id: client_id,
          received_id: received_id,
          last_mutation_id: last_mutation_id
        )
      elsif received_id > expected_id
        raise OutOfOrderMutationError.new(
          client_id: client_id,
          received_id: received_id,
          expected_id: expected_id
        )
      end
    end

    # Execute mutation with retry logic for app errors
    def execute_with_retry(mutation_data, context)
      attempts = 0

      loop do
        attempts += 1

        begin
          return schema.execute_mutation(mutation_data, context)
        rescue ZeroRuby::Error => e
          raise e unless attempts < max_retries
        end
      end
    end

    # Format an error into Zero protocol response
    def format_error_response(error)
      result = {error: error.error_type, message: error.message}

      case error
      when ValidationError
        result[:details] = {messages: error.errors}
      else
        result[:details] = error.details if error.details
      end

      result
    end
  end
end
