# Preview at http://localhost:3000/rails/mailers/devise_mailer (development only).
# Account e-mails for the first local user; the tokens are fake.
class DeviseMailerPreview < ActionMailer::Preview
  def confirmation_instructions
    Devise::Mailer.confirmation_instructions(user, "token-de-exemplo")
  end

  def reset_password_instructions
    Devise::Mailer.reset_password_instructions(user, "token-de-exemplo")
  end

  def password_change
    Devise::Mailer.password_change(user)
  end

  def email_changed
    Devise::Mailer.email_changed(user)
  end

  def unlock_instructions
    Devise::Mailer.unlock_instructions(user, "token-de-exemplo")
  end

  private

  def user
    User.order(:id).first
  end
end
