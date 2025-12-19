# frozen_string_literal: true

require_relative "../test_helper"

class TypesTest < Minitest::Test
  # String type tests
  def test_string_coerces_integer_to_string
    assert_equal "42", ZeroRuby::Types::String.coerce_input(42)
  end

  def test_string_coerces_float_to_string
    assert_equal "3.14", ZeroRuby::Types::String.coerce_input(3.14)
  end

  def test_string_returns_nil_for_nil
    assert_nil ZeroRuby::Types::String.coerce_input(nil)
  end

  def test_string_preserves_string
    assert_equal "hello", ZeroRuby::Types::String.coerce_input("hello")
  end

  # Integer type tests
  def test_integer_coerces_string_to_integer
    assert_equal 42, ZeroRuby::Types::Integer.coerce_input("42")
  end

  def test_integer_coerces_float_to_integer
    assert_equal 3, ZeroRuby::Types::Integer.coerce_input(3.7)
  end

  def test_integer_returns_nil_for_nil
    assert_nil ZeroRuby::Types::Integer.coerce_input(nil)
  end

  def test_integer_raises_coercion_error_for_invalid_string
    error = assert_raises(ZeroRuby::CoercionError) do
      ZeroRuby::Types::Integer.coerce_input("not a number")
    end
    assert_includes error.message, "'not a number'"
    assert_includes error.message, "Integer"
  end

  def test_integer_raises_coercion_error_for_empty_string
    error = assert_raises(ZeroRuby::CoercionError) do
      ZeroRuby::Types::Integer.coerce_input("")
    end
    assert_includes error.message, "empty string"
  end

  def test_integer_preserves_integer
    assert_equal 42, ZeroRuby::Types::Integer.coerce_input(42)
  end

  # Float type tests
  def test_float_coerces_string_to_float
    assert_equal 3.14, ZeroRuby::Types::Float.coerce_input("3.14")
  end

  def test_float_coerces_integer_to_float
    assert_equal 42.0, ZeroRuby::Types::Float.coerce_input(42)
  end

  def test_float_returns_nil_for_nil
    assert_nil ZeroRuby::Types::Float.coerce_input(nil)
  end

  def test_float_raises_coercion_error_for_invalid_string
    error = assert_raises(ZeroRuby::CoercionError) do
      ZeroRuby::Types::Float.coerce_input("not a number")
    end
    assert_includes error.message, "'not a number'"
    assert_includes error.message, "Float"
  end

  def test_float_preserves_float
    assert_equal 3.14, ZeroRuby::Types::Float.coerce_input(3.14)
  end

  # Boolean type tests
  def test_boolean_coerces_true_string
    assert_equal true, ZeroRuby::Types::Boolean.coerce_input("true")
  end

  def test_boolean_coerces_false_string
    assert_equal false, ZeroRuby::Types::Boolean.coerce_input("false")
  end

  def test_boolean_coerces_1_to_true
    assert_equal true, ZeroRuby::Types::Boolean.coerce_input(1)
  end

  def test_boolean_coerces_0_to_false
    assert_equal false, ZeroRuby::Types::Boolean.coerce_input(0)
  end

  def test_boolean_coerces_string_1_to_true
    assert_equal true, ZeroRuby::Types::Boolean.coerce_input("1")
  end

  def test_boolean_coerces_string_0_to_false
    assert_equal false, ZeroRuby::Types::Boolean.coerce_input("0")
  end

  def test_boolean_preserves_true
    assert_equal true, ZeroRuby::Types::Boolean.coerce_input(true)
  end

  def test_boolean_preserves_false
    assert_equal false, ZeroRuby::Types::Boolean.coerce_input(false)
  end

  def test_boolean_returns_nil_for_nil
    assert_nil ZeroRuby::Types::Boolean.coerce_input(nil)
  end

  def test_boolean_raises_coercion_error_for_invalid_value
    error = assert_raises(ZeroRuby::CoercionError) do
      ZeroRuby::Types::Boolean.coerce_input("maybe")
    end
    assert_includes error.message, "'maybe'"
    assert_includes error.message, "Boolean"
    assert_includes error.message, "true, false"
  end
end
