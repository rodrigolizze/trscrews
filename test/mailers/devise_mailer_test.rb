require "test_helper"

# The account e-mails used to be Devise's English defaults ("Someone has requested
# a link..."), which read like phishing next to a Portuguese subject and landed in
# spam. They are now in pt-BR and multipart (HTML + plain text).
class DeviseMailerTest < ActionMailer::TestCase
  test "reset password e-mail is in Portuguese with HTML and text parts" do
    mail = Devise::Mailer.reset_password_instructions(users(:one), "abc123")

    assert_equal "Redefina sua senha na TR AutoFix", mail.subject
    assert mail.multipart?, "esperava versão HTML e texto"
    assert_match "Criar nova senha", mail.html_part.body.to_s
    assert_match "reset_password_token=abc123", mail.text_part.body.to_s
    assert_no_match(/Someone has requested/, mail.body.encoded)
  end

  test "password change notice is in Portuguese" do
    mail = Devise::Mailer.password_change(users(:one))
    assert_match "acabou de ser alterada", mail.html_part.body.to_s
  end

  test "account e-mails come from TR AutoFix" do
    mail = Devise::Mailer.reset_password_instructions(users(:one), "abc123")
    assert_equal "TR AutoFix", mail[:from].display_names.first
  end

  test "order e-mails come from TR AutoFix" do
    assert_match(/\ATR AutoFix </, ApplicationMailer.default[:from])
  end
end
