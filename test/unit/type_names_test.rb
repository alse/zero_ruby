# frozen_string_literal: true

require_relative "../test_helper"

# Test mutations using shorthand types
# These are defined at module level so shorthand constants are in scope
class TypeNamesTestMutation < ZeroRuby::Mutation
  argument :id, ID, required: true
  argument :active, Boolean, required: true
  argument :score, BigInt, required: false
  argument :due_date, ISO8601Date, required: false
  argument :created_at, ISO8601DateTime, required: false

  def execute(**)
  end
end

class TypeNamesTestInputObject < ZeroRuby::InputObject
  argument :id, ID, required: true
  argument :enabled, Boolean, required: true
end

class TypeNamesTest < Minitest::Test
  # Test that constants point to correct types
  def test_id_constant_points_to_id_type
    assert_equal ZeroRuby::Types::ID, ZeroRuby::TypeNames::ID
  end

  def test_boolean_constant_points_to_boolean_type
    assert_equal ZeroRuby::Types::Boolean, ZeroRuby::TypeNames::Boolean
  end

  def test_big_int_constant_points_to_big_int_type
    assert_equal ZeroRuby::Types::BigInt, ZeroRuby::TypeNames::BigInt
  end

  def test_iso8601_date_constant_points_to_iso8601_date_type
    assert_equal ZeroRuby::Types::ISO8601Date, ZeroRuby::TypeNames::ISO8601Date
  end

  def test_iso8601_date_time_constant_points_to_iso8601_date_time_type
    assert_equal ZeroRuby::Types::ISO8601DateTime, ZeroRuby::TypeNames::ISO8601DateTime
  end

  # Test that TypeNames is included in Mutation
  def test_mutation_includes_type_names
    assert_includes ZeroRuby::Mutation.included_modules, ZeroRuby::TypeNames
  end

  # Test that TypeNames is included in InputObject
  def test_input_object_includes_type_names
    assert_includes ZeroRuby::InputObject.included_modules, ZeroRuby::TypeNames
  end

  # Test that shorthand types work in mutation argument declarations
  def test_shorthand_types_in_mutation_arguments
    args = TypeNamesTestMutation.arguments

    assert_equal ZeroRuby::Types::ID, args[:id].type
    assert_equal ZeroRuby::Types::Boolean, args[:active].type
    assert_equal ZeroRuby::Types::BigInt, args[:score].type
    assert_equal ZeroRuby::Types::ISO8601Date, args[:due_date].type
    assert_equal ZeroRuby::Types::ISO8601DateTime, args[:created_at].type
  end

  # Test that shorthand types work in input object argument declarations
  def test_shorthand_types_in_input_object_arguments
    args = TypeNamesTestInputObject.arguments

    assert_equal ZeroRuby::Types::ID, args[:id].type
    assert_equal ZeroRuby::Types::Boolean, args[:enabled].type
  end

  # Test coercion through shorthand types
  def test_shorthand_id_coercion_in_mutation
    mutation = TypeNamesTestMutation.new({id: "abc-123", active: true}, {})
    mutation.call
    # If we got here without error, the ID was coerced correctly
  end

  def test_shorthand_boolean_coercion_in_mutation
    mutation = TypeNamesTestMutation.new({id: "test", active: "true"}, {})
    mutation.call
    # If we got here without error, the Boolean was coerced correctly from string
  end
end
