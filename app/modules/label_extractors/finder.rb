# frozen_string_literal: true

module LabelExtractors
  class Finder
    class UnknownExtractor < StandardError; end

    def self.extractor_instance(task_schema_lookup_key)
      Registry.extractor_instance_from_lookup_key(task_schema_lookup_key)
    end
  end
end
