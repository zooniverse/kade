require "spec_helper"

RSpec.describe ProjectNotificationMailer, :type => :mailer do
  let(:user) { { 'email' => 'test@project@owner.com' } }
  let(:context) { Context.first }
  let(:completion_percentage) { 96 }

  describe "#notify_subject_completion" do
    let(:mail) { ProjectNotificationMailer.notify_subject_completion(user, context, completion_percentage)}
    it "mails the correct user" do
      expect(mail.to).to include(user['email'])
    end

    it 'comes from no-reply@zooniverse.org' do
      expect(mail.from).to include('no-reply@zooniverse.org')
    end

    it 'has the correct subject' do
      expect(mail.subject).to eq("Your subjects are almost retired")
    end

    it 'has the project name in the body' do
      expect(mail.body.encoded).to match("#{context.module_name}")
    end

    it 'has the workflow name in the body' do
      expect(mail.body.encoded).to match("#{context.extractor_name}")
    end

    it 'has the completion percentage in the body' do
      expect(mail.body.encoded).to match("#{completion_percentage}%")
    end
  end

  describe "#notify_prediction_change" do
  let(:mail) { ProjectNotificationMailer.notify_prediction_change(user, context, completion_percentage)}
  it "mails the correct user" do
    expect(mail.to).to include(user['email'])
  end

  it 'comes from no-reply@zooniverse.org' do
    expect(mail.from).to include('no-reply@zooniverse.org')
  end

  it 'has the correct subject' do
    expect(mail.subject).to eq("Significant change in Predictions")
  end

  it 'has the project name in the body' do
    expect(mail.body.encoded).to match("#{context.module_name}")
  end

  it 'has the workflow name in the body' do
    expect(mail.body.encoded).to match("#{context.extractor_name}")
  end

  it 'has the completion percentage in the body' do
    expect(mail.body.encoded).to match("#{completion_percentage}%")
  end
end
end
