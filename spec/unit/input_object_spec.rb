# frozen_string_literal: true

require "spec_helper"

# Test input object with various argument configurations
class TestPostInput < ZeroRuby::InputObject
  argument :id, ZeroRuby::Types::String
  argument :title, ZeroRuby::Types::String.constrained(max_size: 50)
  argument :published, ZeroRuby::Types::Boolean.default(false)
  argument :tags, ZeroRuby::Types::String.optional  # optional, no default
end

# Test nested input objects
class TestAuthorInput < ZeroRuby::InputObject
  argument :name, ZeroRuby::Types::String
  argument :email, ZeroRuby::Types::String.optional
end

class TestArticleInput < ZeroRuby::InputObject
  argument :title, ZeroRuby::Types::String
  argument :author, TestAuthorInput
  argument :co_author, TestAuthorInput.optional
end

# Test mutation using input object
class CreatePostMutation < ZeroRuby::Mutation
  argument :post_input, TestPostInput
  argument :notify, ZeroRuby::Types::Boolean.default(false)

  attr_reader :received_post_input, :received_notify

  def execute(post_input:, notify:)
    transact do
      @received_post_input = post_input
      @received_notify = notify
    end
    nil
  end
end

# Test mutation with nested input object
class CreateArticleMutation < ZeroRuby::Mutation
  argument :article, TestArticleInput

  attr_reader :received_article

  def execute(article:)
    transact do
      @received_article = article
    end
    nil
  end
end

describe ZeroRuby::InputObject do
  let(:ctx) { {current_user: OpenStruct.new(id: 1)}.freeze }

  # Simple transact mock that just executes the user's block
  let(:transact) { proc { |&blk| blk.call } }

  describe "basic coercion" do
    it "coerces nested hash to struct instance" do
      mutation = CreatePostMutation.new({
        "post_input" => {"id" => "123", "title" => "Hello", "published" => "true"},
        "notify" => "true"
      }, ctx)
      mutation.call(&transact)

      # args[:post_input] is now an InputObject instance
      expect(mutation.received_post_input).to be_a(TestPostInput)
      expect(mutation.received_post_input.id).to eq("123")
      expect(mutation.received_post_input.title).to eq("Hello")
      expect(mutation.received_post_input.published).to eq(true)
      expect(mutation.received_notify).to eq(true)
    end

    it "supports to_hash for struct instances" do
      mutation = CreatePostMutation.new({
        "post_input" => {"id" => "123", "title" => "Hello", "published" => "true"}
      }, ctx)
      mutation.call(&transact)

      # InputObject supports to_hash via Dry::Struct
      hash = mutation.received_post_input.to_hash
      expect(hash[:id]).to eq("123")
      expect(hash[:title]).to eq("Hello")
      expect(hash[:published]).to eq(true)
    end
  end

  describe "missing key handling" do
    it "uses default when key is missing and has default" do
      mutation = CreatePostMutation.new({
        "post_input" => {"id" => "123", "title" => "Hello"}
        # published is missing, should use default false
      }, ctx)
      mutation.call(&transact)

      expect(mutation.received_post_input.published).to eq(false)
      expect(mutation.received_notify).to eq(false)
    end

    it "raises ValidationError when required key is missing" do
      expect {
        CreatePostMutation.new({
          "post_input" => {"id" => "123"}  # missing required title
        }, ctx)
      }.to raise_error(ZeroRuby::ValidationError) { |error|
        expect(error.errors.first).to include("title")
      }
    end

    it "handles optional key that is missing with no default" do
      mutation = CreatePostMutation.new({
        "post_input" => {"id" => "123", "title" => "Hello"}
        # tags is missing, optional, no default
      }, ctx)
      mutation.call(&transact)

      # Optional fields without defaults are nil when missing
      expect(mutation.received_post_input.tags).to be_nil
    end
  end

  describe "explicit null handling" do
    it "raises ValidationError when required field receives explicit null" do
      expect {
        CreatePostMutation.new({
          "post_input" => {"id" => "123", "title" => nil}
        }, ctx)
      }.to raise_error(ZeroRuby::ValidationError) { |error|
        expect(error.errors.first).to include("title")
      }
    end

    it "includes nil in result when optional field receives explicit null" do
      mutation = CreatePostMutation.new({
        "post_input" => {"id" => "123", "title" => "Hello", "tags" => nil}
      }, ctx)
      mutation.call(&transact)

      expect(mutation.received_post_input.tags).to be_nil
    end
  end

  describe "validation" do
    it "raises ValidationError for constraint violations" do
      expect {
        CreatePostMutation.new({
          "post_input" => {"id" => "123", "title" => "x" * 51}
        }, ctx)
      }.to raise_error(ZeroRuby::ValidationError) { |error|
        expect(error.errors.first).to include("post_input")
      }
    end
  end

  describe "nested InputObjects" do
    it "coerces nested InputObject" do
      mutation = CreateArticleMutation.new({
        "article" => {
          "title" => "My Article",
          "author" => {"name" => "John", "email" => "john@example.com"}
        }
      }, ctx)
      mutation.call(&transact)

      expect(mutation.received_article).to be_a(TestArticleInput)
      expect(mutation.received_article.title).to eq("My Article")
      expect(mutation.received_article.author).to be_a(TestAuthorInput)
      expect(mutation.received_article.author.name).to eq("John")
      expect(mutation.received_article.author.email).to eq("john@example.com")
    end

    it "handles optional nested InputObject when missing" do
      mutation = CreateArticleMutation.new({
        "article" => {
          "title" => "My Article",
          "author" => {"name" => "John"}
        }
      }, ctx)
      mutation.call(&transact)

      expect(mutation.received_article.co_author).to be_nil
    end

    it "handles optional nested InputObject when provided" do
      mutation = CreateArticleMutation.new({
        "article" => {
          "title" => "My Article",
          "author" => {"name" => "John"},
          "co_author" => {"name" => "Jane"}
        }
      }, ctx)
      mutation.call(&transact)

      expect(mutation.received_article.co_author).to be_a(TestAuthorInput)
      expect(mutation.received_article.co_author.name).to eq("Jane")
    end

    it "validates nested InputObject fields" do
      expect {
        CreateArticleMutation.new({
          "article" => {
            "title" => "My Article",
            "author" => {}  # missing required name
          }
        }, ctx)
      }.to raise_error(ZeroRuby::ValidationError) { |error|
        expect(error.errors.first).to include("name")
      }
    end
  end

  describe "arguments_metadata" do
    it "returns metadata for all arguments" do
      metadata = TestPostInput.arguments_metadata

      expect(metadata.keys).to contain_exactly(:id, :title, :published, :tags)
    end

    it "includes type information" do
      metadata = TestPostInput.arguments_metadata

      expect(metadata[:id][:name]).to eq(:id)
      expect(metadata[:title][:name]).to eq(:title)
    end

    it "identifies required vs optional fields" do
      metadata = TestPostInput.arguments_metadata

      expect(metadata[:id][:required]).to be true
      expect(metadata[:title][:required]).to be true
      expect(metadata[:tags][:required]).to be false  # optional
    end
  end

  describe "string key transformation" do
    it "converts string keys to symbols when creating struct" do
      input = TestPostInput.new({
        "id" => "123",
        "title" => "Hello"
      })

      expect(input.id).to eq("123")
      expect(input.title).to eq("Hello")
    end

    it "accepts symbol keys directly" do
      input = TestPostInput.new({
        id: "123",
        title: "Hello"
      })

      expect(input.id).to eq("123")
      expect(input.title).to eq("Hello")
    end
  end

  describe "extra keys handling" do
    it "ignores extra keys due to strict(false) schema" do
      input = TestPostInput.new({
        "id" => "123",
        "title" => "Hello",
        "unknown_field" => "should be ignored",
        "another_extra" => 42
      })

      expect(input.id).to eq("123")
      expect(input.title).to eq("Hello")
      expect(input.respond_to?(:unknown_field)).to be false
    end
  end

  describe "argument_descriptions" do
    it "stores descriptions when provided" do
      input_class = Class.new(ZeroRuby::InputObject) do
        argument :name, ZeroRuby::Types::String, description: "User's name"
        argument :age, ZeroRuby::Types::Integer
      end

      descriptions = input_class.argument_descriptions
      expect(descriptions[:name]).to eq("User's name")
      expect(descriptions[:age]).to be_nil
    end
  end

  describe "to_hash with nested InputObjects" do
    it "recursively converts nested InputObjects to hashes" do
      mutation = CreateArticleMutation.new({
        "article" => {
          "title" => "My Article",
          "author" => {"name" => "John", "email" => "john@example.com"}
        }
      }, ctx)
      mutation.call(&transact)

      hash = mutation.received_article.to_hash
      expect(hash[:author]).to be_a(Hash)
      expect(hash[:author][:name]).to eq("John")
    end
  end

  describe "empty InputObject" do
    it "handles InputObjects with no arguments" do
      empty_class = Class.new(ZeroRuby::InputObject)

      expect { empty_class.new({}) }.not_to raise_error
      instance = empty_class.new({})
      expect(instance.to_hash).to eq({})
    end
  end
end
