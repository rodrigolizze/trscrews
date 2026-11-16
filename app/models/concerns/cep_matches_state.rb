# The UF of an address always comes from its CEP (see BrazilianCep), never from the
# form: shipping is priced by region, and a UF typed by the customer let a Manaus
# CEP pay the Sudeste fee. The form only shows the UF read-only.
#
# Both steps run only when the address is new or its CEP/UF changes, so older
# records saved before this rule (e.g. a paid order flipped by the Stripe webhook,
# or an address being marked as default) can still be updated untouched.
module CepMatchesState
  extend ActiveSupport::Concern

  included do
    before_validation :assign_state_from_cep, if: :cep_or_state_changing?
    validate :state_must_match_cep, if: :cep_or_state_changing?
  end

  private

  def cep_or_state_changing?
    new_record? || will_save_change_to_cep? || will_save_change_to_state?
  end

  def cep_has_eight_digits?
    cep.to_s.gsub(/\D/, "").length == 8
  end

  def assign_state_from_cep
    uf = BrazilianCep.uf_for(cep) if cep_has_eight_digits?
    self.state = uf if uf
  end

  # Second lock: catches an unassigned CEP and any path that sets the UF after
  # the callback (format errors are reported by the model's own CEP validation).
  def state_must_match_cep
    return unless cep_has_eight_digits?

    expected = BrazilianCep.uf_for(cep)
    if expected.nil?
      errors.add(:base, "CEP não encontrado. Confira o número digitado.")
    elsif expected != state.to_s.upcase
      errors.add(:base, "A UF #{state.to_s.upcase} não corresponde ao CEP #{cep} (que é de #{expected}).")
    end
  end
end
