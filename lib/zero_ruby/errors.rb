# frozen_string_literal: true

module ZeroRuby
  class Error < StandardError
    attr_reader :details

    def initialize(message = nil, details: nil)
      @details = details
      super(message)
    end

    # Returns the Zero protocol error type string
    def error_type
      "app"
    end
  end

  class ValidationError < Error
    attr_reader :errors

    def initialize(errors)
      @errors = Array(errors)
      super(@errors.join(", "))
    end
  end

  # Raised when a value cannot be coerced to the expected type
  class CoercionError < Error
    attr_reader :value, :expected_type

    def initialize(message, value: nil, expected_type: nil)
      @value = value
      @expected_type = expected_type
      super(message)
    end
  end

  # Raised when a mutation is not found in the schema
  class MutationNotFoundError < Error
    attr_reader :mutation_name

    def initialize(mutation_name)
      @mutation_name = mutation_name
      super("Unknown mutation: #{mutation_name}")
    end
  end

  # Raised when pushVersion is not supported
  class UnsupportedPushVersionError < Error
    attr_reader :received_version, :supported_version

    def initialize(received_version, supported_version: 1)
      @received_version = received_version
      @supported_version = supported_version
      super("Unsupported push version: #{received_version}. Expected: #{supported_version}")
    end
  end

  # Raised when a mutation has already been processed (duplicate)
  class MutationAlreadyProcessedError < Error
    attr_reader :client_id, :received_id, :last_mutation_id

    def initialize(client_id:, received_id:, last_mutation_id:)
      @client_id = client_id
      @received_id = received_id
      @last_mutation_id = last_mutation_id
      super("Mutation #{received_id} already processed for client #{client_id}. Last mutation ID: #{last_mutation_id}")
    end

    def error_type
      "alreadyProcessed"
    end
  end

  # Raised when mutations arrive out of order
  class OutOfOrderMutationError < Error
    attr_reader :client_id, :received_id, :expected_id

    def initialize(client_id:, received_id:, expected_id:)
      @client_id = client_id
      @received_id = received_id
      @expected_id = expected_id
      super("Client #{client_id} sent mutation ID #{received_id} but expected #{expected_id}")
    end

    def error_type
      "ooo"
    end
  end
end
