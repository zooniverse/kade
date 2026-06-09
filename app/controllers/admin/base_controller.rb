# frozen_string_literal: true

module Admin
  class BaseController < ActionController::Base
    layout 'admin'
    protect_from_forgery with: :exception

    http_basic_authenticate_with(
      name: Rails.application.config.admin_basic_auth_username,
      password: Rails.application.config.admin_basic_auth_password
    )

    helper_method :pretty_json

    private

    def params_page_size
      (params[:page_size] || 25).to_i.clamp(0, 100)
    end

    def pretty_json(value)
      JSON.pretty_generate(value.presence || {})
    end
  end
end
