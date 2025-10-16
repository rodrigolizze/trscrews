class ShippingAddress < ApplicationRecord
  belongs_to :user

  before_validation :normalize_cep
  before_validation :normalize_state

  UF_CODES = %w[
    AC AL AP AM BA CE DF ES GO MA MT MS MG PA PB PR PE PI RJ RN RS RO RR SC SP SE TO
  ].freeze

  validates :recipient_name, presence: true
  validates :street, :number, :district, :city, presence: true

  CEP_REGEX = /\A\d{5}-?\d{3}\z/
  validates :cep, presence: true, format: { with: CEP_REGEX, message: "inválido (use 12345-678)" }

  validates :state, presence: true, length: { is: 2 }
  validates :state, inclusion: { in: UF_CODES, message: "inválido (use uma UF válida, ex.: SP)" }

  # // Garante único default antes de salvar (suficiente)
  before_save :ensure_single_default, if: :will_save_change_to_is_default?

  # // Ordem: padrão primeiro, depois os mais recentes
  scope :default_first, -> { order(is_default: :desc, updated_at: :desc) }

  # -- Helpers --------------------------------------------------------------
  def formatted_cep
    return "" if cep.blank?
    digits = cep.gsub(/\D/, "")
    return cep unless digits.length == 8
    "#{digits[0,5]}-#{digits[5,3]}"
  end

  def full_address
    [
      "#{street}, #{number}",
      complement.presence,
      "#{district} - #{city}/#{state}",
      "CEP #{formatted_cep}"
    ].compact.join(" | ")
  end

  private

  def normalize_cep
    return if cep.blank?
    digits = cep.gsub(/\D/, "")
    self.cep = if digits.length == 8
      "#{digits[0,5]}-#{digits[5,3]}"
    else
      cep
    end
  end

  def normalize_state
    self.state = state.to_s.strip.upcase
  end

  def ensure_single_default
    return unless is_default?
    # // zera os outros defaults deste usuário
    user.shipping_addresses.where.not(id: id).update_all(is_default: false)
  end
end
