require "test_helper"

# The payment confirmation is the e-mail every buyer gets. It used to be plain
# HTML only (no text part, which hurts spam scoring), without the brand and with
# no way back to the order.
class OrderMailerTest < ActionMailer::TestCase
  setup { @order = orders(:one) }

  test "payment confirmation has HTML and plain-text parts" do
    mail = OrderMailer.payment_confirmed(@order)

    assert mail.multipart?, "esperava versão HTML e texto"
    assert_equal [@order.customer_email], mail.to
    assert_match "Pagamento confirmado", mail.subject
  end

  test "payment confirmation links back to the customer's orders" do
    mail = OrderMailer.payment_confirmed(@order)
    url = Rails.application.routes.url_helpers.my_orders_url(**ActionMailer::Base.default_url_options)

    assert_match "Ver meus pedidos", mail.html_part.body.to_s
    assert_includes mail.html_part.body.to_s, url
    assert_includes mail.text_part.body.to_s, url
  end

  test "payment confirmation lists the items, the total and the posting time" do
    body = OrderMailer.payment_confirmed(@order).text_part.body.to_s

    @order.order_items.each { |item| assert_includes body, item.screw.description }
    assert_includes body, "Total:"
    assert_includes body, "1 dia útil"
  end

  test "order and account e-mails share the branded frame" do
    order_html = OrderMailer.payment_confirmed(@order).html_part.body.to_s
    account_html = Devise::Mailer.reset_password_instructions(users(:one), "abc123").html_part.body.to_s

    [order_html, account_html].each do |html|
      assert_match(/logo-tr-autofix-nav[^"]*\.png/, html)
      assert_includes html, "#FFC400"
      assert_includes html, "Equipe TR AutoFix"
    end
  end
end
