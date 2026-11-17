// Admin product form: live 3D preview of the shape fields. Starts from the
// guessed shape (Screw#viewer_spec(use_overrides: false)) and applies the head,
// seat and wrench fields on top, rewriting the viewer's spec value so
// screw_viewer_controller rebuilds the model. Thread and length update on save.
import { Controller } from "@hotwired/stimulus";

// Heads whose seat is always flat (same rule as Screw#guessed_seat_type).
const FLAT_SEAT_HEADS = ["drain_plug", "torx_countersunk", "torx", "allen", "phillips_pan", "hex_flange"];

export default class extends Controller {
  static targets = ["head", "seat", "wrench", "viewer"];
  static values = { base: Object };

  connect() {
    this.update();
  }

  update() {
    const base = this.baseValue;
    const head = this.headTarget.value || base.head;
    let seat = this.seatTarget.value;
    if (!seat) seat = this.headTarget.value && FLAT_SEAT_HEADS.includes(head) ? "flat" : base.seat;
    const wrench = parseInt(this.wrenchTarget.value, 10) || base.wrench;

    const spec = { ...base, head, seat, wrench };
    this.viewerTarget.setAttribute("data-screw-viewer-spec-value", JSON.stringify(spec));
  }
}
