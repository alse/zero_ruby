build:
    gem build zero_ruby.gemspec

release: build
    gem push zero_ruby-$(ruby -e "require './lib/zero_ruby/version'; puts ZeroRuby::VERSION").gem
