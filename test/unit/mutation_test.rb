# frozen_string_literal: true

require_relative "../test_helper"

# Test mutation class
class TestMutation < ZeroRuby::Mutation
  argument :name, ZeroRuby::Types::String, required: true
  argument :count, ZeroRuby::Types::Integer, required: false, default: 1
  argument :title, ZeroRuby::Types::String, required: true, validates: {length: {maximum: 50}}

  attr_reader :received_args

  def execute(name:, count:, title:)
    @received_args = {name: name, count: count, title: title}
  end
end

# Test mutation with false/nil defaults
class FalsyDefaultMutation < ZeroRuby::Mutation
  argument :name, ZeroRuby::Types::String, required: true
  argument :enabled, ZeroRuby::Types::Boolean, required: false, default: false
  argument :disabled, ZeroRuby::Types::Boolean, required: false  # no default

  attr_reader :received_args

  def execute(name:, enabled:, disabled:)
    @received_args = {name: name, enabled: enabled, disabled: disabled}
  end
end

class MutationTest < Minitest::Test
  def setup
    @ctx = {current_user: OpenStruct.new(id: 1), request_id: "req-123"}.freeze
  end

  def test_mutation_coerces_arguments
    mutation = TestMutation.new({name: "test", title: "Hello"}, @ctx)
    mutation.call
    assert_equal "test", mutation.received_args[:name]
    assert_equal "Hello", mutation.received_args[:title]
  end

  def test_mutation_applies_default_values
    mutation = TestMutation.new({name: "test", title: "Hello"}, @ctx)
    mutation.call
    assert_equal 1, mutation.received_args[:count]
  end

  def test_mutation_executes_successfully
    mutation = TestMutation.new({name: "test", title: "Hello"}, @ctx)
    result = mutation.call
    assert_equal({}, result)
  end

  def test_mutation_raises_on_missing_required_argument
    error = assert_raises(ZeroRuby::ValidationError) do
      TestMutation.new({title: "Hello"}, @ctx)
    end
    assert_includes error.errors, "name is required"
  end

  def test_mutation_raises_on_validation_failure
    long_title = "x" * 51
    error = assert_raises(ZeroRuby::ValidationError) do
      TestMutation.new({name: "test", title: long_title}, @ctx)
    end
    assert error.errors.any? { |e| e.include?("too long") }
  end

  def test_mutation_has_access_to_context
    mutation = TestMutation.new({name: "test", title: "Hello"}, @ctx)
    assert_equal 1, mutation.ctx[:current_user].id
    assert_equal "req-123", mutation.ctx[:request_id]
  end

  def test_mutation_coerces_integer_from_string
    mutation = TestMutation.new({name: "test", count: "5", title: "Hello"}, @ctx)
    mutation.call
    assert_equal 5, mutation.received_args[:count]
  end

  def test_mutation_applies_false_as_default
    mutation = FalsyDefaultMutation.new({name: "test"}, @ctx)
    mutation.call
    assert_equal false, mutation.received_args[:enabled]
  end

  def test_mutation_distinguishes_false_default_from_no_default
    # :enabled has default: false, :disabled has no default
    enabled_arg = FalsyDefaultMutation.arguments[:enabled]
    disabled_arg = FalsyDefaultMutation.arguments[:disabled]

    assert enabled_arg.has_default?, "enabled should have a default"
    refute disabled_arg.has_default?, "disabled should not have a default"
    assert_equal false, enabled_arg.default
    assert_nil disabled_arg.default
  end
end
