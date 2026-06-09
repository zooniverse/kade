# frozen_string_literal: true

require 'sidekiq/web'
# load the UI for sidekiq-cron
# https://github.com/sidekiq-cron/sidekiq-cron#web-ui-for-cron-jobs
require 'sidekiq/cron/web'

Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # https://github.com/mperham/sidekiq/wiki/Monitoring#rails-http-basic-auth-from-routes
  Sidekiq::Web.use Rack::Auth::Basic do |username, password|
    # Protect against timing attacks:
    # - See https://codahale.com/a-lesson-in-timing-attacks/
    # - See https://thisdata.com/blog/timing-attacks-against-string-comparison/
    # - Use & (do not use &&) so that it doesn't short circuit.
    # - Use digests to stop length information leaking (see also ActiveSupport::SecurityUtils.variable_size_secure_compare)
    user_name_valid = ActiveSupport::SecurityUtils.secure_compare(
      ::Digest::SHA256.hexdigest(username),
      ::Digest::SHA256.hexdigest(Rails.application.config.api_basic_auth_username)
    )
    password_valid = ActiveSupport::SecurityUtils.secure_compare(
      ::Digest::SHA256.hexdigest(password),
      ::Digest::SHA256.hexdigest(Rails.application.config.api_basic_auth_password)
    )
    user_name_valid & password_valid
  end if Rails.env.production? || Rails.env.staging?

  mount Sidekiq::Web => '/sidekiq'

  # https://lipanski.com/posts/activestorage-cdn-rails-direct-route
  # add a direct public URL path helper for serving public assets
  # via a hosted DNS / CDN instead of via the blob service storage URL
  # e.g. Rails.application.routes.url_helpers.rails_public_blob_url(TrainingDataExport.first.file)
  # linked to private / public storage services
  #
  # direct :rails_public_blob do |blob|
  #   File.join(ENV['CDN_HOST'], blob.key)
  # end

  # Defines the root path route ("/")
  root 'home#index'

  resources :subjects, only: %i[index show]

  resources :training_data_exports, only: %i[index show create]

  resources :reductions, only: %i[index show] do
    collection do
      # encode the task schema lookup key via the URL
      # define which task schema labels are extracted for incoming data payload
      post ':task_schema_lookup_key', to: 'reductions#create'
    end
  end

  resources :prediction_jobs, only: %i[index show create]

  resources :training_jobs, only: %i[index show]

  resources :contexts, only: %i[index show update]

  namespace :admin do
    root 'contexts#index'
    resources :contexts, only: %i[index show new create edit update destroy] do
      resources :label_extractor_definitions, only: %i[index], module: :contexts
    end
    resources :label_extractor_definitions, only: %i[index new create edit update destroy]
  end

  # all other routes go here
end
