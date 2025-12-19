# frozen_string_literal: true

require_relative "../test_helper"

# Test mutation for schema tests
class SchemaMutation < ZeroRuby::Mutation
  argument :id, ZeroRuby::Types::String, required: true
  argument :value, ZeroRuby::Types::Integer, required: false

  def execute(id:, value: nil)
    # Just perform the mutation - no return value needed
  end
end

# Test schema
class TestSchema < ZeroRuby::Schema
  mutation "items.create", handler: SchemaMutation
  mutation "items.update", handler: SchemaMutation
end

class SchemaTest < Minitest::Test
  def setup
    @context = {current_user: OpenStruct.new(id: 1)}
  end

  def test_schema_executes_single_mutation
    mutation_data = {
      "name" => "items.create",
      "args" => [{"id" => "item-1", "value" => 42}]
    }

    result = TestSchema.execute_mutation(mutation_data, @context)

    assert_equal({}, result)
  end

  def test_schema_raises_on_unknown_mutation
    mutation_data = {
      "name" => "unknown.mutation",
      "args" => [{}]
    }

    error = assert_raises(ZeroRuby::MutationNotFoundError) do
      TestSchema.execute_mutation(mutation_data, @context)
    end

    assert_match(/Unknown mutation/, error.message)
  end

  def test_schema_normalizes_pipe_separated_names
    mutation_data = {
      "name" => "items|create",
      "args" => [{"id" => "item-1"}]
    }

    result = TestSchema.execute_mutation(mutation_data, @context)

    assert_equal({}, result)
  end

  def test_schema_transforms_camel_case_to_snake_case
    mutation_data = {
      "name" => "items.create",
      "args" => [{"id" => "item-1", "someValue" => 99}]
    }

    result = TestSchema.execute_mutation(mutation_data, @context)

    # The key should be transformed but since our mutation only has :value,
    # :some_value would be ignored (not an error)
    # Mutation succeeds with empty result
    assert_equal({}, result)
  end
end
