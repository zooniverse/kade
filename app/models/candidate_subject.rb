# frozen_string_literal: true

class CandidateSubject < ApplicationRecord
  belongs_to :context

  validates :external_id, presence: true, uniqueness: { scope: :context_id }
  validate :validate_catalogue_data

  private

  def validate_catalogue_data
    errors.add(:metadata, 'must be an object') unless metadata.is_a?(Hash)
    unless locations.is_a?(Array) && locations.size == 1 && valid_location?(locations.first)
      errors.add(:locations, 'must contain exactly one image MIME type / permanent HTTPS URL object')
    end
  end

  def valid_location?(location)
    return false unless location.is_a?(Hash) && location.size == 1

    mime_type, url = location.first
    return false unless mime_type.in?(%w[image/jpeg image/png image/gif image/tiff]) && url.is_a?(String)

    uri = URI.parse(url)
    uri.is_a?(URI::HTTPS) && uri.host.present? && uri.userinfo.nil? && uri.query.nil? && uri.fragment.nil?
  rescue URI::InvalidURIError
    false
  end
end
