# frozen_string_literal: true

require_relative "../test_helper"

# Test input object
class TestPostInput < ZeroRuby::InputObject
  argument :id, ZeroRuby::Types::String, required: true
  argument :title, ZeroRuby::Types::String, required: true, validates: {length: {maximum: 50}}
  argument :published, ZeroRuby::Types::Boolean, required: false, default: false
end

# Test mutation using input object
class CreatePostMutation < ZeroRuby::Mutation
  argument :post_input, TestPostInput, required: true
  argument :notify, ZeroRuby::Types::Boolean, required: false, default: false

  attr_reader :received_post_input, :received_notify

  def execute(post_input:, notify:)
    @received_post_input = post_input
    @received_notify = notify
  end
end

class InputObjectTest < Minitest::Test
  def setup
    @ctx = {current_user: OpenStruct.new(id: 1)}.freeze
  end

  def test_input_object_coerces_nested_hash
    mutation = CreatePostMutation.new({
      post_input: {id: "123", title: "Hello", published: "true"},
      notify: "true"
    }, @ctx)
    mutation.call

    assert_equal({id: "123", title: "Hello", published: true}, mutation.received_post_input)
    assert_equal true, mutation.received_notify
  end

  def test_input_object_applies_defaults
    mutation = CreatePostMutation.new({
      post_input: {id: "123", title: "Hello"}
    }, @ctx)
    mutation.call

    assert_equal false, mutation.received_post_input[:published]
    assert_equal false, mutation.received_notify
  end

  def test_input_object_validates_nested_fields
    error = assert_raises(ZeroRuby::ValidationError) do
      CreatePostMutation.new({
        post_input: {id: "123", title: "x" * 51}
      }, @ctx)
    end
    assert error.errors.any? { |e| e.include?("too long") }
  end

  def test_input_object_validates_required_nested_fields
    error = assert_raises(ZeroRuby::ValidationError) do
      CreatePostMutation.new({
        post_input: {id: "123"}  # missing required title
      }, @ctx)
    end
    assert error.errors.any? { |e| e.include?("title is required") }
  end

  def test_input_object_can_be_splatted
    mutation = CreatePostMutation.new({
      post_input: {id: "123", title: "Hello"}
    }, @ctx)
    mutation.call

    # Simulate what you'd do in execute
    splatted = {**mutation.received_post_input}
    assert_equal "123", splatted[:id]
    assert_equal "Hello", splatted[:title]
  end
end
