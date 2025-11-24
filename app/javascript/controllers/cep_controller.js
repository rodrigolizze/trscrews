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
    // Debounce timer for lookup
    this._timer = null

    // --- NEW: bind mask directly on the input element ---
    this._boundMask = () => this.mask()
    if (this.hasCepTarget) {
      this.cepTarget.addEventListener("input", this._boundMask)
      // format any pre-filled value
      this.mask()
    }
  }

  disconnect() {
    // --- NEW: clean up the listener ---
    if (this.hasCepTarget && this._boundMask) {
      this.cepTarget.removeEventListener("input", this._boundMask)
    }
  }

  // // Formats the CEP input as "12345-678" while typing
  mask() {
    // // 1) Get raw value and keep only digits
    const el = this.cepTarget
    if (!el) return
    const digits = (el.value || "").replace(/\D/g, "").slice(0, 8) // // max 8

    // // 2) Build masked string: "12345-678" when >= 6 digits
    let masked = digits
    if (digits.length > 5) {
      masked = `${digits.slice(0, 5)}-${digits.slice(5)}`
    }

    // // 3) Set back to the field (no cursor gymnastics needed here)
    el.value = masked
  }

  // // Called on 'input' (debounced) — see debouncedLookup below
  lookup() {
    this.mask(); // // keep CEP formatted as 12345-678

    const raw = this.cepTarget.value || "";
    const digits = raw.replace(/\D/g, "");

    // // Clear any previous feedback while user is typing
    this._setFeedback("");

    // // Only call ViaCEP when CEP has exactly 8 digits
    if (digits.length !== 8) return;

    // // Show a small "loading" message to user
    this._setFeedback("Consultando CEP...");

    // // ✅ Call ViaCEP directly from the browser using HTTPS
    // // This bypasses Heroku's network and avoids the 503 you saw.
    fetch(`https://viacep.com.br/ws/${digits}/json/`)
      .then((res) => res.json())
      .then((data) => {
        // // ViaCEP returns { erro: true } when CEP is not found
        if (data.erro) {
          throw new Error("CEP não encontrado");
        }

        // // Fill the fields with the data from ViaCEP
        this._fillIfPresent(this.streetTarget,   data.logradouro);
        this._fillIfPresent(this.districtTarget, data.bairro);
        this._fillIfPresent(this.cityTarget,     data.localidade);
        this._fillIfPresent(this.stateTarget,    data.uf);

        // // Normalize CEP in the input if API returns it (e.g. 01311-000)
        if (data.cep && this.cepTarget) {
          this.cepTarget.value = data.cep;
        }

        this._setFeedback("Endereço preenchido pelo CEP.", "success");
      })
      .catch((err) => {
        // // Any error (network, CEP not found, etc.) shows a friendly message
        this._setFeedback(err.message || "Falha na consulta do CEP.", "danger");
      });
  }

  // // Debounced wrapper to avoid firing on every keystroke (hook this to 'input' event)
  debouncedLookup() {
    this.mask();

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
