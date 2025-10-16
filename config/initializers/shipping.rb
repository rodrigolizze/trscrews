# config/initializers/shipping.rb
# // Central config for shipping rules (one source of truth)

Rails.configuration.x.shipping = ActiveSupport::OrderedOptions.new

# // Free-shipping threshold
Rails.configuration.x.shipping.free_limit = 200.to_d

# // Region → fee table
Rails.configuration.x.shipping.region_fee_table = {
  sudeste:       20.to_d,
  sul:           25.to_d,
  centro_oeste:  30.to_d,
  nordeste:      35.to_d,
  norte:         40.to_d
}.freeze

# // UF → region map
Rails.configuration.x.shipping.uf_region_map = {
  "SP" => :sudeste, "RJ" => :sudeste, "MG" => :sudeste, "ES" => :sudeste,
  "PR" => :sul,     "SC" => :sul,     "RS" => :sul,
  "DF" => :centro_oeste, "GO" => :centro_oeste, "MT" => :centro_oeste, "MS" => :centro_oeste,
  "BA" => :nordeste, "SE" => :nordeste, "AL" => :nordeste, "PE" => :nordeste,
  "PB" => :nordeste, "RN" => :nordeste, "CE" => :nordeste, "PI" => :nordeste, "MA" => :nordeste,
  "PA" => :norte, "AP" => :norte, "AM" => :norte, "RR" => :norte, "RO" => :norte, "AC" => :norte, "TO" => :norte
}.freeze
