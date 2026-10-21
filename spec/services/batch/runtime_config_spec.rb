# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Batch::RuntimeConfig do
  it 'accepts a nested Hugging Face checkpoint path' do
    expect do
      described_class.validate!(huggingface_checkpoint_filename: 'checkpoints/best.ckpt')
    end.not_to raise_error
  end

  it 'rejects repository configuration in context batch metadata' do
    expect { described_class.validate!(huggingface_repo_id: 'zooniverse/workflow-model') }
      .to raise_error(described_class::ValidationError, /Unsupported batch runtime config keys/)
  end

end
