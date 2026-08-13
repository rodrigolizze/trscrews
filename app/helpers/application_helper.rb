module ApplicationHelper
  include ActionView::Helpers::NumberHelper

  # Gives views the pagy_*_nav helpers. ApplicationController includes Pagy::Backend
  # for the controller side; without this counterpart the catalog raises NoMethodError
  # as soon as the result set spans more than one page. Dropped by accident in ae52c30.
  include Pagy::Frontend

  # // Format money as BRL (R$ 1.234,56)
  def format_price(value)
    number_to_currency(value.to_d,
      unit: "R$ ",
      separator: ",",
      delimiter: ".",
      precision: 2
    )
  end

  # // Prefer user's name; fallback to email; final fallback to "Minha conta"
  def user_display_name(user)
    user&.name.presence || user&.email.presence || "Minha conta"
  end
  
end
