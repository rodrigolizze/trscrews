import { Controller } from "@hotwired/stimulus"

// Quantidade no carrinho sem botão "Atualizar": os botões − / + e a digitação
// direta enviam o mesmo formulário PATCH set_cart de antes, sozinhos.
// A digitação espera uma pausa curta (debounce) para não enviar a cada tecla.
//
// data-controller="cart-qty"
//   input:   data-cart-qty-target="input"
//   botões:  data-action="cart-qty#decrement" / "cart-qty#increment"
export default class extends Controller {
  static targets = ["input"]
  static values = { delay: { type: Number, default: 600 } }

  disconnect() {
    clearTimeout(this.timer)
  }

  decrement() {
    // Mínimo 1 pelos botões: remover o item é ação explícita ("Remover").
    this.step(-1)
  }

  increment() {
    this.step(1)
  }

  changed() {
    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.submit(), this.delayValue)
  }

  step(delta) {
    const current = parseInt(this.inputTarget.value, 10) || 1
    const max = parseInt(this.inputTarget.max, 10)
    let next = Math.max(1, current + delta)
    if (!Number.isNaN(max) && max > 0) next = Math.min(next, max)
    if (next === current) return
    this.inputTarget.value = next
    this.changed()
  }

  submit() {
    if (this.element.dataset.submitting) return
    this.element.dataset.submitting = "1"
    this.element.requestSubmit()
  }
}
