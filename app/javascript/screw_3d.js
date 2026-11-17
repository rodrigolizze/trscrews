import * as THREE from "three";
import { RGBELoader } from "three/addons/loaders/RGBELoader.js";
import { buildScrew, studioEnvironment } from "controllers/screw_geometry";

// Hero da página inicial: o parafuso é desenhado pelo mesmo gerador das páginas
// de produto (controllers/screw_geometry), em vez do modelo pronto screw.glb.
// Assim a logo TR sai gravada de verdade na cabeça (afundada na geometria) e a
// página deixa de baixar o .glb (1,5 MB) e o decodificador Draco. O reflexo
// continua vindo da mesma foto de estúdio (HDR) do hero antigo.
//
// É uma peça de vitrine, não um produto do catálogo: por isso a página não
// mostra medidas sob o 3D.
const SHOWCASE_SPEC = {
  diameter: 14, pitch: 1.5, length: 30, head: "hex", seat: "conical",
  wrench: 19, finish: "chrome", marking: null
};
// Na vitrine a cabeça leva a logo completa (TR AUTOFIX), sem classe de
// resistência: não é uma peça real do catálogo.
// Comprimento total na cena (em unidades da câmera) e profundidade extra da
// gravação, já que aqui a cabeça é vista bem de perto.
const SHOWCASE_LENGTH = 0.85;
const SHOWCASE_MARK_DEPTH = 2.2;
// Foto real de estúdio (HDRI, CC0 da Poly Haven) refletida pelo cromado: é ela
// que dá o reflexo "de verdade" do hero. Enquanto baixa, vale o estúdio desenhado.
const SHOWCASE_HDRI = "https://dl.polyhaven.org/file/ph-assets/HDRIs/hdr/1k/studio_small_03_1k.hdr";
const CHROME_LOOK = { envMapIntensity: 2.0, clearcoat: 0.6, clearcoatRoughness: 0.03, roughness: 0.04 };
// Pose final calculada, sem ajuste no olho. A gravação "para cima" fica no
// eixo -X do parafuso (ver addMarking). Com rotX = 90° a cabeça aponta para a
// câmera; aí um giro de rotY = 270° leva o -X para o alto da tela: logo em pé
// e sextavado com lados retos em cima e embaixo.
const FINAL_SPIN = (3 * Math.PI) / 2;

// Redesign (direção D): o parafuso é a peça central do hero, em todas as
// larguras. O giro acompanha a rolagem da página até o hero sair da tela.
// O tamanho do palco vem do CSS (.hd-hero__visual); aqui só acompanhamos com
// ResizeObserver.

let scene, camera, renderer, screwGroup, animationId;
let initializedRoot = null;
let currentProgress = 0;
let targetProgress = 0;
let isVisible = true;
let needsRender = true;
let resizeObserver = null;
let visibilityObserver = null;

const reducedMotionQuery = window.matchMedia("(prefers-reduced-motion: reduce)");
// Ângulo de repouso para quem pede menos movimento: mostra cabeça e rosca.
const REDUCED_MOTION_PROGRESS = 0.35;

function loadImage(url) {
  if (!url) return Promise.resolve(null);
  return new Promise((resolve) => {
    const img = new Image();
    img.onload = () => resolve(img);
    img.onerror = () => resolve(null);
    img.src = url;
  });
}

// Vitrine centrada na origem, em pé (cabeça para cima), no tamanho da cena.
async function addShowcaseScrew(group, envMap, logoUrl) {
  await document.fonts?.load("100px Anton").catch(() => {});
  const logo = await loadImage(logoUrl);
  // Gravação no próprio metal, com o fundo só um pouco mais escuro para destacar.
  const screw = buildScrew(SHOWCASE_SPEC, envMap, { logo, markDepth: SHOWCASE_MARK_DEPTH, markInk: "subtle" });
  screw.updateMatrixWorld(true);
  const box = new THREE.Box3().setFromObject(screw);
  const size = box.getSize(new THREE.Vector3());
  screw.position.sub(box.getCenter(new THREE.Vector3()));

  const holder = new THREE.Group();
  holder.add(screw);
  holder.scale.setScalar(SHOWCASE_LENGTH / size.y);
  group.add(holder);
}

function webglAvailable() {
  try {
    const canvas = document.createElement("canvas");
    return !!(window.WebGLRenderingContext &&
      (canvas.getContext("webgl2") || canvas.getContext("webgl")));
  } catch (_e) {
    return false;
  }
}

function initScrew() {
  const root = document.getElementById("screw-3d-root");
  if (!root) return;

  // Idempotência por elemento. run() é chamado pela avaliação do módulo e pelo
  // turbo:load. Sem isto o init roda 2× por carregamento e as duas montagens em
  // voo se atropelam sobre as mesmas variáveis de módulo — o envMap do primeiro
  // chega numa cena que já é a do segundo, e o material metálico renderiza quase
  // preto.
  //
  // Guardamos a REFERÊNCIA do elemento, não um data-attribute nem "existe canvas?":
  // o snapshot do Turbo serializa o DOM, então marca e canvas voltariam no cache e
  // o guard barraria a reconstrução, deixando um canvas morto na tela. Identidade
  // de nó é justamente o que o snapshot não preserva.
  if (initializedRoot === root) return;
  initializedRoot = root;

  if (animationId) cancelAnimationFrame(animationId);
  root.innerHTML = "";

  // Sem WebGL (aparelho antigo, modo de economia): o palco fica só com o fundo.
  if (!webglAvailable()) {
    root.classList.add("is-fallback");
    return;
  }

  const width = root.clientWidth || 1;
  const height = root.clientHeight || 1;
  const isSmall = width < 768;

  scene = new THREE.Scene();

  camera = new THREE.PerspectiveCamera(40, width / height, 0.1, 100);
  camera.position.set(0, 0.4, 1.35);
  camera.lookAt(0, 0.4, 0);

  // Celular: limita a densidade de pixels (1.5) — a diferença visual é mínima e
  // a economia de GPU/bateria é grande.
  const maxRatio = isSmall ? 1.5 : 2;
  renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true, powerPreference: "low-power" });
  renderer.setPixelRatio(Math.min(window.devicePixelRatio, maxRatio));
  renderer.setSize(width, height);
  renderer.toneMapping = THREE.ACESFilmicToneMapping;
  renderer.toneMappingExposure = 1.1;
  renderer.outputColorSpace = THREE.SRGBColorSpace;
  root.appendChild(renderer.domElement);

  // Luzes do hero original (um pouco mais contidas): realce forte de um lado,
  // contraluz frio do outro, preenchimento por cima.
  scene.add(new THREE.AmbientLight(0xffffff, 0.5));
  const keyLight = new THREE.DirectionalLight(0xffffff, 2.8);
  keyLight.position.set(5, 8, 6);
  scene.add(keyLight);
  const rimLight = new THREE.DirectionalLight(0xe8ecf0, 1.6);
  rimLight.position.set(-4, 3, -4);
  scene.add(rimLight);
  const fillLight = new THREE.DirectionalLight(0xffffff, 0.8);
  fillLight.position.set(0, 5, 2);
  scene.add(fillLight);

  screwGroup = new THREE.Group();
  screwGroup.position.set(0, 0.65, 0);
  screwGroup.rotation.set(-0.04, -0.3, 0.14);
  scene.add(screwGroup);

  const envMap = studioEnvironment(renderer);
  scene.environment = envMap;
  const thisScene = scene;
  const built = addShowcaseScrew(screwGroup, envMap, root.dataset.screwLogo).then(() => { needsRender = true; });
  new RGBELoader().load(SHOWCASE_HDRI, (hdr) => {
    // Turbo pode ter remontado a cena enquanto a HDR baixava.
    if (scene !== thisScene) { hdr.dispose(); return; }
    const pmrem = new THREE.PMREMGenerator(renderer);
    const hdrEnv = pmrem.fromEquirectangular(hdr).texture;
    hdr.dispose();
    pmrem.dispose();
    built.then(() => {
      if (scene !== thisScene) return;
      scene.environment = hdrEnv;
      screwGroup.traverse((obj) => {
        if (!obj.isMesh || !obj.material.isMeshPhysicalMaterial) return;
        Object.assign(obj.material, CHROME_LOOK, { envMap: hdrEnv });
        obj.material.needsUpdate = true;
      });
      needsRender = true;
    });
  });

  // Acompanha o tamanho do palco (mudança de breakpoint, rotação do celular).
  if (resizeObserver) resizeObserver.disconnect();
  resizeObserver = new ResizeObserver(() => onResize());
  resizeObserver.observe(root);

  // Fora da tela, não renderiza nada (economia de bateria no celular).
  if (visibilityObserver) visibilityObserver.disconnect();
  visibilityObserver = new IntersectionObserver(([entry]) => {
    isVisible = entry.isIntersecting;
    if (isVisible) needsRender = true;
  });
  visibilityObserver.observe(root);

  updateProgress();
  currentProgress = targetProgress;
  animate();
}

// Progresso 0 → 1. O giro TERMINA com o parafuso ainda na tela: quando o centro
// do palco chega a 45% da altura da janela (de cima para baixo). Antes ele só
// terminava com o palco já fora da tela, e o usuário nunca via a pose final
// (cabeça de frente, com o logo).
const END_AT_VIEWPORT_RATIO = 0.45;
// Rolagem mínima para completar o giro — evita que ele "pule" em telas onde o
// palco já começa perto do topo.
const MIN_SCROLL_DISTANCE = 240;

function updateProgress() {
  if (reducedMotionQuery.matches) {
    targetProgress = REDUCED_MOTION_PROGRESS;
    return;
  }
  const root = document.getElementById("screw-3d-root");
  if (!root) return;
  const rect = root.getBoundingClientRect();
  const absCenter = rect.top + window.scrollY + rect.height / 2;
  const endScroll = Math.max(
    MIN_SCROLL_DISTANCE,
    absCenter - window.innerHeight * END_AT_VIEWPORT_RATIO
  );
  const raw = Math.min(1, Math.max(0, window.scrollY / endScroll));
  // Ease-out: o giro desacelera e assenta na pose final, então parar a
  // rolagem um pouco antes do fim já mostra a cabeça de frente, em pé.
  targetProgress = 1 - Math.pow(1 - raw, 3);
}

function animate() {
  animationId = requestAnimationFrame(animate);
  if (!document.getElementById("screw-3d-root")) {
    cancelAnimationFrame(animationId);
    return;
  }
  if (!isVisible || document.hidden) return;

  // Amortecimento: o parafuso "alcança" a rolagem em vez de pular.
  const alpha = 0.08;
  const delta = targetProgress - currentProgress;
  if (Math.abs(delta) > 0.0005) {
    currentProgress += delta * alpha;
    needsRender = true;
  }
  if (!needsRender) return;

  const ease = Math.min(1, Math.max(0, currentProgress));
  const targetRotY = ease * FINAL_SPIN;
  const targetRotZ = 0.14 * (1 - ease);
  const targetRotX = -0.04 * (1 - ease) + ease * (Math.PI / 2);
  const targetY = 0.4 - ease * 0.1;
  const targetScale = 0.78 + ease * 0.1;

  if (screwGroup) {
    screwGroup.rotation.set(targetRotX, targetRotY, targetRotZ);
    screwGroup.position.set(0, targetY, 0);
    screwGroup.scale.setScalar(targetScale);
  }

  if (renderer && scene && camera) {
    renderer.render(scene, camera);
  }
  needsRender = false;
}

function onResize() {
  const root = document.getElementById("screw-3d-root");
  if (!root || !camera || !renderer) return;
  const w = root.clientWidth;
  const h = root.clientHeight;
  if (w === 0 || h === 0) return;
  renderer.setSize(w, h);
  camera.aspect = w / h;
  camera.updateProjectionMatrix();
  needsRender = true;
}

function run() {
  if (document.getElementById("screw-3d-root")) {
    initScrew();
  }
}

window.addEventListener("scroll", updateProgress, { passive: true });
window.addEventListener("resize", updateProgress, { passive: true });
reducedMotionQuery.addEventListener("change", () => { updateProgress(); needsRender = true; });

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", run);
} else {
  run();
}
document.addEventListener("turbo:load", run);
