import { Controller } from "@hotwired/stimulus"

// Submits its <form> as soon as it appears. Used on the thank_you page right
// after "Finalizar pedido" (pay=1) to go straight to the Stripe payment page
// with the existing button — the button stays visible as a fallback.
export default class extends Controller {
  connect() {
    if (this.element.dataset.autoSubmitted) return
    this.element.dataset.autoSubmitted = "1"
    // Small delay so the "redirecting" message paints first.
    this.timer = setTimeout(() => this.element.requestSubmit(), 400)
  }

  disconnect() {
    clearTimeout(this.timer)
  }
}
