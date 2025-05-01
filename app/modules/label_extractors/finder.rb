# frozen_string_literal: true

module LabelExtractors
  class Finder
    class UnknownExtractor < StandardError; end
    class UnknownTaskKey < StandardError; end

    # hard code Galaxy Zoo for now as these will fail due to missing constant lookup
    # long term we can add these back in and make the lookup dynamic
    EXTRACTOR_SCHEMA_CLASS_REGEX = /\A(galaxy_zoo)_(decals|cosmic_dawn|euclid|jwst_cosmos)_(.+)\z/.freeze

    def self.extractor_instance(task_schema_lookup_key)
      # simulate a regex lookup failure with the || [nil, task_schema_lookup_key] as it'll raise a NameError when trying to constantize
      schema_name_and_task = EXTRACTOR_SCHEMA_CLASS_REGEX.match(task_schema_lookup_key) || [nil, task_schema_lookup_key]
      schema_klass = "LabelExtractors::#{schema_name_and_task[1].camelize}::#{schema_name_and_task[2].camelize}".constantize
      task_key = schema_name_and_task[3].upcase
      schema_klass.new(task_key)
    rescue NameError => _e
      raise UnknownExtractor, "no extractor class found for '#{schema_name_and_task[1]}'"
    end
  end
end
