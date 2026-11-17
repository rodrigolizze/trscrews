// Parametric screw for the product page 3D viewer.
//
// buildScrew(spec) returns a THREE.Group in millimetres, axis along +Y: the
// thread goes from the tip (y = 0) to y = length, the seat and head sit above
// it. spec comes from Screw#viewer_spec (Ruby): diameter, pitch, length, head
// (hex | lock | drain_plug | torx | torx_countersunk | allen), seat (conical |
// spherical | flat), wrench (mm across flats) and finish.
//
// Not a Stimulus controller: it lives here only so pin_all_from pins it
// ("controllers/screw_geometry") without touching config/importmap.rb.
import * as THREE from "three";

const SEGMENTS = 72;

// grain: strength of the procedural surface texture (0 = mirror smooth).
const FINISHES = {
  zinc:      { color: 0x9aa6b2, roughness: 0.3,  metalness: 1,    clearcoat: 0.3, grain: 0.35 },
  chrome:    { color: 0xe6e8eb, roughness: 0.03, metalness: 1,    clearcoat: 0,   grain: 0 },
  phosphate: { color: 0x3b3d40, roughness: 0.62, metalness: 0.7,  clearcoat: 0,   grain: 1 },
  geomet:    { color: 0x8f9398, roughness: 0.55, metalness: 0.9,  clearcoat: 0,   grain: 0.8 },
  black:     { color: 0x202124, roughness: 0.35, metalness: 0.8,  clearcoat: 0.4, grain: 0.4 },
  steel:     { color: 0xb8bcc1, roughness: 0.18, metalness: 1,    clearcoat: 0.5, grain: 0.2 }
};

// Fine metal grain drawn once on a small canvas (no image download): random
// speckle plus faint machining streaks. Used as roughness and bump map.
let grainCache = null;
function grainTexture() {
  if (grainCache) return grainCache;
  const size = 256;
  const canvas = document.createElement("canvas");
  canvas.width = canvas.height = size;
  const ctx = canvas.getContext("2d");
  const img = ctx.createImageData(size, size);
  for (let i = 0; i < size * size; i++) {
    const streak = Math.sin((i % size) * 0.9) * 6;
    const v = 205 + Math.random() * 50 + streak;
    img.data.set([v, v, v, 255], i * 4);
  }
  ctx.putImageData(img, 0, 0);
  grainCache = new THREE.CanvasTexture(canvas);
  grainCache.wrapS = grainCache.wrapT = THREE.RepeatWrapping;
  grainCache.repeat.set(4, 4);
  return grainCache;
}

export function finishMaterial(finish, envMap) {
  const { grain, ...preset } = FINISHES[finish] || FINISHES.steel;
  const options = { ...preset, envMap, envMapIntensity: 1.5, clearcoatRoughness: 0.08,
                    side: THREE.DoubleSide };  // lathe profiles are not all wound the same way
  if (grain > 0) {
    Object.assign(options, { roughnessMap: grainTexture(), bumpMap: grainTexture(), bumpScale: 0.04 * grain });
  }
  return new THREE.MeshPhysicalMaterial(options);
}

// ---------- TR head marking -------------------------------------------------
// Real bolts carry the maker's mark and the property class stamped on the head.
// Drawn on a canvas and applied as colour + bump map to a disc (flat heads) or a
// ring around the drive recess (torx, allen, wheel lock), so it reads engraved.
// The brand mark recoloured to a single engraving tone (the PNG is black on
// transparent; "source-in" keeps its shape and swaps the colour).
function tintedLogo(logo, width, height, color) {
  const canvas = document.createElement("canvas");
  canvas.width = Math.max(1, Math.round(width));
  canvas.height = Math.max(1, Math.round(height));
  const ctx = canvas.getContext("2d");
  ctx.drawImage(logo, 0, 0, canvas.width, canvas.height);
  ctx.globalCompositeOperation = "source-in";
  ctx.fillStyle = color;
  ctx.fillRect(0, 0, canvas.width, canvas.height);
  return canvas;
}

// Draws the TR logo (or the "TR" letters if the image did not load) centred on (x, y).
function drawMark(ctx, logo, x, y, width, font, color) {
  if (logo) {
    const height = width * (logo.naturalHeight / logo.naturalWidth);
    ctx.drawImage(tintedLogo(logo, width, height, color), x - width / 2, y - height / 2, width, height);
  } else {
    ctx.font = font(width * 0.55);
    ctx.fillText("TR", x, y);
  }
}

// Laser marks read dark on bright metal and light on black/phosphate.
const DARK_FINISHES = ["black", "phosphate"];

function markingTexture({ outerR, innerR, marking, logo, finish }) {
  const dark = DARK_FINISHES.includes(finish);
  const ink = dark ? "#b4b7bb" : "#2b2d30";
  // The map multiplies the material colour, so a light mark on a dark finish
  // needs the finish colour painted as the background and a white material.
  const background = dark ? `#${(FINISHES[finish] || FINISHES.steel).color.toString(16).padStart(6, "0")}` : "#ffffff";
  const size = 512, c = size / 2, scale = c / outerR;
  const canvas = document.createElement("canvas");
  canvas.width = canvas.height = size;
  const ctx = canvas.getContext("2d");
  ctx.fillStyle = background;
  ctx.fillRect(0, 0, size, size);
  ctx.fillStyle = dark ? "#b4b7bb" : "#6b6e72";
  ctx.textAlign = "center";
  ctx.textBaseline = "middle";
  const font = (px) => `${Math.round(px)}px Anton, "Arial Black", Impact, sans-serif`;

  if (!innerR) {
    // Flat head: the logo in the middle, class underneath.
    drawMark(ctx, logo, c, c - (marking ? outerR * scale * 0.14 : 0), outerR * scale * 1.15, font, ink);
    if (marking) {
      ctx.font = font(outerR * scale * 0.26);
      ctx.fillText(marking, c, c + outerR * scale * 0.5);
    }
  } else {
    // Recess in the middle: the logo above it, class below, inside the ring.
    const mid = ((outerR + innerR) / 2) * scale;
    const band = (outerR - innerR) * scale;
    drawMark(ctx, logo, c, c - mid, band * 1.5, font, ink);
    if (marking) {
      ctx.font = font(band * 0.5);
      ctx.fillText(marking, c, c + mid);
    }
  }
  const texture = new THREE.CanvasTexture(canvas);
  texture.colorSpace = THREE.SRGBColorSpace;
  return texture;
}

function addMarking(group, { top, outerR, innerR = 0, marking, finish, envMap, logo }) {
  const texture = markingTexture({ outerR, innerR, marking, logo, finish });
  const { grain, ...preset } = FINISHES[finish] || FINISHES.steel;
  const material = new THREE.MeshPhysicalMaterial({
    ...preset, envMap, envMapIntensity: 1.5, map: texture, bumpMap: texture, bumpScale: 0.6,
    color: DARK_FINISHES.includes(finish) ? 0xffffff : preset.color,
    side: THREE.DoubleSide
  });
  const geom = innerR
    ? new THREE.RingGeometry(innerR, outerR, SEGMENTS, 1)
    : new THREE.CircleGeometry(outerR, SEGMENTS);
  // RingGeometry UVs span the outer square, like CircleGeometry: the canvas maps 1:1.
  // rotateY(90°): the viewer lays the screw down (head to the right), so this turn
  // keeps the logo and the class upright on screen instead of sideways.
  const mesh = new THREE.Mesh(geom.rotateX(-Math.PI / 2).rotateY(Math.PI / 2), material);
  mesh.position.y = top + 0.03;
  group.add(mesh);
}

function recessMaterial() {
  return new THREE.MeshStandardMaterial({ color: 0x0d0e10, roughness: 0.9, metalness: 0.2 });
}

// ---------- Thread ----------------------------------------------------------
// A cylinder grid whose radius follows a helical ISO-like profile:
// r(angle, y) = minor radius + depth * triangle wave of (y / pitch - angle / 2π).
// The first pitch is chamfered so the tip looks like a real bolt end.
function threadGeometry(diameter, pitch, length) {
  const rMajor = diameter / 2;
  const depth = 0.6134 * pitch;
  const rMinor = rMajor - depth;
  const rows = Math.max(8, Math.ceil((length / pitch) * 14));
  const positions = [];
  const uvs = [];
  const indices = [];

  for (let i = 0; i <= rows; i++) {
    const y = (length * i) / rows;
    const chamfer = Math.min(1, y / pitch);
    for (let j = 0; j <= SEGMENTS; j++) {
      const a = (j / SEGMENTS) * Math.PI * 2;
      const phase = (((y / pitch - j / SEGMENTS) % 1) + 1) % 1;
      const tri = 1 - Math.abs(phase * 2 - 1);                 // 0 at root, 1 at crest
      const profile = Math.min(1, Math.max(0, (tri - 0.08) / 0.84));
      const r = rMinor * (0.94 + 0.06 * chamfer) + depth * profile * chamfer;
      positions.push(Math.cos(a) * r, y, Math.sin(a) * r);
      uvs.push(j / SEGMENTS, y / length);
    }
  }
  const row = SEGMENTS + 1;
  for (let i = 0; i < rows; i++) {
    for (let j = 0; j < SEGMENTS; j++) {
      const a = i * row + j, b = a + row;
      indices.push(a, b, a + 1, b, b + 1, a + 1);
    }
  }
  const geom = new THREE.BufferGeometry();
  geom.setAttribute("position", new THREE.Float32BufferAttribute(positions, 3));
  geom.setAttribute("uv", new THREE.Float32BufferAttribute(uvs, 2));
  geom.setIndex(indices);
  geom.computeVertexNormals();
  return { geom, rMinor };
}

// Closed solid of revolution from a [radius, y] profile (bottom to top).
function lathe(points) {
  return new THREE.LatheGeometry(points.map(([r, y]) => new THREE.Vector2(r, y)), SEGMENTS);
}

// ---------- Recess shapes (painted inset on the top face) -------------------
function starShape(radius, lobes, depthRatio) {
  const shape = new THREE.Shape();
  const steps = lobes * 24;
  for (let k = 0; k <= steps; k++) {
    const t = (k / steps) * Math.PI * 2;
    const r = radius * (1 - depthRatio / 2 + (depthRatio / 2) * Math.cos(lobes * t));
    const x = Math.cos(t) * r, y = Math.sin(t) * r;
    k === 0 ? shape.moveTo(x, y) : shape.lineTo(x, y);
  }
  return shape;
}

function polygonShape(radius, sides) {
  const shape = new THREE.Shape();
  for (let k = 0; k <= sides; k++) {
    const t = (k / sides) * Math.PI * 2;
    k === 0 ? shape.moveTo(Math.cos(t) * radius, Math.sin(t) * radius)
            : shape.lineTo(Math.cos(t) * radius, Math.sin(t) * radius);
  }
  return shape;
}

// Phillips cross: two crossed slots.
function crossShape(radius, width) {
  const w = width / 2, r = radius;
  const shape = new THREE.Shape();
  const pts = [[-w, r], [w, r], [w, w], [r, w], [r, -w], [w, -w], [w, -r], [-w, -r], [-w, -w], [-r, -w], [-r, w], [-w, w]];
  pts.forEach(([x, y], k) => (k === 0 ? shape.moveTo(x, y) : shape.lineTo(x, y)));
  shape.closePath();
  return shape;
}

// Lays a flat shape on the plane y = top, slightly sunk so it reads as a recess.
function recess(shape, top, material) {
  const geom = new THREE.ExtrudeGeometry(shape, { depth: 0.3, bevelEnabled: false });
  const mesh = new THREE.Mesh(geom, material);
  mesh.rotation.x = -Math.PI / 2;
  mesh.position.y = top - 0.28;
  return mesh;
}

// ---------- Seat --------------------------------------------------------------
// Returns the height it occupies above y = base and the radius it ends at.
function addSeat(group, seat, rMajor, outerR, base, material) {
  if (seat === "conical") {
    // 60° included angle: half-angle 30° from the axis, so each unit of height
    // widens the radius by tan(30°).
    const height = (outerR - rMajor) / Math.tan(Math.PI / 6);
    group.add(new THREE.Mesh(lathe([[rMajor * 0.98, base], [outerR, base + height]]), material));
    return height;
  }
  if (seat === "spherical") {
    const points = [];
    const height = (outerR - rMajor) * 0.75;
    for (let k = 0; k <= 12; k++) {
      const t = k / 12;
      points.push([rMajor * 0.98 + (outerR - rMajor) * Math.sin((t * Math.PI) / 2), base + height * t]);
    }
    group.add(new THREE.Mesh(lathe(points), material));
    return height;
  }
  // flat: a thin washer face
  const height = 0.6;
  group.add(new THREE.Mesh(new THREE.CylinderGeometry(outerR, outerR, height, SEGMENTS)
    .translate(0, base + height / 2, 0), material));
  return height;
}

// Hex prism with a chamfered top, across-flats = wrench.
function addHex(group, wrench, height, base, material) {
  const circumR = wrench / 2 / Math.cos(Math.PI / 6);
  const body = new THREE.CylinderGeometry(circumR, circumR, height * 0.88, 6).translate(0, base + height * 0.44, 0);
  const chamfer = new THREE.CylinderGeometry(circumR * 0.86, circumR, height * 0.12, 6).translate(0, base + height * 0.94, 0);
  group.add(new THREE.Mesh(body, material), new THREE.Mesh(chamfer, material));
  // Top: the chamfered hexagon; its inscribed circle is the flat face for the mark.
  return { top: base + height, faceR: circumR * 0.86 * Math.cos(Math.PI / 6) };
}

// ---------- Public builder ----------------------------------------------------
export function buildScrew(spec, envMap, { logo = null } = {}) {
  const d = Number(spec.diameter) || 12;
  const pitch = Number(spec.pitch) || 1.5;
  const length = Number(spec.length) || d * 2.5;
  const wrench = Number(spec.wrench) || Math.round(d * 1.5);
  const material = finishMaterial(spec.finish, envMap);
  const dark = recessMaterial();
  const group = new THREE.Group();
  const rMajor = d / 2;
  const mark = (top, outerR, innerR) =>
    addMarking(group, { top, outerR, innerR, marking: spec.marking, finish: spec.finish, envMap, logo });

  const { geom, rMinor } = threadGeometry(d, pitch, length);
  group.add(new THREE.Mesh(geom, material));
  group.add(new THREE.Mesh(new THREE.CircleGeometry(rMinor * 0.95, SEGMENTS).rotateX(Math.PI / 2), material));

  let y = length;
  switch (spec.head) {
    case "torx_countersunk": {
      // 90° countersunk head, head diameter ~ 2 × d, torx recess on top.
      const headR = d;
      const h = headR - rMajor;
      group.add(new THREE.Mesh(lathe([[rMajor * 0.98, y], [headR, y + h], [headR, y + h + 0.4], [0, y + h + 0.4]]), material));
      group.add(recess(starShape(d * 0.42, 6, 0.35), y + h + 0.4, dark));
      mark(y + h + 0.4, headR * 0.97, d * 0.46);
      break;
    }
    case "torx":
    case "allen": {
      // Cylindrical socket head with a torx or hex recess.
      const headR = d * 0.8, h = d * 0.85;
      group.add(new THREE.Mesh(lathe([[rMajor * 0.98, y], [headR, y], [headR, y + h * 0.9], [headR * 0.92, y + h], [0, y + h]]), material));
      const shape = spec.head === "torx" ? starShape(d * 0.38, 6, 0.35) : polygonShape(d * 0.36, 6);
      group.add(recess(shape, y + h, dark));
      mark(y + h, headR * 0.9, d * 0.42);
      break;
    }
    case "phillips_pan": {
      // Pan head: low dome, phillips cross; the mark goes around the cross.
      // Flat top (where the mark goes) with a rounded rim, like a real pan head.
      const headR = d, h = d * 0.6, flatR = headR * 0.74, rimY = y + h * 0.45;
      const points = [[rMajor * 0.98, y], [headR, y], [headR, rimY]];
      for (let k = 1; k <= 10; k++) {
        const t = (k / 10) * (Math.PI / 2);
        points.push([flatR + (headR - flatR) * Math.cos(t), rimY + (y + h - rimY) * Math.sin(t)]);
      }
      points.push([0, y + h]);
      group.add(new THREE.Mesh(lathe(points), material));
      group.add(recess(crossShape(d * 0.34, d * 0.13), y + h, dark));
      mark(y + h, flatR * 0.98, d * 0.37);
      break;
    }
    case "hex_flange": {
      // Flanged hex: wide flange (built-in washer) under a hex.
      const flangeR = wrench * 0.68, flangeH = d * 0.16;
      group.add(new THREE.Mesh(lathe([[rMajor * 0.98, y], [flangeR, y], [flangeR, y + flangeH * 0.6], [flangeR * 0.8, y + flangeH], [0, y + flangeH]]), material));
      const { top, faceR } = addHex(group, wrench, d * 0.65, y + flangeH, material);
      mark(top, faceR, 0);
      break;
    }
    case "drain_plug": {
      // Copper sealing washer, flange and a short hex (oil drain plug).
      const copper = new THREE.MeshPhysicalMaterial({ color: 0xb87333, metalness: 1, roughness: 0.3, envMap, envMapIntensity: 1.4, side: THREE.DoubleSide });
      const washerR = wrench * 0.72;
      group.add(new THREE.Mesh(new THREE.CylinderGeometry(washerR, washerR, 1.5, SEGMENTS).translate(0, y + 0.75, 0), copper));
      y += 1.5;
      group.add(new THREE.Mesh(new THREE.CylinderGeometry(washerR * 1.05, washerR * 1.05, 2, SEGMENTS).translate(0, y + 1, 0), material));
      const { top, faceR } = addHex(group, wrench, d * 0.6, y + 2, material);
      mark(top, faceR, 0);
      break;
    }
    case "lock": {
      // Wheel lock: seat + round head with a coded (wavy) key pattern.
      const headR = wrench * 0.6;
      y += addSeat(group, spec.seat || "conical", rMajor, headR * 0.92, y, material);
      const h = d * 0.75;
      group.add(new THREE.Mesh(lathe([[headR * 0.92, y], [headR, y + h * 0.2], [headR, y + h * 0.8], [headR * 0.85, y + h], [0, y + h]]), material));
      group.add(recess(starShape(headR * 0.62, 5, 0.25), y + h, dark));
      mark(y + h, headR * 0.84, headR * 0.66);
      break;
    }
    default: {
      // Hex head (wheel bolt or generic), with the requested seat under it.
      const seatR = wrench * 0.5;
      y += addSeat(group, spec.seat || "flat", rMajor, seatR, y, material);
      const { top, faceR } = addHex(group, wrench, d * 0.75, y, material);
      mark(top, faceR, 0);
    }
  }
  return group;
}
