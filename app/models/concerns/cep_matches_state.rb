# Rejects an address whose UF does not belong to its CEP (see BrazilianCep).
#
# Only runs when the address is new or its CEP/UF changes, so older records saved
# before this check (e.g. a paid order flipped by the Stripe webhook, or an address
# being marked as default) can still be updated.
module CepMatchesState
  extend ActiveSupport::Concern

  included do
    validate :state_must_match_cep,
             if: -> { new_record? || will_save_change_to_cep? || will_save_change_to_state? }
  end

  private

  def state_must_match_cep
    # Format errors are reported by the model's own CEP validation.
    return unless cep.to_s.gsub(/\D/, "").length == 8 && state.present?

    expected = BrazilianCep.uf_for(cep)
    if expected.nil?
      errors.add(:base, "CEP não encontrado. Confira o número digitado.")
    elsif expected != state.to_s.upcase
      errors.add(:base, "A UF #{state.to_s.upcase} não corresponde ao CEP #{cep} (que é de #{expected}).")
    end
  end
end
