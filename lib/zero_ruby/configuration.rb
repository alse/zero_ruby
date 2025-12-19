# frozen_string_literal: true

module ZeroRuby
  # Configuration class for ZeroRuby.
  #
  # @example
  #   ZeroRuby.configure do |config|
  #     config.lmid_store = :active_record
  #     config.max_retry_attempts = 3
  #   end
  class Configuration
    # LMID (Last Mutation ID) tracking settings
    # The LMID store backend: :active_record or a custom LmidStore instance
    attr_accessor :lmid_store

    # Maximum retry attempts for ApplicationError during mutation processing
    attr_accessor :max_retry_attempts

    # The push version supported by this configuration
    attr_accessor :supported_push_version

    def initialize
      @lmid_store = :active_record
      @max_retry_attempts = 3
      @supported_push_version = 1
    end

    # Get the configured LMID store instance
    # @return [LmidStore] The LMID store instance
    def lmid_store_instance
      case @lmid_store
      when :active_record
        LmidStores::ActiveRecordStore.new
      when LmidStore
        @lmid_store
      else
        raise ArgumentError, "Unknown LMID store: #{@lmid_store.inspect}. Use :active_record or pass a custom LmidStore instance."
      end
    end
  end

  class << self
    attr_writer :configuration

    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration)
    end

    def reset_configuration!
      @configuration = Configuration.new
    end
  end
end
