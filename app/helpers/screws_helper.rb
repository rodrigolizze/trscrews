module ScrewsHelper
  def format_price(price)
    return "Sob consulta" if price.blank?
    number_to_currency(price, unit: "R$", separator: ",", delimiter: ".")
  end
end
