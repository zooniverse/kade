# frozen_string_literal: true

source 'https://rubygems.org'
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

gem 'async-http-faraday'

# used for Azure active storage
gem 'azure-storage-blob'

# Reduces boot times through caching; required in config/boot.rb
gem 'bootsnap', require: false

# Build JSON APIs with ease [https://github.com/rails/jbuilder]
# gem 'jbuilder'

gem 'httparty'

gem 'panoptes-client'
gem 'pg'
gem 'puma'

# Use Rack CORS for handling Cross-Origin Resource Sharing (CORS), making cross-origin AJAX possible
gem 'rack-cors'
gem 'rails', '~> 8.0'

# gem 'redis', '~> 4.0'
# Use Kredis to get higher-level data types in Redis [https://github.com/rails/kredis]
# gem 'kredis'

gem 'sidekiq'
gem 'sidekiq-cron'
gem 'strong_migrations'

group :production, :staging do
  gem 'honeybadger'
  gem 'newrelic_rpm'
end

group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem 'debug'
  gem 'rubocop', require: false
  gem 'rubocop-performance', require: false
  gem 'rubocop-rails', require: false
  gem 'rubocop-rspec', require: false
  # Speed up commands on slow machines / big apps [https://github.com/rails/spring]
  gem 'spring'
  gem 'test-prof'
  # add these gems for custom test system profilers
  # gem 'ruby-prof' # https://test-prof.evilmartians.io/#/profilers/ruby_prof
  # gem 'stackprof' # https://test-prof.evilmartians.io/#/profilers/stack_prof
end

group :test do
  gem 'rspec-rails'
  gem 'spring-commands-rspec'
  gem 'webmock'
end
