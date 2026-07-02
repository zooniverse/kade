# frozen_string_literal: true

module Admin
  class ContextsController < BaseController
    rescue_from ::Contexts::CreateAttributes::ValidationError,
                ::Contexts::UpdateAttributes::ValidationError,
                Batch::RuntimeConfig::ValidationError,
                ActiveRecord::RecordInvalid do |e|
      flash.now[:error] = e.message
      @context =
        if params[:id]
          Context.find(params[:id])
        else
          Context.new(context_form_params.except('metadata'))
        end
      render action_name == 'create' ? :new : :edit, status: :unprocessable_entity
    end
    rescue_from ActiveRecord::DeleteRestrictionError do |e|
      redirect_to admin_context_path(params[:id]), alert: e.message
    end

    def index
      @contexts, @pagination = paginate(Context.order(id: :desc))
    end

    def show
      @context = Context.find(params[:id])
      @matching_definitions = matching_definitions(@context)
    end

    def new
      @context = Context.new(
        metadata: {
          'batch' => {}
        }
      )
    end

    def create
      @context = ::Contexts::CreateAttributes.new(params: context_form_params).call
      redirect_to admin_context_path(@context), notice: 'Context created'
    end

    def edit
      @context = Context.find(params[:id])
    end

    def update
      @context = Context.find(params[:id])
      ::Contexts::UpdateAttributes.new(context: @context, params: context_form_params).call
      redirect_to admin_context_path(@context), notice: 'Context updated'
    end

    def trigger_prediction_job
      context = Context.find(params[:id])
      job_id = PredictionManifestExportJob.perform_async(context.id)
      redirect_to admin_context_path(context), notice: "Prediction job with id #{job_id} triggered"
    end

    def trigger_training_job
      context = Context.find(params[:id])
      job_id = RetrainZoobotJob.perform_async(context.id)
      redirect_to admin_context_path(context), notice: "Training job with id #{job_id} triggered"
    end

    def destroy
      context = Context.find(params[:id])
      context.destroy!
      redirect_to admin_contexts_path, notice: 'Context deleted'
    end

    private

    def context_form_params
      permitted = params.require(:context).permit(
        *::Contexts::UpdateAttributes::CONTEXT_ATTRIBUTE_KEYS,
        :metadata_json
      )

      raw = permitted.to_h
      metadata_json = raw.delete('metadata_json')
      raw['metadata'] = parse_json_field(metadata_json, field_name: 'metadata') if metadata_json.present?
      raw
    end

    def parse_json_field(raw_json, field_name:)
      JSON.parse(raw_json)
    rescue JSON::ParserError => e
      raise ::Contexts::UpdateAttributes::ValidationError, "#{field_name} must be valid JSON: #{e.message}"
    end

    def matching_definitions(context)
      LabelExtractorDefinition.where(
        module_name: context.module_name,
        extractor_name: context.extractor_name
      ).order(updated_at: :desc)
    end
  end
end
