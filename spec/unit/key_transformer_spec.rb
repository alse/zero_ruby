# frozen_string_literal: true

require "spec_helper"

# Leaf input object used in array-of-inputobject tests
class KTItemInput < ZeroRuby::InputObject
  argument :first_name, ZeroRuby::Types::String
  argument :last_name, ZeroRuby::Types::String.optional
end

# InputObject with a nested InputObject (3-level test)
class KTAddressInput < ZeroRuby::InputObject
  argument :street_name, ZeroRuby::Types::String
  argument :city, ZeroRuby::Types::String
end

class KTAuthorInput < ZeroRuby::InputObject
  argument :display_name, ZeroRuby::Types::String
  argument :home_address, KTAddressInput
end

# InputObject mixing a typed scalar with a free-form Hash
class KTPostInput < ZeroRuby::InputObject
  argument :first_name, ZeroRuby::Types::String
  argument :spec, ZeroRuby::Types::Hash
end

# Mutation covering all the dispatch branches
class KTKitchenSinkMutation < ZeroRuby::Mutation
  argument :some_value, ZeroRuby::Types::Integer
  argument :flag, ZeroRuby::Types::Boolean.default(false)
  argument :maybe_name, ZeroRuby::Types::String.optional
  argument :spec, ZeroRuby::Types::Hash.optional
  argument :tags, ZeroRuby::Types::Array(ZeroRuby::Types::String).optional
  argument :items, ZeroRuby::Types::Array(KTItemInput).optional
  argument :author, KTAuthorInput.optional
  argument :post, KTPostInput.optional

  def execute(**)
  end
end

describe ZeroRuby::KeyTransformer do
  let(:args) { KTKitchenSinkMutation.arguments }

  def transform(raw)
    described_class.transform(raw, args)
  end

  describe "non-hash input" do
    it "returns non-hash inputs verbatim" do
      expect(described_class.transform(nil, args)).to be_nil
      expect(described_class.transform("string", args)).to eq("string")
      expect(described_class.transform([], args)).to eq([])
    end
  end

  describe "top-level scalar args" do
    it "converts camelCase wire keys to declared snake_case names" do
      result = transform({"someValue" => 1})
      expect(result).to eq({"some_value" => 1})
    end

    it "passes pre-snake-cased keys through" do
      result = transform({"some_value" => 1})
      expect(result).to eq({"some_value" => 1})
    end

    it "uses snake first when both forms are present" do
      result = transform({"some_value" => 1, "someValue" => 2})
      expect(result).to eq({"some_value" => 1})
    end

    it "leaves scalar values untouched" do
      result = transform({"someValue" => "hello"})
      expect(result).to eq({"some_value" => "hello"})
    end
  end

  describe "missing and unknown keys" do
    it "omits missing keys from the output" do
      result = transform({"someValue" => 1})
      expect(result.keys).to eq(["some_value"])
    end

    it "drops keys not in the declared schema" do
      result = transform({"someValue" => 1, "unknownExtra" => "x"})
      expect(result).to eq({"some_value" => 1})
    end
  end

  describe "nil values" do
    it "passes nil values through" do
      result = transform({"maybeName" => nil})
      expect(result).to eq({"maybe_name" => nil})
    end
  end

  describe "optional and default wrappers" do
    it "transforms .optional scalar correctly" do
      result = transform({"maybeName" => "x"})
      expect(result).to eq({"maybe_name" => "x"})
    end

    it "passes value through a .default-wrapped scalar arg" do
      result = transform({"flag" => true})
      expect(result).to eq({"flag" => true})
    end

    it "omits a .default-wrapped scalar when the key is missing" do
      result = transform({})
      expect(result).not_to have_key("flag")
    end

    it "unwraps Default(Array(InputObject)) and recurses element-wise" do
      type = ZeroRuby::Types::Array(KTItemInput).default([].freeze)
      metadata = {items: {type: type, name: :items}}
      raw = {"items" => [{"firstName" => "a"}, {"firstName" => "b", "lastName" => "c"}]}

      result = described_class.transform(raw, metadata)
      expect(result).to eq(
        {"items" => [{"first_name" => "a"}, {"first_name" => "b", "last_name" => "c"}]}
      )
    end

    it "unwraps Default(InputObject) and recurses into its attributes" do
      default_instance = KTAuthorInput.new(
        display_name: "x",
        home_address: KTAddressInput.new(street_name: "y", city: "z")
      )
      type = KTAuthorInput.default(default_instance)
      metadata = {author: {type: type, name: :author}}
      raw = {"author" => {"displayName" => "Jane", "homeAddress" => {"streetName" => "Main", "city" => "Berlin"}}}

      result = described_class.transform(raw, metadata)
      expect(result["author"]).to eq(
        {"display_name" => "Jane", "home_address" => {"street_name" => "Main", "city" => "Berlin"}}
      )
    end
  end

  describe "Hash / JSON leaf (the bug fix)" do
    it "preserves camelCase keys inside top-level Hash args" do
      raw = {"spec" => {"aspectRatio" => 1.5, "imageUrl" => "x"}}
      expect(transform(raw)).to eq(
        {"spec" => {"aspectRatio" => 1.5, "imageUrl" => "x"}}
      )
    end

    it "preserves deeply nested camelCase keys inside Hash args" do
      raw = {
        "spec" => {
          "elements" => {
            "card" => {"props" => {"aspectRatio" => 1.5, "imageUrl" => "x"}}
          }
        }
      }
      expect(transform(raw)).to eq(raw)
    end

    it "preserves Hash values that contain arrays of opaque hashes" do
      raw = {"spec" => {"layers" => [{"aspectRatio" => 1}, {"aspectRatio" => 2}]}}
      expect(transform(raw)).to eq(raw)
    end

    it "preserves Hash values inside a nested InputObject" do
      raw = {"post" => {"firstName" => "a", "spec" => {"aspectRatio" => 1.5}}}
      expect(transform(raw)).to eq(
        {"post" => {"first_name" => "a", "spec" => {"aspectRatio" => 1.5}}}
      )
    end
  end

  describe "nested InputObject" do
    it "transforms keys inside a nested InputObject" do
      raw = {"author" => {"displayName" => "Jane", "homeAddress" => {"streetName" => "Main", "city" => "Berlin"}}}
      expect(transform(raw)).to eq(
        {"author" => {"display_name" => "Jane", "home_address" => {"street_name" => "Main", "city" => "Berlin"}}}
      )
    end

    it "drops unknown keys inside a nested InputObject" do
      raw = {"author" => {"displayName" => "Jane", "homeAddress" => {"streetName" => "Main", "city" => "Berlin"}, "extra" => "junk"}}
      result = transform(raw)
      expect(result["author"].keys).to contain_exactly("display_name", "home_address")
    end

    it "uses snake first when both forms are present inside a nested InputObject" do
      raw = {"author" => {"display_name" => "snake", "displayName" => "camel", "homeAddress" => {"streetName" => "S", "city" => "C"}}}
      result = transform(raw)
      expect(result["author"]["display_name"]).to eq("snake")
    end
  end

  describe "arrays" do
    it "leaves array-of-scalar values unchanged" do
      raw = {"tags" => ["a", "b", "c"]}
      expect(transform(raw)).to eq({"tags" => ["a", "b", "c"]})
    end

    it "transforms keys element-wise for array-of-InputObject" do
      raw = {"items" => [{"firstName" => "a"}, {"firstName" => "b", "lastName" => "c"}]}
      expect(transform(raw)).to eq(
        {"items" => [{"first_name" => "a"}, {"first_name" => "b", "last_name" => "c"}]}
      )
    end

    it "handles empty arrays" do
      expect(transform({"items" => []})).to eq({"items" => []})
      expect(transform({"tags" => []})).to eq({"tags" => []})
    end

    it "uses snake first when both forms are present inside an array element" do
      raw = {"items" => [{"first_name" => "snake", "firstName" => "camel"}]}
      result = transform(raw)
      expect(result["items"][0]["first_name"]).to eq("snake")
    end
  end

  describe "integration with coerce_and_validate!" do
    it "produces a hash that Mutation.coerce_and_validate! can consume" do
      raw = {"someValue" => 1, "author" => {"displayName" => "Jane", "homeAddress" => {"streetName" => "S", "city" => "C"}}}
      params = described_class.transform(raw, KTKitchenSinkMutation.arguments)
      expect {
        KTKitchenSinkMutation.send(:coerce_and_validate!, params)
      }.not_to raise_error
    end
  end
end
