# frozen_string_literal: true

module Batch
  class ContextRuntimeOptions
    class << self
      def for_training(context)
        build(context, mode: :training)
      end

      def for_prediction(context)
        build(context, mode: :prediction)
      end

      private

      def build(context, mode:)
        metadata = context.metadata.is_a?(Hash) ? context.metadata : {}
        batch_config = metadata['batch'].is_a?(Hash) ? metadata['batch'] : {}

        {
          workflow_name: context.extractor_name,
          fixed_crop: batch_config['fixed_crop'] || metadata['fixed_crop'],
          n_blocks: batch_config['n_blocks'] || metadata['n_blocks'],
          container_image_name: batch_config['container_image_name'],
          training_script_path: batch_config['training_script_path'],
          prediction_script_path: batch_config['prediction_script_path'],
          promote_script_path: batch_config['promote_script_path'],
          pretrained_checkpoint_url: batch_config['pretrained_checkpoint_url']
        }.compact.tap do |opts|
          if mode == :training
            opts.delete(:prediction_script_path)
          else
            opts.delete(:training_script_path)
            opts.delete(:promote_script_path)
            opts.delete(:n_blocks)
          end
        end
      end
    end
  end
end
