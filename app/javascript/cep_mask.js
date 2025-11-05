function formatCep(el) {
  const digits = (el.value || "").replace(/\D/g, "").slice(0, 8);
  el.value = digits.length > 5 ? `${digits.slice(0,5)}-${digits.slice(5)}` : digits;
}

function bindCepMask() {
  const el = document.querySelector('[data-cep-target="cep"]');
  if (!el || el.dataset.maskBound) return;   // prevent double-binding
  el.dataset.maskBound = "1";
  el.addEventListener("input", () => formatCep(el), { passive: true });
  formatCep(el); // format any prefilled value
}

addEventListener("turbo:load", bindCepMask);
addEventListener("turbo:frame-load", bindCepMask);
