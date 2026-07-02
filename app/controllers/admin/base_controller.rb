# frozen_string_literal: true

module Admin
  class BaseController < ActionController::Base
    layout 'admin'
    protect_from_forgery with: :exception

    http_basic_authenticate_with(
      name: Rails.application.config.admin_basic_auth_username,
      password: Rails.application.config.admin_basic_auth_password
    )

    helper_method :pretty_json, :pagination_path_for, :pagination_items

    private

    def params_page_size
      (params[:page_size] || 25).to_i.clamp(1, 100)
    end

    def current_page
      (params[:page] || 1).to_i.clamp(1, 10_000)
    end

    def paginate(scope)
      total_count = scope.count
      records = scope.offset((current_page - 1) * params_page_size).limit(params_page_size)

      [records, pagination_metadata(total_count)]
    end

    def pagination_metadata(total_count)
      total_pages = (total_count.to_f / params_page_size).ceil
      total_pages = 1 if total_pages.zero?

      {
        current_page: current_page,
        page_size: params_page_size,
        total_count: total_count,
        total_pages: total_pages,
        has_previous: current_page > 1,
        has_next: current_page < total_pages
      }
    end

    def pagination_path_for(page)
      query_params = request.query_parameters.merge('page' => page, 'page_size' => params_page_size)
      query_params = query_params.reject { |_key, value| value.blank? }
      query_string = query_params.to_query
      query_string.present? ? "#{request.path}?#{query_string}" : request.path
    end

    def pagination_items(total_pages, page)
      return [1] if total_pages <= 1

      pages = [1, total_pages]
      ((page - 2)..(page + 2)).each do |page_number|
        pages << page_number if page_number.between?(1, total_pages)
      end

      sorted_pages = pages.uniq.sort
      items = []

      sorted_pages.each_with_index do |page_number, index|
        previous_page_number = sorted_pages[index - 1]
        items << :gap if previous_page_number && page_number - previous_page_number > 1
        items << page_number
      end

      items
    end

    def pretty_json(value)
      JSON.pretty_generate(value.presence || {})
    end
  end
end
