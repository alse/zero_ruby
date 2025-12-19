# frozen_string_literal: true

require "spec_helper"

# Test mutation class
class TestMutation < ZeroRuby::Mutation
  argument :name, ZeroRuby::Types::String
  argument :count, ZeroRuby::Types::Integer.default(1)
  argument :title, ZeroRuby::Types::String.constrained(max_size: 50)

  attr_reader :received_args

  def execute(name:, count:, title:)
    transact do
      @received_args = {name: name, count: count, title: title}
    end
    nil
  end
end

# Test mutation with false/nil defaults
class FalsyDefaultMutation < ZeroRuby::Mutation
  argument :name, ZeroRuby::Types::String
  argument :enabled, ZeroRuby::Types::Boolean.default(false)
  argument :disabled, ZeroRuby::Types::Boolean.optional  # no default

  attr_reader :received_args

  def execute(name:, enabled:, disabled: nil)
    transact do
      @received_args = {name: name, enabled: enabled, disabled: disabled}
    end
    nil
  end
end

# Test mutation with all constraint types
class ConstraintsMutation < ZeroRuby::Mutation
  argument :min_length, ZeroRuby::Types::String.constrained(min_size: 3)
  argument :max_length, ZeroRuby::Types::String.constrained(max_size: 10)
  argument :greater_than, ZeroRuby::Types::Integer.constrained(gt: 0)
  argument :less_than, ZeroRuby::Types::Integer.constrained(lt: 100)
  argument :format_match, ZeroRuby::Types::String.constrained(format: /^\d+$/)
  argument :in_list, ZeroRuby::Types::String.constrained(included_in: %w[draft published])

  def execute(**)
    transact { nil }
  end
end

# Test mutation that returns data
class DataMutation < ZeroRuby::Mutation
  argument :id, ZeroRuby::Types::String

  def execute(id:)
    transact do
      {id: id, created: true}
    end
  end
end

# Test mutation inheritance
class BaseMutation < ZeroRuby::Mutation
  argument :base_field, ZeroRuby::Types::String
end

class ChildMutation < BaseMutation
  argument :child_field, ZeroRuby::Types::String

  attr_reader :received_args

  def execute(base_field:, child_field:)
    transact do
      @received_args = {base_field: base_field, child_field: child_field}
    end
    nil
  end
end

# Test mutation for collecting multiple errors
class MultiErrorMutation < ZeroRuby::Mutation
  argument :name, ZeroRuby::Types::String
  argument :age, ZeroRuby::Types::Integer

  def execute(**)
    transact { nil }
  end
end

describe ZeroRuby::Mutation do
  let(:ctx) { {current_user: OpenStruct.new(id: 1), request_id: "req-123"}.freeze }

  # Simple transact mock that just executes the user's block
  let(:transact) { proc { |&blk| blk.call } }

  it "coerces arguments" do
    mutation = TestMutation.new({"name" => "test", "title" => "Hello"}, ctx)
    mutation.call(&transact)
    expect(mutation.received_args[:name]).to eq("test")
    expect(mutation.received_args[:title]).to eq("Hello")
  end

  it "applies default values" do
    mutation = TestMutation.new({"name" => "test", "title" => "Hello"}, ctx)
    mutation.call(&transact)
    expect(mutation.received_args[:count]).to eq(1)
  end

  it "executes successfully" do
    mutation = TestMutation.new({"name" => "test", "title" => "Hello"}, ctx)
    result = mutation.call(&transact)
    expect(result).to eq({})
  end

  it "raises on missing required argument" do
    expect {
      TestMutation.new({"title" => "Hello"}, ctx)
    }.to raise_error(ZeroRuby::ValidationError) { |error|
      expect(error.errors).to include("name is required")
    }
  end

  it "raises ValidationError on constraint failure" do
    long_title = "x" * 51
    expect {
      TestMutation.new({"name" => "test", "title" => long_title}, ctx)
    }.to raise_error(ZeroRuby::ValidationError) { |error|
      expect(error.errors.first).to include("title")
    }
  end

  it "coerces integer from string" do
    mutation = TestMutation.new({"name" => "test", "count" => "5", "title" => "Hello"}, ctx)
    mutation.call(&transact)
    expect(mutation.received_args[:count]).to eq(5)
  end

  it "applies false as default" do
    mutation = FalsyDefaultMutation.new({"name" => "test"}, ctx)
    mutation.call(&transact)
    expect(mutation.received_args[:enabled]).to eq(false)
  end

  it "distinguishes false default from optional" do
    enabled_config = FalsyDefaultMutation.arguments[:enabled]
    disabled_config = FalsyDefaultMutation.arguments[:disabled]

    expect(enabled_config[:type].default?).to be true
    expect(disabled_config[:type].optional?).to be true
  end

  describe "constraint validation" do
    it "raises ValidationError for constraint violations" do
      expect {
        ConstraintsMutation.new({
          "min_length" => "ab",  # too short (min 3)
          "max_length" => "valid",
          "greater_than" => 1,
          "less_than" => 50,
          "format_match" => "123",
          "in_list" => "draft"
        }, ctx)
      }.to raise_error(ZeroRuby::ValidationError) { |error|
        expect(error.errors.first).to include("min_length")
      }
    end

    it "passes all constraints when valid" do
      mutation = ConstraintsMutation.new({
        "min_length" => "abc",
        "max_length" => "valid",
        "greater_than" => 1,
        "less_than" => 50,
        "format_match" => "123",
        "in_list" => "draft"
      }, ctx)
      result = mutation.call(&transact)
      expect(result).to eq({})
    end
  end

  describe "mutation returning data" do
    it "wraps returned data in :data key" do
      mutation = DataMutation.new({"id" => "item-1"}, ctx)
      result = mutation.call(&transact)
      expect(result).to eq({data: {id: "item-1", created: true}})
    end
  end

  describe "argument inheritance" do
    it "inherits arguments from parent class" do
      expect(ChildMutation.arguments.keys).to include(:base_field, :child_field)
    end

    it "validates inherited arguments" do
      expect {
        ChildMutation.new({"child_field" => "value"}, ctx)  # missing base_field
      }.to raise_error(ZeroRuby::ValidationError) { |error|
        expect(error.errors).to include("base_field is required")
      }
    end

    it "processes both inherited and own arguments" do
      mutation = ChildMutation.new({
        "base_field" => "base_value",
        "child_field" => "child_value"
      }, ctx)
      mutation.call(&transact)

      expect(mutation.received_args[:base_field]).to eq("base_value")
      expect(mutation.received_args[:child_field]).to eq("child_value")
    end
  end

  describe "multiple validation errors" do
    it "collects all validation errors for missing required fields" do
      expect {
        MultiErrorMutation.new({}, ctx)  # missing both name and age
      }.to raise_error(ZeroRuby::ValidationError) { |error|
        expect(error.errors).to include("name is required")
        expect(error.errors).to include("age is required")
        expect(error.errors.length).to eq(2)
      }
    end

    it "collects all constraint and coercion errors" do
      expect {
        ConstraintsMutation.new({
          "min_length" => "ab",          # too short
          "max_length" => "way too long string here",  # too long
          "greater_than" => 0,           # not > 0
          "less_than" => 100,            # not < 100
          "format_match" => "abc",       # doesn't match /^\d+$/
          "in_list" => "invalid"         # not in [draft, published]
        }, ctx)
      }.to raise_error(ZeroRuby::ValidationError) { |error|
        expect(error.errors.length).to eq(6)
        expect(error.errors.any? { |e| e.include?("min_length") }).to be true
        expect(error.errors.any? { |e| e.include?("max_length") }).to be true
        expect(error.errors.any? { |e| e.include?("greater_than") }).to be true
        expect(error.errors.any? { |e| e.include?("less_than") }).to be true
        expect(error.errors.any? { |e| e.include?("format_match") }).to be true
        expect(error.errors.any? { |e| e.include?("in_list") }).to be true
      }
    end
  end

  describe "coercion errors" do
    it "raises ValidationError for integer coercion failure" do
      expect {
        TestMutation.new({"name" => "test", "count" => "not-a-number", "title" => "Hello"}, ctx)
      }.to raise_error(ZeroRuby::ValidationError) { |error|
        expect(error.errors.first).to include("count")
      }
    end
  end

  describe "explicit nil on optional field" do
    it "accepts explicit nil for optional field" do
      mutation = FalsyDefaultMutation.new({
        "name" => "test",
        "disabled" => nil  # explicit nil on optional field
      }, ctx)
      mutation.call(&transact)

      expect(mutation.received_args[:disabled]).to be_nil
    end
  end

  describe "unknown arguments" do
    it "ignores unknown arguments" do
      mutation = TestMutation.new({
        "name" => "test",
        "title" => "Hello",
        "unknown_field" => "ignored"
      }, ctx)
      mutation.call(&transact)
      expect(mutation.args.keys).to contain_exactly(:name, :count, :title)
    end
  end

  describe "mutation with no arguments" do
    it "executes mutation with no arguments" do
      no_args_class = Class.new(ZeroRuby::Mutation) do
        def execute(**)
          transact { {result: "success"} }
        end
      end

      mutation = no_args_class.new({}, ctx)
      result = mutation.call(&transact)
      expect(result).to eq({data: {result: "success"}})
    end
  end

  describe "argument descriptions" do
    it "stores argument descriptions" do
      described_class = Class.new(ZeroRuby::Mutation) do
        argument :field, ZeroRuby::Types::String, description: "A test field"
        argument :other, ZeroRuby::Types::Integer

        def execute(**)
          transact { nil }
        end
      end

      config = described_class.arguments[:field]
      expect(config[:description]).to eq("A test field")
      expect(described_class.arguments[:other][:description]).to be_nil
    end
  end

  describe "deep inheritance" do
    it "inherits arguments through multiple levels" do
      grandchild = Class.new(ChildMutation) do
        argument :grandchild_field, ZeroRuby::Types::String

        def execute(**)
          transact { nil }
        end
      end

      expect(grandchild.arguments.keys).to include(
        :base_field, :child_field, :grandchild_field
      )
    end
  end

  describe "explicit nil on required field" do
    it "raises validation error for explicit nil on required field" do
      expect {
        TestMutation.new({"name" => nil, "title" => "Hello"}, ctx)
      }.to raise_error(ZeroRuby::ValidationError) { |error|
        expect(error.errors).to include("name is required")
      }
    end
  end
end
