# frozen_string_literal: true

require "dry/schema"

module ZeroRuby
  # Formats Dry::Types and Dry::Struct errors into user-friendly messages
  # using dry-schema's built-in message templates.
  module ErrorFormatter
    # Get the dry-schema messages backend for English
    MESSAGES = Dry::Schema::Messages::YAML.build

    class << self
      # Format a Dry::Struct::Error into user-friendly messages
      # @param error [Dry::Struct::Error] The struct error
      # @return [Array<String>] Formatted error messages
      def format_struct_error(error)
        message = error.message

        if message.include?("is missing")
          match = message.match(/:(\w+) is missing/)
          field = match ? match[1] : "field"
          ["#{field} is required"]
        elsif message.include?("has invalid type")
          # Matches both ":title has invalid type" and "has invalid type for :title"
          match = message.match(/:(\w+) has invalid type/) ||
            message.match(/has invalid type for :(\w+)/)
          field = match ? match[1] : "field"
          ["#{field}: invalid type"]
        elsif message.include?("violates constraints")
          # Extract constraint info and format it
          [format_constraint_message(message)]
        else
          [message]
        end
      end

      # Format a Dry::Types::CoercionError into user-friendly message
      # @param error [Dry::Types::CoercionError] The coercion error
      # @return [String] Formatted error message
      def format_coercion_error(error)
        message = error.message
        input = error.respond_to?(:input) ? error.input : nil

        type = extract_type_name(message)
        if input
          value_str = format_value(input)
          "#{value_str} is not a valid #{type}"
        else
          lookup_message(:type?, type) || "must be a #{type}"
        end
      end

      # Format a Dry::Types::ConstraintError into user-friendly message
      # @param error [Dry::Types::ConstraintError] The constraint error
      # @return [String] Formatted error message
      def format_constraint_error(error)
        format_constraint_message(error.message)
      end

      private

      # Format a constraint violation message
      def format_constraint_message(message)
        # Parse predicate and args from messages like:
        # "max_size?(50, \"value\") failed" or "gt?(0, 0) failed"
        if (match = message.match(/(\w+\?)\(([^)]*)\)/))
          predicate = match[1]
          args_str = match[2]
          args = parse_args(args_str)

          lookup_message(predicate, *args) || fallback_message(predicate, args)
        else
          message
        end
      end

      # Look up a message from dry-schema's message templates
      def lookup_message(predicate, *args)
        # Convert predicate to symbol without ?
        key = predicate.to_s.chomp("?").to_sym

        # Try to get message from dry-schema
        begin
          result = MESSAGES.call(key, path: [:base], tokens: build_tokens(key, args))
          result&.text
        rescue
          nil
        end
      end

      # Build tokens hash for message interpolation
      def build_tokens(key, args)
        case key
        when :max_size, :min_size, :size
          {num: args[0]}
        when :gt, :gteq, :lt, :lteq
          {num: args[0]}
        when :included_in, :excluded_from
          {list: args[0]}
        when :format
          {format: args[0]}
        else
          {num: args[0]}
        end
      end

      # Fallback messages when dry-schema lookup fails
      def fallback_message(predicate, args)
        case predicate
        when "max_size?"
          "size cannot be greater than #{args[0]}"
        when "min_size?"
          "size cannot be less than #{args[0]}"
        when "gt?"
          "must be greater than #{args[0]}"
        when "gteq?"
          "must be greater than or equal to #{args[0]}"
        when "lt?"
          "must be less than #{args[0]}"
        when "lteq?"
          "must be less than or equal to #{args[0]}"
        when "included_in?"
          "must be one of: #{args[0]}"
        when "format?"
          "is in invalid format"
        when "filled?"
          "must be filled"
        else
          "is invalid"
        end
      end

      # Parse args from constraint error message
      def parse_args(args_str)
        # Simple parsing - split by comma and clean up
        args_str.split(",").map do |arg|
          arg = arg.strip
          if arg.start_with?('"') && arg.end_with?('"')
            arg[1..-2] # Remove quotes
          elsif arg.match?(/^-?\d+$/)
            arg.to_i
          elsif arg.match?(/^-?\d+\.\d+$/)
            arg.to_f
          else
            arg
          end
        end
      end

      # Extract type name from error message
      def extract_type_name(message)
        case message
        when /Integer/ then "integer"
        when /Float/ then "number"
        when /String/ then "string"
        when /Bool|TrueClass|FalseClass/ then "boolean"
        when /Date/ then "date"
        when /Array/ then "array"
        when /Hash/ then "object"
        else "value"
        end
      end

      # Format a value for display in error messages
      def format_value(value)
        return "nil" if value.nil?

        str = value.to_s
        (str.length > 50) ? "#{str[0, 50]}..." : str
      end
    end
  end
end
