// "Ver em 3D" on the product page: draws this product's screw from its specs
// (Screw#viewer_spec) with three.js. Nothing 3D loads until the button is
// pressed; the scene pauses offscreen and is disposed when the page changes.
//
// Drag rotates (horizontal drag only, so vertical swipes still scroll the page on
// phones). Without reduced motion it also turns slowly on its own.
import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["stage", "photo", "toggle", "label"];
  // autoOpen: show the 3D right away (admin preview) instead of waiting for the button.
  static values = { spec: Object, logo: String, autoOpen: Boolean };

  connect() {
    this.open = false;
    this.reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    if (this.autoOpenValue) this.show();
  }

  // The admin preview rewrites data-screw-viewer-spec-value when a shape field
  // changes: rebuild the model in the running scene.
  specValueChanged() {
    if (this.renderer) this.mountScrew();
  }

  disconnect() {
    this.teardown();
  }

  async toggle(event) {
    event?.preventDefault();
    this.open ? this.close() : await this.show();
  }

  async show() {
    this.open = true;
    this.stageTarget.hidden = false;
    if (this.hasPhotoTarget) this.photoTarget.hidden = true;
    if (this.hasToggleTarget) this.toggleTarget.setAttribute("aria-pressed", "true");
    if (this.hasLabelTarget) this.labelTarget.textContent = "Ver fotos";

    if (!this.renderer) {
      try {
        await this.start();
      } catch (error) {
        console.error("[screw-viewer]", error);
        this.stageTarget.textContent = "Não foi possível carregar o 3D neste navegador.";
        return;
      }
    }
    this.running = true;
    this.loop();
  }

  close() {
    this.open = false;
    this.running = false;
    this.stageTarget.hidden = true;
    if (this.hasPhotoTarget) this.photoTarget.hidden = false;
    if (this.hasToggleTarget) this.toggleTarget.setAttribute("aria-pressed", "false");
    if (this.hasLabelTarget) this.labelTarget.textContent = "Ver em 3D";
  }

  async start() {
    const THREE = await import("three");
    const { buildScrew } = await import("controllers/screw_geometry");
    this.buildScrew = buildScrew;
    // The head mark is drawn on a canvas: load the TR logo (and the font used for
    // the property class) first. Without the logo it falls back to "TR" letters.
    await document.fonts?.load("100px Anton").catch(() => {});
    this.logo = await this.loadImage(this.logoValue);
    this.THREE = THREE;

    const stage = this.stageTarget;
    const width = stage.clientWidth || 400;
    const height = stage.clientHeight || width;

    const renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true });
    renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
    renderer.setSize(width, height);
    renderer.toneMapping = THREE.ACESFilmicToneMapping;
    renderer.outputColorSpace = THREE.SRGBColorSpace;
    stage.appendChild(renderer.domElement);
    this.renderer = renderer;

    const scene = new THREE.Scene();
    const envMap = this.environment(THREE, renderer);
    scene.add(new THREE.AmbientLight(0xffffff, 0.35));
    const key = new THREE.DirectionalLight(0xffffff, 1.4);
    key.position.set(30, 50, 40);
    scene.add(key);

    const pivot = new THREE.Group();
    pivot.rotation.x = -0.35;
    scene.add(pivot);
    const camera = new THREE.PerspectiveCamera(30, width / height, 1, 2000);

    Object.assign(this, { scene, camera, pivot, envMap });
    this.mountScrew();
    this.bindDrag();
    this.observe();
  }

  // (Re)builds the screw from specValue: lays it down (head on the right),
  // centres it and fits the camera to its size.
  mountScrew() {
    const THREE = this.THREE;
    if (this.screw) {
      this.pivot.remove(this.screw);
      this.disposeObject(this.screw);
    }
    const screw = this.buildScrew(this.specValue, this.envMap, { logo: this.logo });
    screw.rotation.z = -Math.PI / 2;
    // Measure BEFORE attaching to the pivot: once the pivot has turned (a rebuild
    // in the admin preview), a world-space box is off-centre and the screw would
    // orbit around the axis instead of spinning on it.
    screw.updateMatrixWorld(true);
    const box = new THREE.Box3().setFromObject(screw);
    screw.position.sub(box.getCenter(new THREE.Vector3()));
    this.pivot.add(screw);
    this.screw = screw;

    const size = box.getSize(new THREE.Vector3());
    const aspect = this.camera.aspect;
    const fit = Math.max(size.x, size.y / aspect);
    this.camera.position.set(0, 0, (fit / 2 / Math.tan((this.camera.fov * Math.PI) / 360)) * 1.35);
    this.camera.lookAt(0, 0, 0);
    this.renderer.render(this.scene, this.camera);
  }

  disposeObject(root) {
    root.traverse((obj) => {
      obj.geometry?.dispose();
      const materials = Array.isArray(obj.material) ? obj.material : [obj.material];
      materials.forEach((m) => { m?.map?.dispose(); m?.dispose(); });
    });
  }

  loadImage(url) {
    if (!url) return Promise.resolve(null);
    return new Promise((resolve) => {
      const img = new Image();
      img.onload = () => resolve(img);
      img.onerror = () => resolve(null);
      img.src = url;
    });
  }

  // Studio environment reflected by the metal: dark room with two softbox
  // stripes and a mid-grey floor. The contrast is what makes chrome read as a
  // mirror; matte finishes (high roughness) just blur it into a soft gradient.
  environment(THREE, renderer) {
    const pmrem = new THREE.PMREMGenerator(renderer);
    const canvas = document.createElement("canvas");
    canvas.width = 512;
    canvas.height = 256;
    const ctx = canvas.getContext("2d");
    const base = ctx.createLinearGradient(0, 0, 0, 256);
    base.addColorStop(0, "#16171a");
    base.addColorStop(0.5, "#2e3034");
    base.addColorStop(0.6, "#6d7075");
    base.addColorStop(1, "#26282b");
    ctx.fillStyle = base;
    ctx.fillRect(0, 0, 512, 256);
    // Softboxes: a wide band above the horizon and a narrow one higher up.
    const band = (y, h, alpha) => {
      const g = ctx.createLinearGradient(0, y, 0, y + h);
      g.addColorStop(0, "rgba(255,255,255,0)");
      g.addColorStop(0.5, `rgba(255,255,255,${alpha})`);
      g.addColorStop(1, "rgba(255,255,255,0)");
      ctx.fillStyle = g;
      ctx.fillRect(0, y, 512, h);
    };
    band(84, 30, 1);
    band(36, 10, 0.9);
    const texture = new THREE.CanvasTexture(canvas);
    texture.mapping = THREE.EquirectangularReflectionMapping;
    const envMap = pmrem.fromEquirectangular(texture).texture;
    texture.dispose();
    pmrem.dispose();
    return envMap;
  }

  bindDrag() {
    const el = this.renderer.domElement;
    el.style.touchAction = "pan-y";
    el.style.cursor = "grab";
    let lastX = null;
    this.onDown = (e) => { lastX = e.clientX; this.dragging = true; el.setPointerCapture?.(e.pointerId); el.style.cursor = "grabbing"; };
    this.onMove = (e) => {
      if (!this.dragging || lastX === null) return;
      this.pivot.rotation.y += (e.clientX - lastX) * 0.01;
      lastX = e.clientX;
    };
    this.onUp = () => { this.dragging = false; lastX = null; el.style.cursor = "grab"; };
    el.addEventListener("pointerdown", this.onDown);
    el.addEventListener("pointermove", this.onMove);
    el.addEventListener("pointerup", this.onUp);
    el.addEventListener("pointercancel", this.onUp);
  }

  observe() {
    this.resizeObserver = new ResizeObserver(() => {
      const w = this.stageTarget.clientWidth, h = this.stageTarget.clientHeight;
      if (!w || !h) return;
      this.renderer.setSize(w, h);
      this.camera.aspect = w / h;
      this.camera.updateProjectionMatrix();
    });
    this.resizeObserver.observe(this.stageTarget);
    this.visibility = new IntersectionObserver(([entry]) => {
      this.onScreen = entry.isIntersecting;
      if (this.onScreen && this.open) this.loop();
    });
    this.visibility.observe(this.stageTarget);
  }

  loop() {
    if (this.frame) return;
    const tick = () => {
      this.frame = null;
      if (!this.running || this.onScreen === false) return;
      if (!this.reducedMotion && !this.dragging) this.pivot.rotation.y += 0.004;
      this.renderer.render(this.scene, this.camera);
      this.frame = requestAnimationFrame(tick);
    };
    this.frame = requestAnimationFrame(tick);
  }

  teardown() {
    this.running = false;
    if (this.frame) cancelAnimationFrame(this.frame);
    this.resizeObserver?.disconnect();
    this.visibility?.disconnect();
    if (!this.renderer) return;
    this.disposeObject(this.scene);
    this.envMap?.dispose();
    this.renderer.dispose();
    this.renderer.domElement.remove();
    this.renderer = null;
  }
}
