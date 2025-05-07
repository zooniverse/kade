# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Format::TrainingDataCsv do
  describe '#run' do
    fixtures :contexts

    let(:workflow_id) { 4 }
    let(:formatter) { described_class.new(workflow_id, Zoobot.label_column_headers) }
    let(:subject_locations) do
      [
        { 'image/jpeg': 'https://panoptes-uploads.zooniverse.org/subject_location/2f2490b4-65c1-4dca-ba25-c44128aa7a39.jpeg' }
      ]
    end
    let(:reduction_subject) do
      Subject.create(zooniverse_subject_id: 1, context_id: 1, locations: subject_locations)
    end
    let(:reduction_attributes) do
      {
        subject_id: reduction_subject.id,
        zooniverse_subject_id: reduction_subject.zooniverse_subject_id,
        workflow_id: workflow_id,
        labels: {
          'smooth-or-featured-cd_smooth' => 3,
          'smooth-or-featured-cd_featured-or-disk' => 9,
          'smooth-or-featured-cd_problem' => 0
        },
        unique_id: '8000_231121_468',
        raw_payload: {},
        task_key: 'T0'
      }
    end
    let(:export_file) { formatter.run }

    before do
      Reduction.create(reduction_attributes)
    end

    it 'returns a temp file' do
      expect(formatter.run).to be_a(Tempfile)
    end

    it 'returns the csv data in the temp file' do
      expected_output = "#{Zoobot.label_column_headers.join(',')}\n8000_231121_468,/test/2f2490b4-65c1-4dca-ba25-c44128aa7a39.jpeg,3,9,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0\n"
      results = File.read(export_file.path)
      expect(results).to eq(expected_output)
    end

    context 'with multiple reductions for one subject' do
      let(:another_task_reduction_attributes) do
        {
          subject_id: reduction_subject.id,
          zooniverse_subject_id: reduction_subject.zooniverse_subject_id,
          workflow_id: workflow_id,
          labels: {
            'how-rounded-cd_round' => 1,
            'how-rounded-cd_in-between' => 5,
            'how-rounded-cd_cigar-shaped' => 3
          },
          unique_id: '8000_231121_468',
          task_key: 'T1'
        }
      end

      before do
        Reduction.create(another_task_reduction_attributes)
      end

      it 'combines the reductions results into 1 row' do
        expected_lines = [
          '8000_231121_468,/test/2f2490b4-65c1-4dca-ba25-c44128aa7a39.jpeg,3,9,0,1,5,3,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0'
        ].join("\n")
        expected_output = "#{Zoobot.label_column_headers.join(',')}\n#{expected_lines}\n"
        results = File.read(export_file.path)
        expect(results).to eq(expected_output)
      end
    end

    context 'with a multi image subject' do
      let(:subject_locations) do
        [
          { 'image/jpeg': 'https://panoptes-uploads.zooniverse.org/subject_location/2f2490b4-65c1-4dca-ba25-c44128aa7a39.jpeg' },
          { 'image/jpeg': 'https://panoptes-uploads.zooniverse.org/subject_location/fdccb1cf-0fc9-49b5-b054-62c83bccb9cd.jpeg' }
        ]
      end
      let(:expected_lines) do
        [
          '8000_231121_468,/test/2f2490b4-65c1-4dca-ba25-c44128aa7a39.jpeg,3,9,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0'
        ].join("\n")
      end

      it 'returns the multi image csv data in the temp file' do
        expected_output = "#{Zoobot.label_column_headers.join(',')}\n#{expected_lines}\n"
        results = File.read(export_file.path)
        expect(results).to eq(expected_output)
      end
    end

    context 'with no subject locations - pending backfilling' do
      let(:subject_locations) { [] }

      it 'raises an error' do
        expect {
          export_file
        }.to raise_error(Format::TrainingDataCsv::MissingLocationData, "For subject id: #{reduction_subject.id}")
      end
    end
  end
end
