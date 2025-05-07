# frozen_string_literal: true

require 'csv'

module Format
  class TrainingDataCsv
    class MissingLocationData < StandardError; end
    attr_reader :workflow_id, :temp_file, :column_headers, :label_column_headers, :grouped_reductions

    GroupedReduction = Struct.new(:subject_id, :unique_id, :labels)

    def initialize(workflow_id, column_headers)
      @workflow_id = workflow_id
      @temp_file = Tempfile.new("reductions_workflow_id_#{workflow_id}.csv")
      @column_headers = column_headers
      # remove the first 2 column headers (id_str & file_loc_path)
      @label_column_headers = column_headers[2..-1]
      @grouped_reductions = []
    end

    def run
      csv << column_headers
      # dynamically create the 'grouped' reductions for all known subject task labels
      create_grouped_reductions
      grouped_reductions.each do |grouped_reduction|
        reduced_subject = Subject.find(grouped_reduction.subject_id)

        # if location subject data is available
        # raise short term so we understand frequent / how this happens
        # and long term maybe move to skipping?
        raise MissingLocationData, "For subject id: #{reduced_subject.id}" if reduced_subject.locations.blank?

        # Ensure we handle multi image subjects here
        # assume we will only train on first image
        location = reduced_subject.locations.first
        # each location is an object containing only 1 mimetype key and an image URL
        image_url = location.values.first
        csv << [
          grouped_reduction.unique_id,
          Zoobot::Storage.container_image_path(image_url),
          # fetch all the reduction's saved question:answer values
          # ensure we add 0's to the missing column headers - Zoobot demands this!
          # https://zoobot.readthedocs.io/guides/training_from_scratch.html#creating-a-catalog
          *grouped_reduction.labels.fetch_values(*label_column_headers) { |_key| 0 }
        ]
      end
      temp_file.rewind
      temp_file
    end

    private

    def csv
      @csv ||= CSV.new(temp_file)
    end

    def create_grouped_reductions
      # avoid the AR cache for this query to avoid excess object allocations
      ActiveRecord::Base.uncached do
        # can't use a find_each / batches approach here as the id isn't in the aggregate query :(
        # for now we'll just load all the reduction aggregates into memory
        # this should approximate the number of known subjects for the workflow
        # as it combines the number of reduction tasks to the unique subjects
        grouped_subject_reductions.each do |grouped_reduction|
          grouped_reductions << GroupedReduction.new(
            grouped_reduction.subject_id,
            grouped_reduction.unique_id,
            merge_reduction_labels(grouped_reduction)
          )
        end
      end
    end

    # this grouping query could get big and do a lot of object allocations
    # if it becomes a problem, switch to a raw sql query retuning the result tuples only
    # or move to a batch iterator to find the unique reduction ids for a subject
    def grouped_subject_reductions
      # TBH - this feels like it could be addressed by another data model
      # perhaps a GroupedReduction that collates all the known labels states
      # of the known set of per subject per task Reductions
      # it would be collated ahead of export time i.e. triggered by a Reduction update / creation.
      # perhaps something to look at in future if this export is becoming problematic with timing etc
      Reduction
        .where(workflow_id: workflow_id)
        .select('subject_id, unique_id, json_agg(labels) as combined_labels')
        .group(:subject_id, :unique_id)
    end

    # this is starting to look like it's own class ;)
    def merge_reduction_labels(grouped_reduction)
      {}.tap do |all_subject_labels|
        grouped_reduction.combined_labels.each { |labels| all_subject_labels.merge!(labels) }
      end
    end
  end
end
