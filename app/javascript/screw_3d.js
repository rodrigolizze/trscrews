import * as THREE from "three";
import { GLTFLoader } from "three/addons/loaders/GLTFLoader.js";
import { DRACOLoader } from "three/addons/loaders/DRACOLoader.js";
import { RGBELoader } from "three/addons/loaders/RGBELoader.js";

// screw.glb is Draco-compressed, so GLTFLoader needs a decoder injected or it cannot
// read the mesh at all. The decoder is pinned to the same three.js release we load
// from jsDelivr, so both move together on upgrade.
const DRACO_DECODER_PATH =
  "https://cdn.jsdelivr.net/npm/three@0.160.0/examples/jsm/libs/draco/";

// Redesign (direção D): o parafuso saiu da seção de cards e virou a peça central do
// hero, em todas as larguras (antes era só >= 992px). O giro agora acompanha a
// rolagem da página até o hero sair da tela, em vez de seguir os 4 cards.
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

function createProceduralEnvMap(renderer) {
  const pmrem = new THREE.PMREMGenerator(renderer);
  const canvas = document.createElement("canvas");
  canvas.width = 512;
  canvas.height = 256;
  const ctx = canvas.getContext("2d");
  const g = ctx.createLinearGradient(0, 0, 0, 256);
  g.addColorStop(0, "#707070");
  g.addColorStop(0.5, "#e0e0e0");
  g.addColorStop(1, "#808080");
  ctx.fillStyle = g;
  ctx.fillRect(0, 0, 512, 256);
  const texture = new THREE.CanvasTexture(canvas);
  texture.mapping = THREE.EquirectangularReflectionMapping;
  const envMap = pmrem.fromEquirectangular(texture).texture;
  texture.dispose();
  pmrem.dispose();
  return envMap;
}

function applyMetallicMaterials(model, envMap) {
  const metalPreset = {
    metalness: 1,
    roughness: 0.03,
    envMapIntensity: 2.2,
    clearcoat: 0.7,
    clearcoatRoughness: 0.02,
    color: 0xe8e9eb
  };
  model.traverse((child) => {
    if (!child.isMesh || !child.material) return;
    const mats = Array.isArray(child.material) ? child.material : [child.material];
    for (const mat of mats) {
      if (mat.isMeshStandardMaterial || mat.isMeshPhysicalMaterial) {
        mat.metalness = metalPreset.metalness;
        mat.roughness = metalPreset.roughness;
        mat.envMapIntensity = metalPreset.envMapIntensity;
        mat.envMap = envMap;
        mat.clearcoat = metalPreset.clearcoat;
        mat.clearcoatRoughness = metalPreset.clearcoatRoughness;
        mat.roughnessMap = null;
        mat.normalMap = null;
        if (mat.map) {
          mat.color.setHex(0xffffff);
        } else {
          mat.color.setHex(metalPreset.color);
        }
      } else {
        const metal = new THREE.MeshPhysicalMaterial({
          color: metalPreset.color,
          metalness: metalPreset.metalness,
          roughness: metalPreset.roughness,
          envMap: envMap,
          envMapIntensity: metalPreset.envMapIntensity,
          clearcoat: metalPreset.clearcoat,
          clearcoatRoughness: metalPreset.clearcoatRoughness,
          map: mat.map || null
        });
        if (mat.map) metal.color.setHex(0xffffff);
        child.material = Array.isArray(child.material)
          ? mats.map(() => metal.clone())
          : metal;
        break;
      }
    }
  });
}

function addProceduralScrew(group) {
  const metal = new THREE.MeshPhysicalMaterial({
    color: 0xe8e9eb,
    metalness: 1,
    roughness: 0.08,
    envMapIntensity: 1.8,
    clearcoat: 0.6,
    clearcoatRoughness: 0.05
  });

  const shaftGeom = new THREE.CylinderGeometry(0.28, 0.30, 6.2, 48);
  const shaft = new THREE.Mesh(shaftGeom, metal);
  shaft.rotation.z = Math.PI / 2;
  group.add(shaft);

  const headGeom = new THREE.CylinderGeometry(0.75, 0.72, 0.95, 48);
  const head = new THREE.Mesh(headGeom, metal);
  head.position.x = 3.5;
  head.rotation.z = Math.PI / 2;
  group.add(head);

  const darkerMetal = new THREE.MeshPhysicalMaterial({
    color: 0x5a5d62,
    metalness: 1,
    roughness: 0.12,
    envMapIntensity: 1.5,
    clearcoat: 0.5,
    clearcoatRoughness: 0.08
  });

  const socket1 = new THREE.Mesh(
    new THREE.BoxGeometry(0.52, 0.12, 0.52),
    darkerMetal
  );
  socket1.position.set(3.95, 0, 0);
  socket1.rotation.z = Math.PI / 4;
  group.add(socket1);

  const socket2 = new THREE.Mesh(
    new THREE.BoxGeometry(0.52, 0.12, 0.52),
    darkerMetal
  );
  socket2.position.set(3.95, 0, 0);
  socket2.rotation.set(Math.PI / 2, 0, Math.PI / 4);
  group.add(socket2);
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
  // turbo:load. Sem isto o init roda 2× por carregamento e os dois RGBELoader em
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
  renderer.toneMappingExposure = 1.2;
  root.appendChild(renderer.domElement);

  const pmremGenerator = new THREE.PMREMGenerator(renderer);
  pmremGenerator.compileEquirectangularShader();

  scene.add(new THREE.AmbientLight(0xffffff, 0.7));

  const dirLight = new THREE.DirectionalLight(0xffffff, 3.5);
  dirLight.position.set(5, 8, 6);
  scene.add(dirLight);

  const dirLight2 = new THREE.DirectionalLight(0xe8ecf0, 2);
  dirLight2.position.set(-4, 3, -4);
  scene.add(dirLight2);

  const fillLight = new THREE.DirectionalLight(0xffffff, 1);
  fillLight.position.set(0, 5, 2);
  scene.add(fillLight);

  screwGroup = new THREE.Group();
  screwGroup.position.set(0, 0.65, 0);
  screwGroup.rotation.set(-0.04, -0.3, 0.14);
  scene.add(screwGroup);

  const envUrl = root.dataset.screwEnv || "https://dl.polyhaven.org/file/ph-assets/HDRIs/hdr/1k/studio_small_03_1k.hdr";
  const modelUrl = root.dataset.screwModel;

  function onEnvLoaded(envMap) {
    scene.environment = envMap;
    needsRender = true;
    if (modelUrl) {
      const dracoLoader = new DRACOLoader();
      dracoLoader.setDecoderPath(DRACO_DECODER_PATH);
      dracoLoader.setDecoderConfig({ type: "wasm" });

      const loader = new GLTFLoader();
      loader.setDRACOLoader(dracoLoader);
      loader.load(
        modelUrl,
        (gltf) => {
          const model = gltf.scene;
          model.position.set(0, 0, 0);
          model.rotation.set(0, 0, 0);
          model.scale.setScalar(1);
          applyMetallicMaterials(model, envMap);
          screwGroup.add(model);
          dracoLoader.dispose();
          needsRender = true;
        },
        undefined,
        () => {
          addProceduralScrew(screwGroup);
          needsRender = true;
        }
      );
    } else {
      addProceduralScrew(screwGroup);
      needsRender = true;
    }
  }

  new RGBELoader().load(envUrl, (texture) => {
    texture.mapping = THREE.EquirectangularReflectionMapping;
    const envMap = pmremGenerator.fromEquirectangular(texture).texture;
    texture.dispose();
    onEnvLoaded(envMap);
  }, undefined, () => {
    const envMap = createProceduralEnvMap(renderer);
    onEnvLoaded(envMap);
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

// Progresso 0 → 1: do topo da página até o palco do parafuso sair da tela por cima.
function updateProgress() {
  if (reducedMotionQuery.matches) {
    targetProgress = REDUCED_MOTION_PROGRESS;
    return;
  }
  const root = document.getElementById("screw-3d-root");
  if (!root) return;
  const rect = root.getBoundingClientRect();
  const endY = rect.bottom + window.scrollY; // posição absoluta do fim do palco
  const p = endY > 0 ? window.scrollY / endY : 0;
  targetProgress = Math.min(1, Math.max(0, p));
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
  const logoRotationDeg = 207;
  const targetRotY = ease * (Math.PI / 2 + logoRotationDeg * (Math.PI / 180));
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
