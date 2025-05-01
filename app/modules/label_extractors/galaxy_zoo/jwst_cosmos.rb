# frozen_string_literal: true

module LabelExtractors
  module GalaxyZoo
    class JwstCosmos < BaseExtractor

      # Derived to conform to the existing catalogue schema for Zoobot JwstCosmos
      # https://github.com/mwalmsley/galaxy-datasets/blob/a1a653ec7ab228036129acecb6a26b9960dbb5ff/galaxy_datasets/shared/label_metadata.py#L568
      TASK_KEY_LABEL_PREFIXES = {
        'T0' => 'smooth-or-featured',
        'T1' => 'how-rounded',
        'T2' => 'disk-edge-on',
        'T3' => 'edge-on-bulge',
        'T4' => 'bar',
        'T5' => 'has-spiral-arms',
        'T6' => 'spiral-winding',
        'T7' => 'spiral-arm-count',
        'T8' => 'bulge-size',
        'T11' => 'merging', # T10 is not used for training and no T9 in prod :shrug:
        'T12' => 'clumps',
        'T19' => 'problem',
      }.freeze
      TASK_KEY_DATA_LABELS = {
        'T0' => {
          '0' => 'smooth',
          '1' => 'featured-or-disk',
          '2' => 'star-artifact-zoom'
        },
        'T1' => {
          '0' => 'round',
          '1' => 'in-between',
          '2' => 'cigar-shaped'
        },
        'T2' => {
          '0' => 'yes',
          '1' => 'no'
        },
        'T3' => {
          '0' => 'rounded',
          '1' => 'boxy',
          '2' => 'none'
        },
        'T4' => {
          '0' => 'no',
          '1' => 'weak',
          '2' => 'strong'
        },
        'T5' => {
          '0' => 'yes',
          '1' => 'no'
        },
        'T6' => {
          '0' => 'tight',
          '1' => 'medium',
          '2' => 'loose'
        },
        'T7' => {
          '0' => '1',
          '1' => '2',
          '2' => '3',
          '3' => '4',
          '4' => 'more-than-4',
          '5' => 'cant-tell'
        },
        'T8' => {
          '0' => 'none',
          '1' => 'small',
          '2' => 'moderate',
          '3' => 'large',
          '4' => 'dominant'
        },
        'T11' => {
          '0' => 'merger',
          '1' => 'major-disturbance',
          '2' => 'minor-disturbance',
          '3' => 'none'
        },
        'T12' => {
          '0' => 'yes',
          '1' => 'no'
        },
        'T19' => {
          '0' => 'star',
          '1' => 'artifact',
          '2' => 'bad-zoom'
        }
      }.freeze

      DATA_RELEASE_SUFFIX = 'jwst'

      private
      def self.data_release_suffix
        DATA_RELEASE_SUFFIX
      end
    end
  end
end
