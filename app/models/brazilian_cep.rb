# Maps a CEP to its state (UF) using the Correios CEP ranges.
#
# Shipping is priced by region, so the UF must come from the CEP itself: trusting
# the UF field from the checkout form let a customer type a Manaus CEP, pick "SP"
# and pay the Sudeste fee. Static ranges keep the check offline and instant (no
# ViaCEP call at checkout); they only change when Correios renumbers a state.
module BrazilianCep
  # [first CEP, last CEP, UF] as 8-digit integers. A few states span two ranges.
  RANGES = [
    [ 1_000_000, 19_999_999, "SP"],
    [20_000_000, 28_999_999, "RJ"],
    [29_000_000, 29_999_999, "ES"],
    [30_000_000, 39_999_999, "MG"],
    [40_000_000, 48_999_999, "BA"],
    [49_000_000, 49_999_999, "SE"],
    [50_000_000, 56_999_999, "PE"],
    [57_000_000, 57_999_999, "AL"],
    [58_000_000, 58_999_999, "PB"],
    [59_000_000, 59_999_999, "RN"],
    [60_000_000, 63_999_999, "CE"],
    [64_000_000, 64_999_999, "PI"],
    [65_000_000, 65_999_999, "MA"],
    [66_000_000, 68_899_999, "PA"],
    [68_900_000, 68_999_999, "AP"],
    [69_000_000, 69_299_999, "AM"],
    [69_300_000, 69_399_999, "RR"],
    [69_400_000, 69_899_999, "AM"],
    [69_900_000, 69_999_999, "AC"],
    [70_000_000, 72_799_999, "DF"],
    [72_800_000, 72_999_999, "GO"],
    [73_000_000, 73_699_999, "DF"],
    [73_700_000, 76_799_999, "GO"],
    [76_800_000, 76_999_999, "RO"],
    [77_000_000, 77_999_999, "TO"],
    [78_000_000, 78_899_999, "MT"],
    [78_900_000, 78_999_999, "RO"],
    [79_000_000, 79_999_999, "MS"],
    [80_000_000, 87_999_999, "PR"],
    [88_000_000, 89_999_999, "SC"],
    [90_000_000, 99_999_999, "RS"]
  ].freeze

  # Returns the UF ("SP", "AM"...) or nil when the CEP is malformed or unassigned.
  def self.uf_for(cep)
    digits = cep.to_s.gsub(/\D/, "")
    return nil unless digits.length == 8

    number = digits.to_i
    RANGES.find { |first, last, _| number.between?(first, last) }&.last
  end

  # "69005010" -> "69005-010"; nil when it is not 8 digits.
  def self.format(cep)
    digits = cep.to_s.gsub(/\D/, "")
    return nil unless digits.length == 8
    "#{digits[0, 5]}-#{digits[5, 3]}"
  end
end
