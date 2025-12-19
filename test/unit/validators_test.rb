# frozen_string_literal: true

require_relative "../test_helper"

class ValidatorsTest < Minitest::Test
  def setup
    @ctx = {current_user: nil}.freeze
  end

  # LengthValidator tests
  def test_length_validator_minimum_passes
    validator = ZeroRuby::Validators::LengthValidator.new(minimum: 3)
    assert_nil validator.validate(nil, @ctx, "hello")
  end

  def test_length_validator_minimum_fails
    validator = ZeroRuby::Validators::LengthValidator.new(minimum: 5)
    result = validator.validate(nil, @ctx, "hi")
    assert_includes result, "is too short (minimum is 5)"
  end

  def test_length_validator_maximum_passes
    validator = ZeroRuby::Validators::LengthValidator.new(maximum: 10)
    assert_nil validator.validate(nil, @ctx, "hello")
  end

  def test_length_validator_maximum_fails
    validator = ZeroRuby::Validators::LengthValidator.new(maximum: 3)
    result = validator.validate(nil, @ctx, "hello")
    assert_includes result, "is too long (maximum is 3)"
  end

  # NumericalityValidator tests
  def test_numericality_greater_than_passes
    validator = ZeroRuby::Validators::NumericalityValidator.new(greater_than: 5)
    assert_nil validator.validate(nil, @ctx, 10)
  end

  def test_numericality_greater_than_fails
    validator = ZeroRuby::Validators::NumericalityValidator.new(greater_than: 5)
    result = validator.validate(nil, @ctx, 3)
    assert_includes result, "must be greater than 5"
  end

  def test_numericality_less_than_passes
    validator = ZeroRuby::Validators::NumericalityValidator.new(less_than: 10)
    assert_nil validator.validate(nil, @ctx, 5)
  end

  def test_numericality_less_than_fails
    validator = ZeroRuby::Validators::NumericalityValidator.new(less_than: 5)
    result = validator.validate(nil, @ctx, 10)
    assert_includes result, "must be less than 5"
  end

  def test_numericality_rejects_non_numeric
    validator = ZeroRuby::Validators::NumericalityValidator.new(greater_than: 0)
    result = validator.validate(nil, @ctx, "not a number")
    assert_equal "is not a number", result
  end

  # FormatValidator tests
  def test_format_with_pattern_passes
    validator = ZeroRuby::Validators::FormatValidator.new(with: /\A[a-z]+\z/)
    assert_nil validator.validate(nil, @ctx, "hello")
  end

  def test_format_with_pattern_fails
    validator = ZeroRuby::Validators::FormatValidator.new(with: /\A[a-z]+\z/)
    result = validator.validate(nil, @ctx, "Hello123")
    assert_includes result, "is invalid"
  end

  # InclusionValidator tests
  def test_inclusion_passes_when_in_array
    validator = ZeroRuby::Validators::InclusionValidator.new(in: %w[draft published])
    assert_nil validator.validate(nil, @ctx, "draft")
  end

  def test_inclusion_fails_when_not_in_array
    validator = ZeroRuby::Validators::InclusionValidator.new(in: %w[draft published])
    result = validator.validate(nil, @ctx, "archived")
    assert_equal "is not included in the list", result
  end

  # AllowBlankValidator tests
  def test_allow_blank_false_rejects_empty_string
    validator = ZeroRuby::Validators::AllowBlankValidator.new(false)
    result = validator.validate(nil, @ctx, "")
    assert_equal "can't be blank", result
  end

  def test_allow_blank_false_rejects_whitespace
    validator = ZeroRuby::Validators::AllowBlankValidator.new(false)
    result = validator.validate(nil, @ctx, "   ")
    assert_equal "can't be blank", result
  end

  def test_allow_blank_false_accepts_non_blank
    validator = ZeroRuby::Validators::AllowBlankValidator.new(false)
    assert_nil validator.validate(nil, @ctx, "hello")
  end

  def test_allow_blank_true_accepts_empty_string
    validator = ZeroRuby::Validators::AllowBlankValidator.new(true)
    assert_nil validator.validate(nil, @ctx, "")
  end
end
