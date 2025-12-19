# frozen_string_literal: true

require "spec_helper"

describe ZeroRuby::TypeNames do
  describe "constant access" do
    it "provides Types module access" do
      expect(ZeroRuby::TypeNames::Types).to eq(ZeroRuby::Types)
    end
  end

  describe "in Mutation classes" do
    it "provides Types constant for argument definitions" do
      mutation_class = Class.new(ZeroRuby::Mutation) do
        argument :id, ZeroRuby::Types::ID
        argument :active, ZeroRuby::Types::Boolean
        argument :created_at, ZeroRuby::Types::ISO8601DateTime
        argument :birth_date, ZeroRuby::Types::ISO8601Date

        def execute
        end
      end

      expect(mutation_class.arguments[:id][:type]).to eq(ZeroRuby::Types::ID)
      expect(mutation_class.arguments[:active][:type]).to eq(ZeroRuby::Types::Boolean)
      expect(mutation_class.arguments[:created_at][:type]).to eq(ZeroRuby::Types::ISO8601DateTime)
      expect(mutation_class.arguments[:birth_date][:type]).to eq(ZeroRuby::Types::ISO8601Date)
    end

    it "works with all type constants" do
      mutation_class = Class.new(ZeroRuby::Mutation) do
        argument :name, ZeroRuby::Types::String
        argument :count, ZeroRuby::Types::Integer
        argument :price, ZeroRuby::Types::Float

        def execute
        end
      end

      expect(mutation_class.arguments[:name][:type]).to eq(ZeroRuby::Types::String)
      expect(mutation_class.arguments[:count][:type]).to eq(ZeroRuby::Types::Integer)
      expect(mutation_class.arguments[:price][:type]).to eq(ZeroRuby::Types::Float)
    end
  end

  describe "in InputObject classes" do
    it "provides Types constant for argument definitions" do
      input_class = Class.new(ZeroRuby::InputObject) do
        argument :id, ZeroRuby::Types::ID
        argument :published, ZeroRuby::Types::Boolean
        argument :event_date, ZeroRuby::Types::ISO8601Date
      end

      metadata = input_class.arguments_metadata
      expect(metadata[:id][:type]).to eq(ZeroRuby::Types::ID)
      expect(metadata[:published][:type]).to eq(ZeroRuby::Types::Boolean)
      expect(metadata[:event_date][:type]).to eq(ZeroRuby::Types::ISO8601Date)
    end
  end
end
