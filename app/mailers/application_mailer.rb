class ApplicationMailer < ActionMailer::Base
  default from: "nao-responder@screwshop.dev"
  layout "mailer"

  helper :application   # // makes ApplicationHelper available in mailer views
end
