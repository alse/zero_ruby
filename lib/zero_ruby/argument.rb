# frozen_string_literal: true

module ZeroRuby
  # Represents a declared argument for a mutation.
  # Holds type, required status, and validation configuration.
  class Argument
    # Sentinel value to distinguish "no default provided" from "default is nil"
    NOT_PROVIDED = Object.new.freeze

    # Maps Ruby built-in classes to ZeroRuby types.
    # This allows using String, Integer, Float directly in argument declarations.
    RUBY_TYPE_MAP = {
      ::String => -> { ZeroRuby::Types::String },
      ::Integer => -> { ZeroRuby::Types::Integer },
      ::Float => -> { ZeroRuby::Types::Float }
    }.freeze

    attr_reader :name, :type, :required, :validators, :default, :description

    def initialize(name:, type:, required: true, validates: nil, default: NOT_PROVIDED, description: nil, **options)
      @name = name.to_sym
      @type = resolve_type(type)
      @required = required
      @validators = validates || {}
      @has_default = default != NOT_PROVIDED
      @default = @has_default ? default : nil
      @description = description
      @options = options
    end

    def required?
      @required
    end

    def optional?
      !@required
    end

    def has_default?
      @has_default
    end

    # Coerce and validate a raw input value
    # @param raw_value [Object] The raw input value
    # @param ctx [Hash] The context hash
    # @return [Object] The coerced value
    def coerce(raw_value, ctx = nil)
      value = (raw_value.nil? && has_default?) ? @default : raw_value

      # Handle InputObject types (they use .coerce instead of .coerce_input)
      if input_object_type?
        @type.coerce(value, ctx)
      else
        @type.coerce_input(value, ctx)
      end
    end

    private

    # Resolve a type reference to a ZeroRuby type.
    # Handles Ruby built-in classes (String, Integer, Float) by mapping them
    # to the corresponding ZeroRuby::Types class.
    def resolve_type(type)
      if RUBY_TYPE_MAP.key?(type)
        RUBY_TYPE_MAP[type].call
      else
        type
      end
    end

    def input_object_type?
      defined?(ZeroRuby::InputObject) && @type.is_a?(Class) && @type < ZeroRuby::InputObject
    end
  end
end
