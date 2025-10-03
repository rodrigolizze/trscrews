// app/javascript/controllers/cep_controller.js
// // Stimulus controller to auto-fill address fields using ViaCEP through our /cep/:cep endpoint
// // How it will be used (next step we'll wire it in the form):
// // <div data-controller="cep">
// //   <input data-cep-target="cep" data-action="blur->cep#lookup input->cep#debouncedLookup">
// //   <input data-cep-target="street">
// //   <input data-cep-target="district">
// //   <input data-cep-target="city">
// //   <input data-cep-target="state">
// //   <div data-cep-target="feedback"></div>
// // </div>
//
// // Notes:
// // - We sanitize CEP to digits only and require 8 digits before calling the server.
// // - If the API returns an error, we show a friendly message in the feedback area.
// // - You can choose to only fill empty fields or always overwrite (we overwrite for simplicity).
//
// // This controller depends on Stimulus being set up (you already have controllers working).
// // It uses the Rails route we added: GET /cep/:cep (defaults to JSON).
//
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["cep", "street", "district", "city", "state", "feedback"]

  connect() {
    // // Small debounce timer used by debouncedLookup
    this._timer = null
  }

  // // Called on 'input' (debounced) — see debouncedLookup below
  lookup() {
    const raw = this.cepTarget.value || ""
    const digits = raw.replace(/\D/g, "")

    // // Clear messages if user is typing
    this._setFeedback("")

    // // Only call when we have exactly 8 digits
    if (digits.length !== 8) return

    // // Show a small loading hint
    this._setFeedback("Consultando CEP...")

    fetch(`/cep/${digits}`, {
      headers: { "Accept": "application/json" },
      credentials: "same-origin"
    })
      .then(async (res) => {
        const data = await res.json().catch(() => ({}))

        if (!res.ok) {
          // // Handle known error messages coming from our controller
          const msg = data && data.error ? data.error : "Não foi possível consultar o CEP."
          throw new Error(msg)
        }

        // // Fill the fields (overwrite for consistency; change if you prefer "only if empty")
        this._fillIfPresent(this.streetTarget,   data.street)
        this._fillIfPresent(this.districtTarget, data.district)
        this._fillIfPresent(this.cityTarget,     data.city)
        this._fillIfPresent(this.stateTarget,    data.state)

        // // Normalize CEP field with mask if server returned it (e.g., "01311-000")
        if (data.cep && this.cepTarget) {
          this.cepTarget.value = data.cep
        }

        this._setFeedback("Endereço preenchido pelo CEP.", "success")
      })
      .catch((err) => {
        // // Show a friendly message (e.g., "CEP não encontrado" or timeout)
        this._setFeedback(err.message || "Falha na consulta do CEP.", "danger")
      })
  }

  // // Debounced wrapper to avoid firing on every keystroke (hook this to 'input' event)
  debouncedLookup() {
    clearTimeout(this._timer)
    this._timer = setTimeout(() => this.lookup(), 350) // // 350ms debounce
  }

  // // Helpers
  _fillIfPresent(el, value) {
    if (!el) return
    el.value = value || ""
    // // Trigger input event so any Rails/Turbo validations or masks can react
    el.dispatchEvent(new Event("input", { bubbles: true }))
  }

  _setFeedback(message, kind = "") {
    if (!this.hasFeedbackTarget) return
    // // You can style this with Bootstrap by using text-* classes
    const base = "small mt-1"
    const color =
      kind === "success" ? "text-success"
      : kind === "danger" ? "text-danger"
      : "text-muted"
    this.feedbackTarget.className = `${base} ${color}`
    this.feedbackTarget.textContent = message || ""
  }
}
