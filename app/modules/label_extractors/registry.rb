# frozen_string_literal: true

module LabelExtractors
  class Registry
    DEFAULT_CODE_EXTRACTORS = {
      'galaxy_zoo.cosmic_dawn' => 'LabelExtractors::GalaxyZoo::CosmicDawn',
      'galaxy_zoo.decals' => 'LabelExtractors::GalaxyZoo::Decals',
      'galaxy_zoo.euclid' => 'LabelExtractors::GalaxyZoo::Euclid',
      'galaxy_zoo.jwst_cosmos' => 'LabelExtractors::GalaxyZoo::JwstCosmos'
    }.freeze

    class << self
      def register(module_name, extractor_name, extractor_class)
        code_extractors[registry_key(module_name, extractor_name)] = extractor_class
      end

      def extractor_registered?(module_name, extractor_name)
        extractor_class_for(module_name, extractor_name).present? ||
          LabelExtractorDefinition.find_enabled(module_name, extractor_name).present?
      end

      def extractor_instance(module_name, extractor_name, task_key)
        extractor_class = extractor_class_for(module_name, extractor_name)
        return extractor_class.new(task_key) if extractor_class

        definition = LabelExtractorDefinition.find_enabled(module_name, extractor_name)
        return ConfigurableExtractor.new(task_key, definition.config) if definition

        raise Finder::UnknownExtractor, "no extractor class found for '#{module_name}_#{extractor_name}'"
      end

      def extractor_instance_from_lookup_key(task_schema_lookup_key)
        module_name, extractor_name, task_key = parse_lookup_key(task_schema_lookup_key)
        extractor_instance(module_name, extractor_name, task_key)
      end

      def label_column_headers(module_name, extractor_name)
        %w[id_str file_loc] | question_answers_schema(module_name, extractor_name)
      end

      def question_answers_schema(module_name, extractor_name)
        extractor_class = extractor_class_for(module_name, extractor_name)
        return extractor_class.question_answers_schema if extractor_class

        definition = LabelExtractorDefinition.find_enabled(module_name, extractor_name)
        return ConfigurableExtractor.question_answers_schema(definition.config) if definition

        raise Finder::UnknownExtractor, "no extractor class found for '#{module_name}_#{extractor_name}'"
      end

      def code_extractors
        @code_extractors ||= DEFAULT_CODE_EXTRACTORS.dup
      end

      private

      def extractor_class_for(module_name, extractor_name)
        extractor = code_extractors[registry_key(module_name, extractor_name)]
        extractor.is_a?(String) ? extractor.constantize : extractor
      end

      def parse_lookup_key(task_schema_lookup_key)
        registry_keys = (code_extractors.keys + db_registry_keys).uniq.sort_by { |key| -key.length }
        matched_key = registry_keys.find do |key|
          lookup_prefix = key.tr('.', '_')
          task_schema_lookup_key.start_with?("#{lookup_prefix}_")
        end

        raise Finder::UnknownExtractor, "no extractor class found for '#{task_schema_lookup_key}'" unless matched_key

        module_name, extractor_name = matched_key.split('.', 2)
        task_key = task_schema_lookup_key.delete_prefix("#{matched_key.tr('.', '_')}_").upcase

        [module_name, extractor_name, task_key]
      end

      def db_registry_keys
        LabelExtractorDefinition.enabled.pluck(:module_name, :extractor_name).map do |module_name, extractor_name|
          registry_key(module_name, extractor_name)
        end
      end

      def registry_key(module_name, extractor_name)
        "#{module_name}.#{extractor_name}"
      end
    end
  end
end
