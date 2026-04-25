# frozen_string_literal: true

require 'rails_helper'

RSpec.describe NotifyProjectOwnerJob, type: :job do
  describe 'perform' do
    let(:context) { Context.first }
    let(:job) { described_class.new }
    let(:panoptes_client_double) { instance_double(Panoptes::Client) }
    let(:fake_owner_id)   { 1 }
    let(:fake_user_hash)  { { "id" => fake_owner_id, "email" => "foo@example.com", "display_name" => "Foo Bar" } }
    let(:fake_project_hash)  { { "links" => { "owner" => { "id" => fake_owner_id } } } }
    let(:completion_rate) { 0.9 }

    let(:mailer_double) { instance_double("ActionMailer::MessageDelivery", deliver_now: true) }
    before do
      allow(ENV).to receive(:fetch).with('PANOPTES_OAUTH_CLIENT_ID').and_return('fake-client-id')
      allow(ENV).to receive(:fetch).with('PANOPTES_OAUTH_CLIENT_SECRET').and_return('fake-client-sekreto')
      allow(panoptes_client_double).to receive(:project).and_return(fake_project_hash)
      allow(panoptes_client_double).to receive(:user).and_return(fake_user_hash)
      allow(Panoptes::Client).to receive(:new).and_return(panoptes_client_double)
    end

    context 'subject_completion' do
      before do
        allow(ProjectNotificationMailer)
        .to receive(:notify_subject_completion)
        .and_return(mailer_double)
        job.perform(context.active_subject_set_id, completion_rate)
      end
      it 'calls the api client to fetch project details' do
        expect(panoptes_client_double).to have_received(:project).with(context.project_id)
      end

      it 'calls the api client to fetch user details' do
        expect(panoptes_client_double).to have_received(:user).with(fake_owner_id)
      end

      it 'calls ProjectNotificationMailer notify_subject_completion' do
        expect(ProjectNotificationMailer).to have_received(:notify_subject_completion).with(fake_user_hash, context, (completion_rate * 100))
      end

      it 'attempts to deliver the mail' do
        expect(mailer_double).to have_received(:deliver_now)
      end

    end

    context 'model_result_change' do
      before do
        allow(ProjectNotificationMailer)
        .to receive(:notify_prediction_change)
        .and_return(mailer_double)
        job.perform(context.active_subject_set_id, completion_rate, 'model_result_change')
      end
      it 'calls the api client to fetch project details' do
        expect(panoptes_client_double).to have_received(:project).with(context.project_id)
      end

      it 'calls the api client to fetch user details' do
        expect(panoptes_client_double).to have_received(:user).with(fake_owner_id)
      end

      it 'calls ProjectNotificationMailer notify_prediction_change' do
        expect(ProjectNotificationMailer).to have_received(:notify_prediction_change).with(fake_user_hash, context, (completion_rate * 100))
      end

      it 'attempts to deliver the mail' do
        expect(mailer_double).to have_received(:deliver_now)
      end
    end
  end
end
