import { Controller } from "@hotwired/stimulus"

// data-controller="gallery"
export default class extends Controller {
  static targets = ["main", "thumb"]

  connect() {
    // mark the first thumb as active
    if (this.thumbTargets.length) this._activate(this.thumbTargets[0])
  }

  swap(e) {
    e.preventDefault()
    const el = e.currentTarget
    const url = el.dataset.url
    if (!url) return

    this.mainTarget.src = url
    this._activate(el)
  }

  _activate(activeEl) {
    this.thumbTargets.forEach(t => t.classList.remove("border-primary", "opacity-100"))
    activeEl.classList.add("border-primary", "opacity-100")
  }
}
