# frozen_string_literal: true

class ApplicationController < ActionController::API
  rescue_from LabelExtractors::ConfigurationError,
              LabelExtractors::UnknownTaskKey,
              LabelExtractors::UnknownLabelKey,
              LabelExtractors::GalaxyZoo::UnknownTaskKey,
              LabelExtractors::GalaxyZoo::UnknownLabelKey,
              LabelExtractors::Finder::UnknownExtractor do |e|
    # keep notifying HB about these errors - longer term remove if noisy
    Honeybadger.notify(e)
    # and respond to the client with a useful error message so they can fix it
    json_error_render(:unprocessable_entity, e)
  end

  private

  # allow the page size to be set via ?page_size=10 query param
  # but clamp it between 0 and 100 to ensure a reasonable result set
  def params_page_size
    (params[:page_size] || 10).to_i.clamp(0, 100)
  end

  def json_error_render(status, exception)
    render(
      status: status,
      json: { 'errors' => [{ 'type' => exception.class, 'detail' => exception.message }] }
    )
  end
end
