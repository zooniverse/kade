# frozen_string_literal: true

module Admin
  class LabelExtractorDefinitionsController < BaseController
    class ValidationError < StandardError; end

    rescue_from ActiveRecord::RecordInvalid do
      flash.now[:error] = @definition.errors.full_messages.to_sentence
      prepare_form_state
      render action_name == 'update' ? :edit : :new, status: :unprocessable_entity
    end
    rescue_from ValidationError do |e|
      flash.now[:error] = e.message
      prepare_form_state
      render action_name == 'create' ? :new : :edit, status: :unprocessable_entity
    end

    def index
      @definitions, @pagination = paginate(LabelExtractorDefinition.order(updated_at: :desc))
    end

    def new
      @definition = LabelExtractorDefinition.new(enabled: true)
    end

    def create
      @definition = LabelExtractorDefinition.new(definition_attributes)
      @definition.save!
      redirect_to admin_label_extractor_definitions_path, notice: 'Label extractor definition created'
    end

    def edit
      @definition = LabelExtractorDefinition.find(params[:id])
      @return_to = resolved_return_to
    end

    def update
      @definition = LabelExtractorDefinition.find(params[:id])
      @definition.update!(definition_attributes)
      redirect_to resolved_return_to, notice: 'Label extractor definition updated'
    end

    def destroy
      definition = LabelExtractorDefinition.find(params[:id])
      definition.destroy!
      redirect_to admin_label_extractor_definitions_path, notice: 'Label extractor definition deleted'
    end

    private

    def definition_form_params
      params.require(:label_extractor_definition).permit(
        :module_name,
        :extractor_name,
        :enabled,
        :config_json
      )
    end

    def definition_attributes
      {
        module_name: definition_form_params[:module_name],
        extractor_name: definition_form_params[:extractor_name],
        enabled: truthy?(definition_form_params[:enabled]),
        config: parse_json_field(definition_form_params[:config_json], field_name: 'config')
      }
    end

    def parse_json_field(raw_json, field_name:)
      JSON.parse(raw_json.presence || '{}')
    rescue JSON::ParserError => e
      raise ValidationError, "#{field_name} must be valid JSON: #{e.message}"
    end

    def truthy?(value)
      ActiveModel::Type::Boolean.new.cast(value)
    end

    def prepare_form_state
      @definition ||= params[:id] ? LabelExtractorDefinition.find(params[:id]) : LabelExtractorDefinition.new(enabled: true)
      @return_to = resolved_return_to
      return unless params[:label_extractor_definition]

      @definition.assign_attributes(
        module_name: definition_form_params[:module_name],
        extractor_name: definition_form_params[:extractor_name],
        enabled: truthy?(definition_form_params[:enabled])
      )
      @config_json_value = definition_form_params[:config_json]
    end

    def resolved_return_to
      requested_path = params[:return_to].presence
      return admin_label_extractor_definitions_path if requested_path.blank?

      uri = URI.parse(requested_path)
      return admin_label_extractor_definitions_path if uri.host.present? || uri.scheme.present?
      return admin_label_extractor_definitions_path unless uri.path.start_with?('/admin')

      uri.to_s
    rescue URI::InvalidURIError
      admin_label_extractor_definitions_path
    end
  end
end
