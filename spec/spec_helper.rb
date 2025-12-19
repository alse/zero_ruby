# frozen_string_literal: true

require "ostruct"
require_relative "support/database_setup"

# Connect to PostgreSQL and set up schema
ZeroRuby::TestHelpers::DatabaseSetup.connect!
ZeroRuby::TestHelpers::DatabaseSetup.setup_schema!

# Load zero_ruby after ActiveRecord is available
require "zero_ruby"

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.warnings = true
  config.order = :random
  Kernel.srand config.seed

  # Truncate tables before each test for isolation
  config.before(:each) do
    ZeroRuby::TestHelpers::DatabaseSetup.truncate!
  end
end
