import { Controller } from "@hotwired/stimulus"

// data-controller="navbar"
//
// Abaixo de lg o menu abre sobreposto (position:absolute, em _navbar.scss). O
// collapse do Bootstrap não fecha ao tocar fora — só o dropdown faz isso — e num
// painel flutuante é justamente esse o instinto do usuário.
export default class extends Controller {
  static targets = ["menu"]

  connect() {
    // Guardado na instância para poder remover no disconnect. Sem o par
    // connect/disconnect o listener sobreviveria à troca de body do Turbo e
    // acumularia uma cópia por visita.
    this.boundClose = (event) => this.closeOnOutsideClick(event)
    document.addEventListener("click", this.boundClose)
  }

  disconnect() {
    document.removeEventListener("click", this.boundClose)
  }

  closeOnOutsideClick(event) {
    if (!this.hasMenuTarget) return

    const menu = this.menuTarget
    if (!menu.classList.contains("show")) return

    const target = event.target
    if (!(target instanceof Element)) return
    if (menu.contains(target)) return

    // O próprio botão já alterna pelo data-api do Bootstrap; fechar aqui também
    // duplicaria a ação no meio da transição de 350ms.
    if (target.closest(".navbar-toggler")) return

    // hide() e não classList.remove("show"): mexer na classe na mão deixa o
    // estado interno do Collapse dessincronizado e o toque seguinte no botão não
    // reabre. O toggle:false evita que getOrCreateInstance alterne ao construir —
    // o construtor do Collapse tem toggle:true por padrão.
    window.bootstrap?.Collapse.getOrCreateInstance(menu, { toggle: false }).hide()
  }
}
