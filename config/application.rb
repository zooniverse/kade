require_relative 'boot'

require 'rails'
# Pick the frameworks you want:
require 'active_model/railtie'
require 'active_record/railtie'
require 'action_controller/railtie'
require 'active_storage/engine'
require "action_mailer/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Kade
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 7.0

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Only loads a smaller set of middleware suitable for API only apps.
    # Middleware like session, flash, cookies can be added back manually.
    # Skip views, helpers and assets when generating a new resource.
    config.api_only = true

    # API basic auth scheme
    # Long term this can switch to Zooniverse API JWT token auth & pundit authorization schemes
    config.api_basic_auth_username = ENV.fetch('API_BASIC_AUTH_USERNAME', 'kade-user')
    config.api_basic_auth_password = ENV.fetch('API_BASIC_AUTH_PASSWORD', 'kade-password')

    # Reduction ingester basic auth scheme (Caesar etc)
    config.reduction_basic_auth_username = ENV.fetch('REDUCTION_BASIC_AUTH_USERNAME', 'kade-user')
    config.reduction_basic_auth_password = ENV.fetch('REDUCTION_BASIC_AUTH_PASSWORD', 'kade-password')

    # Re Add session management for mounting sidekiq UI app
    #
    # This also configures session_options for use below
    config.session_store :cookie_store, key: '_kade_session'
    # Required for all session management (regardless of session_store)
    config.middleware.use ActionDispatch::Cookies
    config.middleware.use config.session_store, config.session_options
  end
end
