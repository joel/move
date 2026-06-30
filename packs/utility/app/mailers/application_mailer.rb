# frozen_string_literal: true

class ApplicationMailer < ActionMailer::Base
  default from: ENV.fetch("NOTIF_MAIL_FROM", "no-reply@example.com")
  layout "mailer"
end
