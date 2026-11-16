module CompanyHelper
  def company
    Rails.configuration.x.company
  end

  # wa.me needs the number with country code and digits only.
  def whatsapp_url(number)
    digits = number.to_s.gsub(/\D/, "")
    digits = "55#{digits}" unless digits.start_with?("55") && digits.length >= 12
    "https://wa.me/#{digits}"
  end

  # Links to the support channels that are configured (e-mail, WhatsApp).
  def company_contact_links
    links = []
    links << mail_to(company.email) if company.email
    links << link_to("WhatsApp #{company.whatsapp}", whatsapp_url(company.whatsapp),
                     target: "_blank", rel: "noopener") if company.whatsapp
    links
  end

  # "pelo e-mail x ou WhatsApp y", or a neutral fallback while none is configured.
  def company_contact_sentence
    links = company_contact_links
    return "pelos canais informados no rodapé do site" if links.empty?

    safe_join(["por "] + links.each_with_index.flat_map { |l, i| i.zero? ? [l] : [" ou ", l] })
  end

  # "Razão Social, CNPJ 00.000.000/0001-00" with only the parts that are configured.
  def company_identification
    [company.legal_name || company.trade_name,
     ("CNPJ #{company.cnpj}" if company.cnpj)].compact.join(", ")
  end
end
