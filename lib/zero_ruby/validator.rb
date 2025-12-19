# frozen_string_literal: true

module ZeroRuby
  # Base class for argument validators.
  # Inspired by graphql-ruby's validation system.
  class Validator
    class << self
      # Registry of validator classes by name
      def validators
        @validators ||= {}
      end

      # Register a validator class
      def register(name, klass)
        validators[name.to_sym] = klass
      end

      # Get a validator class by name
      def get(name)
        validators[name.to_sym]
      end

      # Run all validations on a value
      # @param validators_config [Hash] Configuration hash for validators
      # @param mutation [ZeroRuby::Mutation] The mutation instance
      # @param ctx [Hash] The context hash
      # @param value [Object] The value to validate
      # @return [Array<String>] Array of error messages
      def validate!(validators_config, mutation, ctx, value)
        return [] if validators_config.nil? || validators_config.empty?

        errors = []

        validators_config.each do |validator_name, config|
          validator_class = get(validator_name)
          next unless validator_class

          validator = validator_class.new(config)
          result = validator.validate(mutation, ctx, value)
          errors.concat(Array(result)) if result
        end

        errors
      end
    end

    attr_reader :config

    def initialize(config)
      @config = config
    end

    # Validate a value
    # @param mutation [ZeroRuby::Mutation] The mutation instance
    # @param ctx [Hash] The context hash
    # @param value [Object] The value to validate
    # @return [String, Array<String>, nil] Error message(s) or nil if valid
    def validate(mutation, ctx, value)
      raise NotImplementedError, "Subclasses must implement #validate"
    end

    protected

    # Helper to format error messages
    def error_message(message)
      message
    end
  end
end
