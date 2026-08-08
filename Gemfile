# frozen_string_literal: true

source 'https://rubygems.org'

gemspec

group :development, :test do
  gem 'minitest', '~> 5.20'
  gem 'rake', '~> 13.0'
  # Patch-level pin: CI resolves gems fresh on every run, and new
  # rubocop minors have failed it with cop changes on untouched
  # code. Bump deliberately, with the autocorrect in the same
  # commit.
  gem 'rubocop', '~> 1.89.0', require: false
  gem 'rubocop-minitest', '~> 0.35', require: false
  gem 'rubocop-rake', '~> 0.6', require: false
end
