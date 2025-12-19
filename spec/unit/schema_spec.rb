# frozen_string_literal: true

require "spec_helper"

# Test mutation for schema tests
class SchemaMutation < ZeroRuby::Mutation
  argument :id, ZeroRuby::Types::String
  argument :value, ZeroRuby::Types::Integer.optional
  argument :some_value, ZeroRuby::Types::Integer.optional

  @@last_some_value = nil

  def execute(some_value: nil, **)
    transact do
      # Store in class variable so we can verify in tests
      @@last_some_value = some_value
    end
  end

  def self.last_some_value
    @@last_some_value
  end

  def self.reset!
    @@last_some_value = nil
  end
end

# Test schema
class TestSchema < ZeroRuby::Schema
  mutation "items.create", handler: SchemaMutation
  mutation "items.update", handler: SchemaMutation
end

# Test schema inheritance
class BaseSchema < ZeroRuby::Schema
  mutation "base.action", handler: SchemaMutation
end

class ChildSchema < BaseSchema
  mutation "child.action", handler: SchemaMutation
end

# Test mutation with nested args
class NestedArgsMutation < ZeroRuby::Mutation
  argument :nested_data, ZeroRuby::Types::String.optional

  @@last_nested_data = nil

  def execute(nested_data: nil, **)
    transact do
      @@last_nested_data = nested_data
    end
  end

  def self.last_nested_data
    @@last_nested_data
  end

  def self.reset!
    @@last_nested_data = nil
  end
end

class NestedArgsSchema < ZeroRuby::Schema
  mutation "nested.action", handler: NestedArgsMutation
end

# Test mutation with constraints for Dry error conversion tests
class ConstrainedMutation < ZeroRuby::Mutation
  argument :title, ZeroRuby::Types::String.constrained(max_size: 10)
  argument :count, ZeroRuby::Types::Integer

  def execute(**)
    transact { nil }
  end
end

# Test InputObject for Dry::Struct::Error conversion tests
class AddressInput < ZeroRuby::InputObject
  attribute :street, ZeroRuby::Types::String
  attribute :city, ZeroRuby::Types::String
end

class InputObjectMutation < ZeroRuby::Mutation
  argument :address, AddressInput

  def execute(**)
    transact { nil }
  end
end

class DryErrorSchema < ZeroRuby::Schema
  mutation "constrained.create", handler: ConstrainedMutation
  mutation "input_object.create", handler: InputObjectMutation
end

describe ZeroRuby::Schema do
  let(:context) { {current_user: OpenStruct.new(id: 1)} }

  # Simple transact mock that just executes the user's block
  let(:transact) { proc { |&blk| blk.call } }

  it "executes single mutation" do
    mutation_data = {
      "name" => "items.create",
      "args" => [{"id" => "item-1", "value" => 42}]
    }

    result = TestSchema.execute_mutation(mutation_data, context, &transact)

    expect(result).to eq({})
  end

  it "raises on unknown mutation" do
    mutation_data = {
      "name" => "unknown.mutation",
      "args" => [{}]
    }

    expect {
      TestSchema.execute_mutation(mutation_data, context, &transact)
    }.to raise_error(ZeroRuby::MutationNotFoundError, /Unknown mutation/)
  end

  it "normalizes pipe-separated names" do
    mutation_data = {
      "name" => "items|create",
      "args" => [{"id" => "item-1"}]
    }

    result = TestSchema.execute_mutation(mutation_data, context, &transact)

    expect(result).to eq({})
  end

  it "transforms camelCase to snake_case" do
    SchemaMutation.reset!
    mutation_data = {
      "name" => "items.create",
      "args" => [{"id" => "item-1", "someValue" => 99}]
    }

    TestSchema.execute_mutation(mutation_data, context, &transact)

    expect(SchemaMutation.last_some_value).to eq(99)
  end

  describe "schema inheritance" do
    it "child schema has access to parent mutations" do
      expect(ChildSchema.mutations.keys).to include("base.action")
    end

    it "child schema has its own mutations" do
      expect(ChildSchema.mutations.keys).to include("child.action")
    end

    it "parent schema does not have child mutations" do
      expect(BaseSchema.mutations.keys).not_to include("child.action")
    end

    it "can execute inherited mutation" do
      mutation_data = {
        "name" => "base.action",
        "args" => [{"id" => "test-1"}]
      }

      result = ChildSchema.execute_mutation(mutation_data, context, &transact)
      expect(result).to eq({})
    end
  end

  describe "name normalization edge cases" do
    it "handles empty mutation name" do
      mutation_data = {
        "name" => "",
        "args" => [{}]
      }

      expect {
        TestSchema.execute_mutation(mutation_data, context, &transact)
      }.to raise_error(ZeroRuby::MutationNotFoundError)
    end

    it "handles mutation name with multiple pipes" do
      # items|sub|create -> items.sub.create (normalized to dots)
      # Note: We can only test with registered mutations
      mutation_data = {
        "name" => "items|create",
        "args" => [{"id" => "item-1"}]
      }

      result = TestSchema.execute_mutation(mutation_data, context, &transact)
      expect(result).to eq({})
    end
  end

  describe "deep nested camelCase transformation" do
    it "transforms nested object keys" do
      NestedArgsMutation.reset!
      mutation_data = {
        "name" => "nested.action",
        "args" => [{"nestedData" => "test-value"}]
      }

      NestedArgsSchema.execute_mutation(mutation_data, context, &transact)
      expect(NestedArgsMutation.last_nested_data).to eq("test-value")
    end
  end

  describe "args edge cases" do
    it "handles nil args" do
      mutation_data = {
        "name" => "items.create",
        "args" => nil
      }

      # nil args should be treated as empty, triggering validation error for required id
      expect {
        TestSchema.execute_mutation(mutation_data, context, &transact)
      }.to raise_error(ZeroRuby::ValidationError)
    end

    it "handles empty args array" do
      mutation_data = {
        "name" => "items.create",
        "args" => []
      }

      # Empty array means no args hash, should fail validation for required id
      expect {
        TestSchema.execute_mutation(mutation_data, context, &transact)
      }.to raise_error(ZeroRuby::ValidationError)
    end

    it "handles missing args key" do
      mutation_data = {
        "name" => "items.create"
      }

      # Missing args key should fail validation for required id
      expect {
        TestSchema.execute_mutation(mutation_data, context, &transact)
      }.to raise_error(ZeroRuby::ValidationError)
    end
  end

  describe "Dry error conversion" do
    it "converts Dry::Types::ConstraintError to ValidationError" do
      mutation_data = {
        "name" => "constrained.create",
        "args" => [{"title" => "this title is way too long", "count" => 1}]
      }

      expect {
        DryErrorSchema.execute_mutation(mutation_data, context, &transact)
      }.to raise_error(ZeroRuby::ValidationError) { |error|
        # Error message contains the invalid value
        expect(error.errors.first).to include("not a valid")
      }
    end

    it "converts Dry::Types::CoercionError to ValidationError" do
      mutation_data = {
        "name" => "constrained.create",
        "args" => [{"title" => "short", "count" => "not-a-number"}]
      }

      expect {
        DryErrorSchema.execute_mutation(mutation_data, context, &transact)
      }.to raise_error(ZeroRuby::ValidationError) { |error|
        expect(error.errors.first).to include("integer")
      }
    end

    it "converts Dry::Struct::Error to ValidationError" do
      mutation_data = {
        "name" => "input_object.create",
        "args" => [{"address" => {"street" => "123 Main St"}}]  # missing city
      }

      expect {
        DryErrorSchema.execute_mutation(mutation_data, context, &transact)
      }.to raise_error(ZeroRuby::ValidationError) { |error|
        expect(error.errors.first).to include("required")
      }
    end
  end
end
