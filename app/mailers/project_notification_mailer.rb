class ProjectNotificationMailer < ApplicationMailer
    layout false

    def notify_subject_completion(user, context, completion_percentage)
      @completion_percentage = completion_percentage
      @project_name = context.module_name
      @workflow_name = context.extractor_name
      @email_to = user['email']
      mail(to: @email_to, subject: "Your subjects are almost retired")
    end
  end
