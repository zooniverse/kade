# frozen_string_literal: true

require 'uri'

module Batch
  class RuntimeConfig
    class ValidationError < StandardError; end

    SCRIPT_PATH_KEYS = %w[
      training_script_path
      prediction_script_path
      promote_script_path
    ].freeze
    ALLOWED_KEYS = (
      SCRIPT_PATH_KEYS + %w[
        container_image_name
        fixed_crop
        n_blocks
        pretrained_checkpoint_url
      ]
    ).freeze
    FIXED_CROP_KEYS = %w[
      lower_left_x
      lower_left_y
      upper_right_x
      upper_right_y
    ].freeze

    def self.validate!(config)
      new(config).validate!
    end

    def initialize(config)
      @config = config.to_h.transform_keys(&:to_s)
    end

    def validate!
      validate_keys!
      validate_container_image_name!(@config['container_image_name']) if @config.key?('container_image_name')
      validate_script_paths!
      validate_pretrained_checkpoint_url!(@config['pretrained_checkpoint_url']) if @config.key?('pretrained_checkpoint_url')
      validate_n_blocks!(@config['n_blocks']) if @config.key?('n_blocks')
      validate_fixed_crop!(@config['fixed_crop']) if @config.key?('fixed_crop')
    end

    private

    def validate_keys!
      unsupported_keys = @config.keys - ALLOWED_KEYS
      return if unsupported_keys.empty?

      raise ValidationError, "Unsupported batch runtime config keys: #{unsupported_keys.join(', ')}"
    end

    def validate_container_image_name!(value)
      validate_non_blank_string!(value, 'container_image_name')
      raise ValidationError, 'container_image_name must not contain whitespace' if value.match?(/\s/)
    end

    def validate_script_paths!
      SCRIPT_PATH_KEYS.each do |key|
        next unless @config.key?(key)

        value = @config[key]
        validate_relative_path!(value, key)
        expected_extension = key == 'promote_script_path' ? '.sh' : '.py'
        raise ValidationError, "#{key} must end with #{expected_extension}" unless value.end_with?(expected_extension)
      end
    end

    def validate_pretrained_checkpoint_url!(value)
      validate_non_blank_string!(value, 'pretrained_checkpoint_url')

      if value.match?(%r{\Ahttps?://})
        uri = URI.parse(value)
        unless uri.is_a?(URI::HTTP) && uri.host.present? && uri.path.present? && uri.path != '/'
          raise ValidationError, 'pretrained_checkpoint_url must be an HTTP(S) URL or relative checkpoint path'
        end

        validate_no_parent_path_segments!(uri.path.split('/'), 'pretrained_checkpoint_url')
      elsif value.match?(%r{\A[A-Za-z][A-Za-z0-9+\-.]*://})
        raise ValidationError, 'pretrained_checkpoint_url must be an HTTP(S) URL or relative checkpoint path'
      else
        validate_relative_path!(value, 'pretrained_checkpoint_url')
      end
    rescue URI::InvalidURIError
      raise ValidationError, 'pretrained_checkpoint_url must be an HTTP(S) URL or relative checkpoint path'
    end

    def validate_n_blocks!(value)
      return if value.is_a?(Integer) && value.positive?

      raise ValidationError, 'n_blocks must be a positive integer'
    end

    def validate_fixed_crop!(value)
      raise ValidationError, 'fixed_crop must be an object' unless value.respond_to?(:to_h)

      fixed_crop = value.to_h.transform_keys(&:to_s)
      missing_keys = FIXED_CROP_KEYS - fixed_crop.keys
      unsupported_keys = fixed_crop.keys - FIXED_CROP_KEYS

      raise ValidationError, "fixed_crop is missing required keys: #{missing_keys.join(', ')}" if missing_keys.any?
      raise ValidationError, "fixed_crop has unsupported keys: #{unsupported_keys.join(', ')}" if unsupported_keys.any?

      FIXED_CROP_KEYS.each do |key|
        raise ValidationError, "fixed_crop.#{key} must be numeric" unless fixed_crop[key].is_a?(Numeric)
      end
    end

    def validate_relative_path!(value, key)
      validate_non_blank_string!(value, key)
      raise ValidationError, "#{key} must be a relative path" if value.start_with?('/')
      raise ValidationError, "#{key} must not contain whitespace" if value.match?(/\s/)
      raise ValidationError, "#{key} must use forward slashes" if value.include?('\\')

      validate_no_parent_path_segments!(value.split('/'), key)
    end

    def validate_no_parent_path_segments!(segments, key)
      raise ValidationError, "#{key} must not include parent directory traversal" if segments.include?('..')
    end

    def validate_non_blank_string!(value, key)
      raise ValidationError, "#{key} must be a string" unless value.is_a?(String)
      raise ValidationError, "#{key} must not be blank" if value.blank?
    end
  end
end
