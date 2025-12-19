# frozen_string_literal: true

require_relative "lib/zero_ruby/version"

Gem::Specification.new do |spec|
  spec.name = "zero_ruby"
  spec.version = ZeroRuby::VERSION
  spec.authors = ["Alex Serban"]

  spec.summary = "Ruby gem for handling Zero mutations with type safety"
  spec.description = "Handle Zero mutations with runtime type safety"
  spec.homepage = "https://github.com/alse/zero-ruby"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  spec.files = Dir.glob("{lib}/**/*") + %w[LICENSE.txt README.md CHANGELOG.md]
  spec.require_paths = ["lib"]

  # Runtime dependencies
  # None required - pure Ruby implementation

  # Development dependencies
  spec.add_development_dependency "bundler", "~> 2.5"
  spec.add_development_dependency "minitest", "~> 5.27"
  spec.add_development_dependency "ostruct"  # Will be removed from default gems in Ruby 3.5
  spec.add_development_dependency "rake", "~> 13.3"
  spec.add_development_dependency "standard", "~> 1.51"
end
