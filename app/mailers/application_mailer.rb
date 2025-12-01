class ApplicationMailer < ActionMailer::Base
  default from: "trautoparts.suporte@gmail.com"
  layout "mailer"

  # 👇 Isso faz os helpers de ApplicationHelper (incluindo format_price)
  # ficarem disponíveis em TODOS os templates de e-mail
  helper :application
end
