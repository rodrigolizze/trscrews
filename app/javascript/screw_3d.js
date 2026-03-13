import * as THREE from "three";
import { GLTFLoader } from "three/addons/loaders/GLTFLoader.js";

let scene, camera, renderer, screwGroup, animationId;
let currentProgress = 0;
let targetProgress = 0;
const ratios = [0, 0, 0, 0];

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

function initScrew() {
  const root = document.getElementById("screw-3d-root");
  if (!root) return;

  if (animationId) cancelAnimationFrame(animationId);
  if (renderer && renderer.domElement) {
    root.innerHTML = "";
  }

  const width = root.offsetWidth;
  const height = root.offsetHeight;

  scene = new THREE.Scene();

  camera = new THREE.PerspectiveCamera(40, width / height, 0.1, 100);
  camera.position.set(0, 0.4, 1.35);
  camera.lookAt(0, 0.4, 0);

  renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true });
  renderer.setSize(width, height);
  renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
  root.appendChild(renderer.domElement);

  const ambientLight = new THREE.AmbientLight(0xffffff, 0.35);
  scene.add(ambientLight);

  const dirLight = new THREE.DirectionalLight(0xffffff, 2.5);
  dirLight.position.set(5, 8, 6);
  scene.add(dirLight);

  const dirLight2 = new THREE.DirectionalLight(0xe8ecf0, 1.2);
  dirLight2.position.set(-4, 3, -4);
  scene.add(dirLight2);

  screwGroup = new THREE.Group();
  screwGroup.position.set(0, 0.65, 0);
  screwGroup.rotation.set(-0.04, -0.3, 0.14);
  scene.add(screwGroup);

  const modelUrl = root.dataset.screwModel;
  if (modelUrl) {
    const loader = new GLTFLoader();
    loader.load(
      modelUrl,
      (gltf) => {
        const model = gltf.scene;
        model.position.set(0, 0, 0);
        model.rotation.set(0, 0, 0);
        model.scale.setScalar(1);
        screwGroup.add(model);
      },
      undefined,
      () => {
        addProceduralScrew(screwGroup);
      }
    );
  } else {
    addProceduralScrew(screwGroup);
  }

  const cards = [1, 2, 3, 4].map((i) => document.getElementById(`screw-card-${i}`));
  cards.forEach((card, i) => {
    if (!card) return;
    const observer = new IntersectionObserver(
      ([entry]) => {
        ratios[i] = entry.intersectionRatio;
        updateProgress();
      },
      {
        threshold: [0, 0.25, 0.5, 0.75, 1],
        rootMargin: "0px 0px -20% 0px"
      }
    );
    observer.observe(card);
  });

  updateProgress();
  animate();

  window.addEventListener("resize", onResize);
}

function updateProgress() {
  let maxIdx = 0;
  for (let i = 0; i < 4; i++) {
    if (ratios[i] > 0) maxIdx = i;
  }
  targetProgress = (maxIdx + ratios[maxIdx]) * 0.25;
}

function animate() {
  animationId = requestAnimationFrame(animate);
  if (!document.getElementById("screw-3d-root")) {
    cancelAnimationFrame(animationId);
    return;
  }

  const alpha = 0.08;
  currentProgress += (targetProgress - currentProgress) * alpha;

  const ease = Math.min(1, Math.max(0, currentProgress));
  const logoRotationDeg = 207;
  const targetRotY = 0 + ease * (Math.PI / 2 + logoRotationDeg * (Math.PI / 180));
  const targetRotZ = 0.14 * (1 - ease);
  const targetRotX = -0.04 * (1 - ease) + ease * (Math.PI / 2);
  const targetY = 0.4 - ease * 0.1;
  const targetScale = 0.78 + ease * 0.1;

  if (screwGroup) {
    screwGroup.rotation.y = targetRotY;
    screwGroup.rotation.z = targetRotZ;
    screwGroup.rotation.x = targetRotX;
    screwGroup.position.set(0, targetY, 0);
    screwGroup.scale.setScalar(targetScale);
  }

  if (renderer && scene && camera) {
    renderer.render(scene, camera);
  }
}

function onResize() {
  const root = document.getElementById("screw-3d-root");
  if (!root || !camera || !renderer) return;
  const width = root.offsetWidth;
  const height = root.offsetHeight;
  camera.aspect = width / height;
  camera.updateProjectionMatrix();
  renderer.setSize(width, height);
}

function run() {
  if (document.getElementById("screw-3d-root")) {
    initScrew();
  }
}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", run);
} else {
  run();
}
document.addEventListener("turbo:load", run);
