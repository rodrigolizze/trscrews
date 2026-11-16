# Company identification shown in the footer and in the policy pages.
#
# Decreto 7.962/2013 (art. 2º) requires an online store to show its legal name,
# CNPJ, physical address and e-mail. The values live in ENV so they can be filled
# on Heroku at go-live without a deploy. A blank value hides its line: placeholder
# data must never show up on the live site.
Rails.configuration.x.company = ActiveSupport::OrderedOptions.new.tap do |company|
  company.trade_name = ENV.fetch("COMPANY_TRADE_NAME", "TR AutoFix")
  company.legal_name = ENV["COMPANY_LEGAL_NAME"].presence
  company.cnpj       = ENV["COMPANY_CNPJ"].presence
  company.address    = ENV["COMPANY_ADDRESS"].presence
  company.email      = ENV["COMPANY_EMAIL"].presence
  company.whatsapp   = ENV["COMPANY_WHATSAPP"].presence
  company.hours      = ENV.fetch("COMPANY_HOURS", "segunda a sexta, das 9h às 18h")
  # Shown as "Última atualização" on the policy pages; bump it when the text changes.
  company.policies_updated_on = Date.parse(ENV.fetch("POLICIES_UPDATED_ON", "2026-11-16"))
end
