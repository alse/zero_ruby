# frozen_string_literal: true

require "spec_helper"

describe ZeroRuby::Types do
  describe "String" do
    it "preserves string" do
      expect(ZeroRuby::Types::String["hello"]).to eq("hello")
    end

    it "rejects nil" do
      expect { ZeroRuby::Types::String[nil] }
        .to raise_error(Dry::Types::ConstraintError)
    end

    it "rejects non-string values" do
      expect { ZeroRuby::Types::String[123] }
        .to raise_error(Dry::Types::ConstraintError)
      expect { ZeroRuby::Types::String[:foo] }
        .to raise_error(Dry::Types::ConstraintError)
    end
  end

  describe "Integer" do
    it "coerces string to integer" do
      expect(ZeroRuby::Types::Integer["42"]).to eq(42)
    end

    it "coerces float to integer" do
      expect(ZeroRuby::Types::Integer[3.7]).to eq(3)
    end

    it "raises CoercionError for invalid string" do
      expect { ZeroRuby::Types::Integer["not a number"] }
        .to raise_error(Dry::Types::CoercionError)
    end

    it "raises CoercionError for empty string" do
      expect { ZeroRuby::Types::Integer[""] }
        .to raise_error(Dry::Types::CoercionError)
    end

    it "preserves integer" do
      expect(ZeroRuby::Types::Integer[42]).to eq(42)
    end

    it "handles negative integers" do
      expect(ZeroRuby::Types::Integer[-42]).to eq(-42)
      expect(ZeroRuby::Types::Integer["-42"]).to eq(-42)
    end

    it "handles zero" do
      expect(ZeroRuby::Types::Integer[0]).to eq(0)
      expect(ZeroRuby::Types::Integer["0"]).to eq(0)
    end

    it "raises error for nil" do
      expect { ZeroRuby::Types::Integer[nil] }
        .to raise_error(Dry::Types::CoercionError)
    end
  end

  describe "Float" do
    it "coerces string to float" do
      expect(ZeroRuby::Types::Float["3.14"]).to eq(3.14)
    end

    it "coerces integer to float" do
      expect(ZeroRuby::Types::Float[42]).to eq(42.0)
    end

    it "raises CoercionError for invalid string" do
      expect { ZeroRuby::Types::Float["not a number"] }
        .to raise_error(Dry::Types::CoercionError)
    end

    it "preserves float" do
      expect(ZeroRuby::Types::Float[3.14]).to eq(3.14)
    end

    it "handles negative floats" do
      expect(ZeroRuby::Types::Float[-3.14]).to eq(-3.14)
      expect(ZeroRuby::Types::Float["-3.14"]).to eq(-3.14)
    end

    it "handles zero" do
      expect(ZeroRuby::Types::Float[0.0]).to eq(0.0)
      expect(ZeroRuby::Types::Float["0.0"]).to eq(0.0)
    end

    it "raises CoercionError for empty string" do
      expect { ZeroRuby::Types::Float[""] }
        .to raise_error(Dry::Types::CoercionError)
    end

    it "raises error for nil" do
      expect { ZeroRuby::Types::Float[nil] }
        .to raise_error(Dry::Types::CoercionError)
    end
  end

  describe "Boolean" do
    it "coerces 'true' string" do
      expect(ZeroRuby::Types::Boolean["true"]).to eq(true)
    end

    it "coerces 'false' string" do
      expect(ZeroRuby::Types::Boolean["false"]).to eq(false)
    end

    it "preserves true" do
      expect(ZeroRuby::Types::Boolean[true]).to eq(true)
    end

    it "preserves false" do
      expect(ZeroRuby::Types::Boolean[false]).to eq(false)
    end

    it "raises CoercionError for invalid value" do
      expect { ZeroRuby::Types::Boolean["maybe"] }
        .to raise_error(Dry::Types::CoercionError)
    end

    it "raises CoercionError for nil" do
      expect { ZeroRuby::Types::Boolean[nil] }
        .to raise_error(Dry::Types::CoercionError)
    end

    it "coerces integers 1 and 0 to boolean" do
      # Params::Bool accepts 1/0 as true/false
      expect(ZeroRuby::Types::Boolean[1]).to eq(true)
      expect(ZeroRuby::Types::Boolean[0]).to eq(false)
    end

    it "coerces string '1' and '0' to boolean" do
      expect(ZeroRuby::Types::Boolean["1"]).to eq(true)
      expect(ZeroRuby::Types::Boolean["0"]).to eq(false)
    end
  end

  describe "ID" do
    it "accepts non-empty strings" do
      expect(ZeroRuby::Types::ID["abc"]).to eq("abc")
    end

    it "rejects empty strings" do
      expect { ZeroRuby::Types::ID[""] }
        .to raise_error(Dry::Types::ConstraintError)
    end

    it "rejects nil" do
      expect { ZeroRuby::Types::ID[nil] }
        .to raise_error(Dry::Types::ConstraintError)
    end

    it "accepts numeric strings" do
      expect(ZeroRuby::Types::ID["123"]).to eq("123")
    end

    it "rejects numeric values" do
      expect { ZeroRuby::Types::ID[123] }
        .to raise_error(Dry::Types::ConstraintError)
    end

    it "accepts whitespace-containing strings" do
      # Whitespace strings are non-empty, so they pass the filled constraint
      expect(ZeroRuby::Types::ID["  abc  "]).to eq("  abc  ")
    end
  end

  describe "ISO8601Date" do
    it "parses ISO8601 date strings" do
      expect(ZeroRuby::Types::ISO8601Date["2024-01-15"]).to eq(Date.new(2024, 1, 15))
    end

    it "raises CoercionError for invalid date strings" do
      expect { ZeroRuby::Types::ISO8601Date["not-a-date"] }
        .to raise_error(Dry::Types::CoercionError)
    end

    it "raises CoercionError for empty string" do
      expect { ZeroRuby::Types::ISO8601Date[""] }
        .to raise_error(Dry::Types::CoercionError)
    end

    it "raises error for nil" do
      expect { ZeroRuby::Types::ISO8601Date[nil] }
        .to raise_error(Dry::Types::CoercionError)
    end
  end

  describe "ISO8601DateTime" do
    it "parses ISO8601 datetime strings" do
      result = ZeroRuby::Types::ISO8601DateTime["2024-01-15T10:30:00Z"]
      expect(result).to be_a(DateTime)
    end

    it "parses datetime with timezone offset" do
      result = ZeroRuby::Types::ISO8601DateTime["2024-01-15T10:30:00+05:00"]
      expect(result).to be_a(DateTime)
      expect(result.hour).to eq(10)
    end

    it "raises CoercionError for invalid datetime strings" do
      expect { ZeroRuby::Types::ISO8601DateTime["not-a-datetime"] }
        .to raise_error(Dry::Types::CoercionError)
    end

    it "raises CoercionError for empty string" do
      expect { ZeroRuby::Types::ISO8601DateTime[""] }
        .to raise_error(Dry::Types::CoercionError)
    end

    it "raises error for nil" do
      expect { ZeroRuby::Types::ISO8601DateTime[nil] }
        .to raise_error(Dry::Types::CoercionError)
    end

    it "parses datetime without timezone (assumes local)" do
      result = ZeroRuby::Types::ISO8601DateTime["2024-01-15T10:30:00"]
      expect(result).to be_a(DateTime)
      expect(result.hour).to eq(10)
    end

    it "parses datetime with negative timezone offset" do
      result = ZeroRuby::Types::ISO8601DateTime["2024-01-15T10:30:00-05:00"]
      expect(result).to be_a(DateTime)
      expect(result.hour).to eq(10)
    end
  end

  describe "constraints" do
    it "validates max_size" do
      type = ZeroRuby::Types::String.constrained(max_size: 5)
      expect { type["toolong"] }.to raise_error(Dry::Types::ConstraintError)
      expect(type["short"]).to eq("short")
    end

    it "validates min_size" do
      type = ZeroRuby::Types::String.constrained(min_size: 3)
      expect { type["ab"] }.to raise_error(Dry::Types::ConstraintError)
      expect(type["abc"]).to eq("abc")
    end

    it "validates gt (greater than)" do
      type = ZeroRuby::Types::Integer.constrained(gt: 0)
      expect { type[0] }.to raise_error(Dry::Types::ConstraintError)
      expect(type[1]).to eq(1)
    end

    it "validates gteq (greater than or equal)" do
      type = ZeroRuby::Types::Integer.constrained(gteq: 5)
      expect { type[4] }.to raise_error(Dry::Types::ConstraintError)
      expect(type[5]).to eq(5)
      expect(type[6]).to eq(6)
    end

    it "validates lt (less than)" do
      type = ZeroRuby::Types::Integer.constrained(lt: 10)
      expect { type[10] }.to raise_error(Dry::Types::ConstraintError)
      expect(type[9]).to eq(9)
    end

    it "validates lteq (less than or equal)" do
      type = ZeroRuby::Types::Integer.constrained(lteq: 10)
      expect { type[11] }.to raise_error(Dry::Types::ConstraintError)
      expect(type[10]).to eq(10)
      expect(type[9]).to eq(9)
    end

    it "validates format" do
      type = ZeroRuby::Types::String.constrained(format: /^\d+$/)
      expect { type["abc"] }.to raise_error(Dry::Types::ConstraintError)
      expect(type["123"]).to eq("123")
    end

    it "validates included_in" do
      type = ZeroRuby::Types::String.constrained(included_in: %w[draft published])
      expect { type["invalid"] }.to raise_error(Dry::Types::ConstraintError)
      expect(type["draft"]).to eq("draft")
    end

    it "validates excluded_from" do
      type = ZeroRuby::Types::String.constrained(excluded_from: %w[admin root])
      expect { type["admin"] }.to raise_error(Dry::Types::ConstraintError)
      expect { type["root"] }.to raise_error(Dry::Types::ConstraintError)
      expect(type["user"]).to eq("user")
    end

    it "validates multiple constraints together" do
      type = ZeroRuby::Types::Integer.constrained(gteq: 1, lteq: 100)
      expect { type[0] }.to raise_error(Dry::Types::ConstraintError)
      expect { type[101] }.to raise_error(Dry::Types::ConstraintError)
      expect(type[1]).to eq(1)
      expect(type[50]).to eq(50)
      expect(type[100]).to eq(100)
    end

    it "validates constraints on Float" do
      type = ZeroRuby::Types::Float.constrained(gt: 0.0, lt: 1.0)
      expect { type[0.0] }.to raise_error(Dry::Types::ConstraintError)
      expect { type[1.0] }.to raise_error(Dry::Types::ConstraintError)
      expect(type[0.5]).to eq(0.5)
    end

    it "applies constraints after coercion for Integer" do
      type = ZeroRuby::Types::Integer.constrained(gt: 40)
      expect(type["50"]).to eq(50)  # coerced then validated
      expect { type["30"] }.to raise_error(Dry::Types::ConstraintError)
    end

    it "applies constraints after coercion for Float" do
      type = ZeroRuby::Types::Float.constrained(lteq: 0.5)
      expect(type["0.3"]).to eq(0.3)  # coerced then validated
      expect { type["0.7"] }.to raise_error(Dry::Types::ConstraintError)
    end
  end

  describe "optional types" do
    it "accepts nil for optional String" do
      type = ZeroRuby::Types::String.optional
      expect(type[nil]).to be_nil
      expect(type["hello"]).to eq("hello")
    end

    it "accepts nil for optional Integer" do
      type = ZeroRuby::Types::Integer.optional
      expect(type[nil]).to be_nil
      expect(type[42]).to eq(42)
    end

    it "accepts nil for optional Float" do
      type = ZeroRuby::Types::Float.optional
      expect(type[nil]).to be_nil
      expect(type[3.14]).to eq(3.14)
    end

    it "accepts nil for optional Boolean" do
      type = ZeroRuby::Types::Boolean.optional
      expect(type[nil]).to be_nil
      expect(type[true]).to eq(true)
      expect(type[false]).to eq(false)
    end

    it "accepts nil for optional ID" do
      type = ZeroRuby::Types::ID.optional
      expect(type[nil]).to be_nil
      expect(type["abc"]).to eq("abc")
    end

    it "accepts nil for optional ISO8601Date" do
      type = ZeroRuby::Types::ISO8601Date.optional
      expect(type[nil]).to be_nil
      expect(type["2024-01-15"]).to eq(Date.new(2024, 1, 15))
    end

    it "accepts nil for optional ISO8601DateTime" do
      type = ZeroRuby::Types::ISO8601DateTime.optional
      expect(type[nil]).to be_nil
      result = type["2024-01-15T10:30:00Z"]
      expect(result).to be_a(DateTime)
    end
  end

  describe "default values" do
    it "provides default when value is missing for String" do
      type = ZeroRuby::Types::String.default("default_value")
      expect(type[]).to eq("default_value")
      expect(type["custom"]).to eq("custom")
    end

    it "provides default when value is missing for Integer" do
      type = ZeroRuby::Types::Integer.default(0)
      expect(type[]).to eq(0)
      expect(type[42]).to eq(42)
    end

    it "provides default when value is missing for Float" do
      type = ZeroRuby::Types::Float.default(0.0)
      expect(type[]).to eq(0.0)
      expect(type[3.14]).to eq(3.14)
    end

    it "provides default for boolean true" do
      type = ZeroRuby::Types::Boolean.default(true)
      expect(type[]).to eq(true)
      expect(type[false]).to eq(false)
    end

    it "provides default for boolean false" do
      type = ZeroRuby::Types::Boolean.default(false)
      expect(type[]).to eq(false)
      expect(type[true]).to eq(true)
    end
  end
end
