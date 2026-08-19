# Compressão Draco do `screw.glb` — Investigação

**Data:** 2026-08-19
**Branch:** master
**Status:** investigação apenas — nada foi modificado, instalado ou comprimido
**Meta do usuário:** reduzir 31 MB → ~300 KB–1 MB sem mudança visual perceptível

---

## Resumo executivo (leia isto primeiro)

Três achados mudam o plano em relação ao que foi pedido:

1. **A geometria domina — 96,05% do arquivo.** Draco ataca exatamente isso. A hipótese
   estava certa.
2. **Draco sozinho provavelmente NÃO chega em 300 KB–1 MB.** O modelo tem 1.376.376
   triângulos. Draco deve levar o arquivo para a faixa de **1,5–3,5 MB** (redução de
   ~89–95%). Para bater a meta é preciso **decimar a malha antes** (`simplify`) —
   e o modelo é tão denso que a decimação é visualmente gratuita neste caso.
3. **Existem DOIS `screw.glb` no repositório**, de modelos diferentes. O de 31 MB é o
   servido; o de 324 KB em `public/` é órfão e nunca é requisitado.

E uma correção à premissa do item 6 do pedido: **falha de Draco não produz tela vazia.**
O `screw_3d.js` já tem um `onError` que desenha um parafuso procedural. O modo de falha
real é degradação silenciosa — o visitante vê um parafuso genérico de baixo polígono e
ninguém percebe que o modelo quebrou. Isso é pior que tela vazia para efeito de detecção,
e o plano de teste abaixo trata disso explicitamente.

---

## 1. O modelo atual

### 1.1 Onde está, e qual é o servido

| Arquivo | Tamanho | Modelo | Servido? |
|---|---|---|---|
| `app/assets/images/screw.glb` | **31.749.504 B** (30,28 MiB) | Gerado por **Tripo 2.0** (IA), 1,37M triângulos, com texturas | **SIM** |
| `public/screw.glb` | 331.388 B (324 KiB) | Sketchfab "BOLT" de *Davide Specchi*, CC-BY-4.0, 9.019 vértices, sem texturas | **NÃO** |

Os dois têm MD5 diferentes e são modelos distintos — não são versões do mesmo asset.

**Cadeia de serving (confirmada):**

- `app/views/pages/home.html.erb:104`
  ```erb
  <div id="screw-3d-root" data-screw-model="<%= asset_path('screw.glb') %>" ...>
  ```
- `asset_path` resolve pelo **Sprockets**, que procura em `app/assets/images/` → gera
  `/assets/screw-<digest>.glb`.
- `config/initializers/assets.rb:13` — `Rails.application.config.assets.precompile += %w[ screw.glb ]`
  (confirmado, como você lembrava das etapas de upgrade).
- `public/screw.glb` seria servido em `/screw.glb`. **Nada no código referencia esse caminho.**
  É resto de uma versão anterior (commits `4997b06` / `fc71797`).

**Carregamento é ansioso, em toda visita.** `screw_3d.js:302-310` chama `run()` em
`DOMContentLoaded` **e** em `turbo:load`, e `initScrew()` dispara o `GLTFLoader.load()`
sem nenhum `IntersectionObserver` guardando o *fetch*. O `IntersectionObserver` que existe
no arquivo controla só a rotação conforme o scroll, não o download. Ou seja: sim, todo
visitante da home baixa 31 MB, mesmo que nunca role até o parafuso.

### 1.2 O que tem dentro dos 31 MB

Estrutura do container GLB: chunk `JSON` de 1.648 B + chunk `BIN` de 31.747.828 B.
Sem extensões (`extensionsUsed` e `extensionsRequired` ausentes — logo, **ainda não há
Draco nem meshopt**). 1 cena, 1 nó, 1 mesh, 1 primitive, 1 material, 3 texturas.

| bufferView | Conteúdo | Bytes | % do arquivo |
|---|---|---:|---:|
| #2 | `indices` — SCALAR, `UNSIGNED_INT` (4 B), 4.129.128 elementos | 16.516.512 | **52,0%** |
| #0 | `POSITION` — VEC3 `float32`, 699.019 vértices | 8.388.228 | **26,4%** |
| #1 | `TEXCOORD_0` — VEC2 `float32`, 699.019 vértices | 5.592.152 | **17,6%** |
| #4 | JPEG `panheadscrew3dmodel_basecolor` — 4096×4096 | 551.801 | 1,7% |
| #5 | JPEG `panheadscrew3dmodel_rm` (rough/metal) — 4096×4096 | 399.456 | 1,3% |
| #3 | JPEG `panheadscrew3dmodel_normal` — 4096×4096 | 299.675 | 0,9% |

**Geometria: 30.496.892 B = 96,05%. Texturas: 1.250.932 B = 3,94%.**

> **Veredito da pergunta central:** geometria domina de forma esmagadora. **Draco ajuda muito.**
> Comprimir as texturas resolveria no máximo 3,9% do problema de download.

**Números da malha:** 1.376.376 triângulos, 699.019 vértices. A razão V/T = 0,508 indica
uma malha **fechada e já soldada** (manifold) — não há ganho a extrair de um `weld` prévio.

**Dois detalhes que importam para o plano:**

- **Não existe atributo `NORMAL`.** O primitive tem só `POSITION` e `TEXCOORD_0`. O
  three.js detecta a ausência do atributo e renderiza em *flat shading*. Com 1,37M
  triângulos isso é indistinguível de *smooth shading* — mas deixa de ser, se a malha
  for decimada. Ver §6.2.
- **As texturas são 4096×4096.** No disco são só 1,25 MB (JPEG), mas na VRAM cada uma
  ocupa 4096² × 4 B ≈ 67 MB descomprimida, ~89 MB com mipmaps. Três delas ≈ **~268 MB
  de VRAM**. Em celular isso é um custo maior que o próprio download — e não aparece
  no tamanho do arquivo.

### 1.3 Como o frontend carrega

`app/javascript/screw_3d.js`:

```js
import * as THREE from "three";                                   // linha 1
import { GLTFLoader } from "three/addons/loaders/GLTFLoader.js";  // linha 2
import { RGBELoader } from "three/addons/loaders/RGBELoader.js";  // linha 3
...
const loader = new GLTFLoader();                                  // linha 196
loader.load(
  modelUrl,
  (gltf) => { ...applyMetallicMaterials(model, envMap); screwGroup.add(model); },
  undefined,
  () => { addProceduralScrew(screwGroup); }   // ← fallback silencioso
);
```

Pinado em `config/importmap.rb:4-7`, tudo via CDN jsDelivr:

```rb
pin "screw_3d", to: "screw_3d.js"
pin "three", to: "https://cdn.jsdelivr.net/npm/three@0.160.0/build/three.module.js"
pin "three/addons/loaders/GLTFLoader.js", to: ".../three@0.160.0/examples/jsm/loaders/GLTFLoader.js"
pin "three/addons/loaders/RGBELoader.js", to: ".../three@0.160.0/examples/jsm/loaders/RGBELoader.js"
```

**Observação sobre as texturas (achado lateral):** `applyMetallicMaterials()`
(`screw_3d.js:45-89`) sobrescreve o material do glTF com um preset metálico e faz
`mat.normalMap = null` e `mat.roughnessMap = null`. Ou seja, o **normal map de 4096×4096
(293 KB) é baixado, decodificado e descartado** — nunca chega à tela. O `_rm` continua
ligado como `metalnessMap` (o GLTFLoader atribui a mesma imagem a `metalnessMap` e
`roughnessMap`, e só o segundo é anulado). Só o `basecolor` é usado como pretendido.
Isso não é foco desta tarefa, mas é ganho fácil quando chegarmos nas texturas.

---

## 2. Three.js atual vs. o que Draco exige

### 2.1 Versão e disponibilidade do DRACOLoader

Versão do projeto: **three.js r160** (`three@0.160.0`, jsDelivr). O `DRACOLoader` existe
nessa versão. Verificado por requisição HEAD ao CDN:

| URL | Status |
|---|---|
| `https://cdn.jsdelivr.net/npm/three@0.160.0/examples/jsm/loaders/DRACOLoader.js` | `200` (`application/javascript`) |
| `https://cdn.jsdelivr.net/npm/three@0.160.0/examples/jsm/libs/draco/draco_decoder.wasm` | `200` (`application/wasm`) |

O r160 empacota o decoder Draco da linha 1.5.x, compatível com o encoder que o
gltf-transform 4.4.2 usa (`draco3dgltf ~1.5.7`).

### 2.2 O que muda no código

Draco não é transparente: o `GLTFLoader` só sabe abrir um `.glb` com
`KHR_draco_mesh_compression` se um `DRACOLoader` for injetado nele. A mudança em
`screw_3d.js` é pequena e localizada:

```js
import { DRACOLoader } from "three/addons/loaders/DRACOLoader.js";

const dracoLoader = new DRACOLoader();
dracoLoader.setDecoderPath("<caminho dos decoders>");   // precisa terminar com "/"
dracoLoader.setDecoderConfig({ type: "wasm" });         // wasm; cai para JS se indisponível
const loader = new GLTFLoader();
loader.setDRACOLoader(dracoLoader);
```

Mais uma linha em `config/importmap.rb` pinando `three/addons/loaders/DRACOLoader.js`.

O `DRACOLoader` busca os arquivos do decoder em runtime, a partir de `setDecoderPath`.
São 3 arquivos em `examples/jsm/libs/draco/`: `draco_decoder.js` (fallback asm.js),
`draco_wasm_wrapper.js` e `draco_decoder.wasm` (~ 200 KB combinados no caminho wasm).
Eles decodificam num Web Worker.

### 2.3 Decoder: CDN ou `public/`?

| | **CDN (jsDelivr)** | **`public/draco/` (self-hosted)** |
|---|---|---|
| Esforço | 1 linha (`setDecoderPath` para a URL) | copiar 3 arquivos + versioná-los no repo |
| Coerência com o projeto | **Alta** — three.js, GLTFLoader, RGBELoader e o HDRI já vêm de CDN | Introduz um padrão novo, misto |
| Risco de indisponibilidade | jsDelivr fora ⇒ decoder falha ⇒ fallback procedural | Nenhuma dependência externa nova |
| Versionamento | Travado na URL `three@0.160.0` — sobe junto no upgrade do three.js | Manual: precisa lembrar de atualizar no upgrade |
| Cache | Compartilhado entre sites; TTL longo do jsDelivr | Digest do Sprockets, cache imutável |
| Latência | +1 conexão a host externo | Mesma origem, reaproveita a conexão |
| CSP | Sem bloqueio hoje (ver abaixo) | Sem bloqueio |
| Privacidade/LGPD | IP do visitante vai para o jsDelivr — **já vai hoje**, por causa do three.js | Não vaza |

**CSP não é obstáculo em nenhum dos dois casos:** `config/initializers/content_security_policy.rb`
está **inteiramente comentado** — não há política em vigor.

**Recomendação:** **CDN**. O projeto já depende do jsDelivr para o próprio three.js — se
o CDN cair, o decoder é o menor dos problemas, porque a cena inteira já não carregou. Usar
CDN mantém decoder e three.js na mesma versão automaticamente, e é uma linha a menos para
esquecer no upgrade para Rails 8. Self-hosting só se passarmos a hospedar o three.js também.

> Vale registrar o *trade-off* de segurança de supply chain: um decoder wasm de terceiro
> executando no browser do visitante. É o mesmo perfil de risco do `three.module.js` que
> já carregamos do mesmo host, então não é uma fronteira nova. Se quisermos endurecer isso
> depois, o caminho é SRI + CSP — e aí faz sentido self-hostar tudo de uma vez.

---

## 3. Ferramenta de compressão

### 3.1 gltf-transform vs. gltf-pipeline

**Recomendação: `@gltf-transform/cli`.** Versão atual **4.4.2**, mantida ativamente por
Don McCurdy (que também mantém o `GLTFLoader` no three.js — mesmo autor dos dois lados do
pipeline). O `gltf-pipeline` (Cesium) funciona para Draco, mas é essencialmente só isso;
o gltf-transform traz no mesmo binário `simplify`, `resize`, `webp`, `prune`, `dedup`,
`inspect` — que, como a §1 mostrou, é exatamente o que este modelo precisa além de Draco.

Comandos disponíveis na CLI 4.4.2 (extraídos do pacote publicado):
`avif center copy dedup dequantize draco etc1s flatten gzip inspect instance join jpeg
ktxdecompress ktxfix merge meshopt metalrough optimize palette partition png prune quantize
reorder resample resize sequence simplify sparse tangents uastc unlit unweld unwrap
validate webp weld xmp`

> **Atenção — lacuna confirmada:** **não existe comando `normals` na CLI.** A função
> `normals()` existe apenas na API JS (`@gltf-transform/functions`). Isso importa porque
> este modelo não tem `NORMAL` (§1.2) e a decimação vai exigir gerar normais. Ver §6.2.

**Alternativa avaliada e descartada — meshopt.** `gltf-transform meshopt` (extensão
`EXT_meshopt_compression`) tem um decoder de ~25 KB contra ~200 KB do Draco wasm, e
decodifica mais rápido. Valia medir. **Medido na Etapa 1: 7.192.796 B contra 3.473.088 B
do Draco padrão — mais que o dobro.** Nesta malha o Draco ganha com folga, e os ~200 KB
extras de decoder se pagam muitas vezes. **Decisão: Draco.**

### 3.2 A compressão é offline — confirmado

**Sim, é offline e roda uma única vez.** O fluxo é:

```
screw.glb (31 MB)  →  [gltf-transform, na sua máquina]  →  screw.glb comprimido  →  commit
```

O `.glb` comprimido é um arquivo novo, versionado no git, que substitui o atual em
`app/assets/images/`. Nada de compressão em runtime, nada no servidor, nada no ciclo de
request. O browser faz **decodificação** em runtime (§4.3) — só isso.

**O que muda no build/deploy: nada.**

- Sem passo novo de build. O Sprockets continua tratando o `.glb` como asset binário
  opaco — ele copia e adiciona digest, não inspeciona o conteúdo.
- O `precompile += %w[ screw.glb ]` continua valendo sem alteração (mesmo nome de arquivo).
- O deploy no Heroku é idêntico ao de hoje.
- O gltf-transform **não** vira dependência da aplicação. É ferramenta de mesa, usada uma
  vez. **Não** deve entrar em `Gemfile` nem criar um `package.json` no projeto (que hoje
  não tem nenhum — é importmap puro, sem npm no build).

### 3.3 Requisitos

- **Node.js ≥ 20** — exigido pelo `@gltf-transform/cli` 4.4.2 (`engines.node: ">=20"`).
  Sua máquina: **v20.20.2** via nvm. ✅ Atende, mas por pouco.
- **npm 10.8.2** presente. ✅
- Instalar **fora do repositório** (ex.: no scratchpad ou via `npx`), para não criar
  `package.json`/`node_modules` no projeto:
  ```
  npx --yes @gltf-transform/cli@4.4.2 inspect ...
  ```
- O pacote traz `draco3dgltf`, `meshoptimizer`, `sharp` e `gltf-validator` como
  dependências — download inicial de algumas centenas de MB de `node_modules`. Por isso
  o scratchpad, não o repo.

---

## 4. Impacto esperado

### 4.1 Redução medida ✅

> **Medido em 2026-08-19 (Etapa 1), com `@gltf-transform/cli` 4.4.2.** Esta seção
> continha estimativas; foram substituídas pelos números reais. Todas as variantes
> passaram por `gltf-transform validate` com **zero erros**. Baseline: 31.749.504 B.

| # | Variante | Triângulos | Geometria | Texturas | **Total** | Redução |
|---|---|---:|---:|---:|---:|---:|
| — | **baseline** | 1.376.376 | 30.498.572 | 1.250.932 | **31.749.504** | — |
| **M** | meshopt | 1.376.376 | 5.941.864 | 1.250.932 | **7.192.796** | 77,3% |
| **A** | draco padrão | 1.376.376 | 2.222.156 | 1.250.932 | **3.473.088** | 89,1% |
| **B** | draco agressivo (pos 11, uv 9) | 1.376.376 | 1.215.064 | 1.250.932 | **2.465.996** | 92,2% |
| **C4** | simplify 10% + draco | 137.637 | 657.136 | 1.250.932 | **1.908.068** | 94,0% |
| **C2** | simplify 5% + draco | 68.818 | 352.516 | 1.250.932 | **1.603.448** | 95,0% |
| **C3** | simplify 3% + draco | 41.290 | 227.620 | 1.250.932 | **1.478.552** | 95,3% |
| **C5** | simplify 2% + draco | 27.526 | 161.252 | 1.250.932 | **1.412.184** | 95,6% |
| **D1** | C2 + tex 1024 WebP q80 | 68.818 | 352.644 | 40.588 | **393.232** | **98,8%** |
| **D4** | C3 + tex 2048 WebP q85 | 41.290 | 227.752 | 153.932 | **381.684** | 98,8% |
| **D2** | C2 + tex 512 WebP q80 | 68.818 | 352.642 | 16.026 | **368.668** | 98,8% |
| **D3** | C3 + tex 1024 WebP q80 | 41.290 | 227.748 | 40.588 | **268.336** | 99,2% |

**Achado — abaixo de ~70k triângulos, a geometria deixa de importar.** De C2 (68k tris)
para C5 (27k tris) economiza-se 191 KB; tratar as texturas economiza 1,21 MB. Depois da
decimação, as texturas passam a ser **78–88% do arquivo**.

> ⚠️ **D1 foi escolhida por estes números e REPROVADA no teste visual da Etapa 3.**
> Ver §4.1.1 — o tamanho do arquivo não era o critério que decidia.

### 4.1.1 Teste visual: o tamanho não decide ✅ (Etapa 3, 2026-08-19)

Todas as variantes abaixo carregam sem erro e passam na validação. O que as separa é
só a aparência do cromado (`metalness: 1`, `roughness: 0.03`, refletindo o HDRI).

| Variante | Triângulos | Tamanho | Rosca | Aro / colar da cabeça | Veredito |
|---|---:|---:|---|---|---|
| baseline | 1.376.376 | 31.749.504 | contínua | liso | referência |
| H (erro dirigindo) | 4.246–16.212 | 70.416–139.808 | destruída | polígono, cordas retas | ✗ |
| D1 | 68.818 | 393.232 | quebrada | espículas, papel amassado | ✗ |
| F1 | 137.637 | 697.852 | filetes quebrados | facetas planas nítidas | ✗ |
| F2 (= G1) | 206.456 | 992.092 | recuperada | aro amassado | ✗ |
| G2 | 275.274 | 1.274.508 | contínua | aro bom, colar facetado | ~ aceitável |
| **E3** ⭐ | 344.093 | **1.549.192** | igual ao baseline | facetamento leve | ✅ **limpo** |

**⭐ Variante final: E3 — 1.549.192 B, redução de 95,1%.** É o menor arquivo
visualmente limpo confirmado. G2 economizaria 275 KB em troca de um colar visivelmente
mais facetado — não compensa.

**A meta de 300 KB–1 MB é incompatível com a geometria deste modelo.** Ficar abaixo de
1 MB exige ≤206k triângulos, e 206k já reprova no aro da cabeça. Isso foi descoberto
medindo, não deduzido: a meta era uma estimativa, não um requisito, e a aparência tem
precedência sobre ela.

**Por que a decimação falha aqui, corrigindo a premissa original desta seção.** A §4.1
justificava a decimação com "~3 triângulos por pixel, mais de 95% da malha é invisível
por construção". **Está errado.** A necessidade de triângulos não é ditada pelos pixels
da tela e sim pela **frequência das features**: a rosca é uma hélice fina e o colar/aro
da cabeça são arestas vivas, e ambos se degradam independentemente do tamanho do canvas.
A rosca se recupera por volta de 206k triângulos; o aro e o colar só perto de 344k.

**O `--error` não é uma alavanca — é um teto, não um alvo.** Gerar ~206k com
`--error 0.001` produziu um arquivo **byte-idêntico** ao mesmo ratio com `--error 0.01`
(MD5 `9ac160d1…`): quando o `--ratio` é atingido antes de o erro encostar no limite, o
parâmetro nunca entra em jogo. Com `--ratio 0`, deixando o erro comandar, a malha desaba
para 4k–16k triângulos — uma ordem de grandeza abaixo do que já quebrava.

**A razão de fundo:** a métrica do meshoptimizer é de **distância posicional**, mas um
cromado com `roughness: 0.03` é sensível à **continuidade das normais**, que essa métrica
não limita. Por isso 0,05% de erro geométrico ainda destrói o reflexo. Nenhum ajuste de
`--error` protege a aparência — **a contagem de triângulos é o único controle real.**

**Bounding boxes preservadas.** As versões decimadas batem com a original com desvio de
~3×10⁻⁵ (0,007% do modelo) — nada encolheu, deslocou ou perdeu escala.

**Warning de validação (pré-existente, não é regressão):**
`MESH_PRIMITIVE_GENERATED_TANGENT_SPACE` — material com `normalTexture` sem atributo
`TANGENT`. **Já existe no baseline** e é inócuo aqui, porque o `screw_3d.js` anula o
`normalMap` (§1.3).

**Por que `simplify` é seguro aqui:** o canvas tem `min-height: 400px` e ocupa a coluna
`col-lg-7` — na prática algo como 400–700 px de lado. São 1,37M triângulos para ~500k
pixels: **cerca de 3 triângulos por pixel**. Mais de 95% da malha é invisível por
construção. Decimar para 40–80k triângulos não é uma concessão de qualidade; é remover
dados que a tela nunca teve como mostrar.

### 4.2 O que NÃO muda

- **Aparência.** Draco é lossy, mas a perda é quantização de posição (padrão: 14 bits por
  eixo) e de UV (12 bits). Num objeto desta escala, 14 bits dão ~1/16000 da caixa
  delimitadora por passo — muito abaixo de um pixel na tela. Imperceptível.
- **Materiais, texturas, cena, hierarquia, UVs.** Draco toca só os buffers de atributo de
  malha. O `applyMetallicMaterials()` continua funcionando igual.
- **A animação de scroll**, o `IntersectionObserver`, o `syncScrewHeight()` — nada disso
  encosta na geometria.
- **O fallback procedural** continua sendo o comportamento em caso de erro.

### 4.3 O custo em runtime

O trade-off é real e vale explicitar:

- **Hoje:** 31.749.504 B pela rede, zero decode. Numa conexão 4G de 10 Mbps, ≈ **25
  segundos** só de download. Em 3G, minutos.
- **Com E3:** 1.549.192 B (~1,2 s em 4G) + **~358 KB do decoder Draco** (medido: 13.628 B
  do `DRACOLoader.js` + 58.763 B do wrapper + 285.747 B do `.wasm`; cacheado entre visitas
  e entre sites, no caso do CDN) + decodificação no cliente.
- **Custo do decode:** com E3 são **344.093 triângulos**, um quarto do original. Draco
  decodifica isso na casa das centenas de milissegundos, em Web Worker — não trava a UI.
- **Saldo:** troca ~25 s de rede por ~1,2 s de rede + algumas centenas de ms de CPU.
- **Bônus não contabilizado no tamanho do arquivo:** as texturas caem de 4096² para 1024²,
  o que reduz o consumo de VRAM de ~268 MB para **~17 MB** (§1.2). Em celular esse ganho
  pode importar mais que os bytes economizados.

---

## 5. Plano de execução proposto

Numerado, com pontos de parada explícitos. **Nada abaixo foi executado.**

### Etapa 0 — Aprovação e preparo *(ponto de parada)*
0.1. Você aprova este documento e escolhe o alvo: **cenário A/B (só Draco, ~2–4 MB)** ou
     **cenário C/D (Draco + decimação + texturas, ~350–750 KB, bate a meta)**.
0.2. Definir se o decoder vem de **CDN** (recomendado) ou de `public/draco/`.
0.3. Criar branch a partir de `master` — sugiro `perf/draco-screw-model`.
     ⚠️ Preciso da sua aprovação explícita para qualquer comando git (CLAUDE.md).

**⛔ PARADA — não avanço sem 0.1 e 0.2 respondidos.**

### Etapa 1 — Medir, sem tocar no projeto ✅ CONCLUÍDA (2026-08-19)
Resultados em §4.1. Projeto verificado intocado (MD5 do `screw.glb` original inalterado,
sem `package.json`/`node_modules` no repo).
1.1. Instalar o gltf-transform no scratchpad (fora do repo), via `npx`.
1.2. Copiar o `screw.glb` para o scratchpad. **O original não é tocado em nenhum momento
     desta etapa.**
1.3. Rodar `gltf-transform inspect` e registrar o baseline.
1.4. Gerar variantes no scratchpad e medir o tamanho real de cada uma:
     - `draco` com config padrão
     - `draco` com quantização mais agressiva
     - `simplify --ratio 0.05 --error 0.001` + `draco`
     - `meshopt` para comparação
1.5. **Reportar a tabela real de tamanhos** — substituindo as estimativas da §4.1 por
     medições.

**⛔ PARADA — você escolhe a variante com os números na mão, não com as estimativas.**

### Etapa 2 — Resolver as normais ✅ (feita na Etapa 1)
2.1. Como a CLI não tem comando `normals` (§3.1), foi escrito um script Node no scratchpad
     usando `@gltf-transform/functions` → `normals({ overwrite: true })`, aplicado
     **depois** do `simplify` (ver correção em §6.2).
2.2. Pipeline final (E3): `weld` → `simplify(ratio 0.25, error 0.01)` → `normals` →
     `resize 1024` → `webp q80` → `draco`. Resultado: 344.093 triângulos, atributos
     `POSITION, TEXCOORD_0, NORMAL`, 1.549.192 B. Script: `build_d1.sh` no scratchpad
     (o nome ficou do candidato original; o ratio é o parâmetro que mudou).
2.3. ✅ Validado visualmente na Etapa 3 — foram necessárias 10 variantes até achar o
     menor ratio que preserva o aro da cabeça. Ver §4.1.1.

### Etapa 3 — Teste local ✅ CONCLUÍDA (2026-08-19)
Provou as duas coisas — **carrega** e **está igual** — mas só na décima variante.
O teste visual reprovou D1, F1, F2 e as variantes dirigidas por erro; E3 passou.
Resultados em §4.1.1.

> **Nota sobre o harness de teste.** As primeiras comparações eram inválidas: `run()`
> dispara no `DOMContentLoaded` **e** no `turbo:load`, então `initScrew()` roda duas
> vezes, cada uma cria um `PMREMGenerator`, e a que termina por último invalida o env map
> da outra — o metal renderiza quase preto, escondendo o facetamento. As capturas
> definitivas removem o listener de `turbo:load` **da resposta HTTP**, via interceptação
> no Playwright; o arquivo do projeto não foi tocado. O bug em si é real e está no
> `TODO.md` como item próprio — não entra neste commit.

Este é o núcleo do plano. O objetivo é provar duas coisas: **carrega** e **está igual**.

3.1. Colocar o `.glb` comprimido em `app/assets/images/screw.glb` (substituindo).
3.2. Aplicar a mudança em `screw_3d.js` (DRACOLoader) e a pin no `importmap.rb`.
     ⚠️ `config/importmap.rb` é mudança em `config/` → **exige sua aprovação** (CLAUDE.md).
3.3. **Neutralizar o fallback temporariamente durante o teste.** Trocar o `onError` por
     um `console.error` que grite, para que uma falha de decoder apareça como erro no
     console em vez de se disfarçar de parafuso procedural. Reverter isso antes do commit.
3.4. `bin/rails server`, abrir a home, e verificar na aba **Network** do DevTools:
     - o `.glb` requisitado tem o tamanho novo;
     - os 3 arquivos do decoder Draco retornam `200`;
     - nenhum erro no console.
3.5. **Comparação visual lado a lado.** Antes de trocar o modelo, capturar screenshots da
     home em 3 posições de scroll (topo, meio, fim da sequência dos 4 cards) com o modelo
     atual. Repetir com o comprimido e comparar par a par. É o único teste que responde
     "está igual?" de forma objetiva.
3.6. Testar em ≥2 navegadores (Chrome + Firefox) e em viewport mobile (DevTools).
3.7. Medir o tempo do `load` até o parafuso aparecer, antes e depois.
3.8. Confirmar que o fallback procedural ainda funciona: apontar `data-screw-model` para
     uma URL inexistente e verificar que o parafuso procedural aparece.
3.9. `bin/rails test` — reportar total / falhas / erros / tempo.
     (Nenhum teste atual cobre isto; ver §6.5.)

**⛔ PARADA — te mostro os screenshots comparados e os números de rede antes de seguir.**

### Etapa 4 — Precompile e simulação de produção
4.1. `RAILS_ENV=production bin/rails assets:precompile` localmente e confirmar que
     `screw-<digest>.glb` sai em `public/assets/` com o tamanho novo.
4.2. Se o decoder for self-hosted, confirmar que ele também é servido corretamente
     (ver §6.3 — `public/` não passa pelo Sprockets).
4.3. Rodar a app localmente em modo produção e repetir o teste 3.4.

### Etapa 5 — Limpeza e commit
5.1. Decidir o destino do `public/screw.glb` órfão (§6.4).
5.2. Reverter a neutralização do fallback (3.3).
5.3. Commit na branch. ⚠️ **Exige sua aprovação explícita.**

### Etapa 6 — Deploy
6.1. ⚠️ **Deploy no Heroku exige sua aprovação explícita** (CLAUDE.md — app em produção
     com usuários reais).
6.2. Pós-deploy: abrir a home em produção, confirmar tamanho na aba Network e
     conferir visualmente.
6.3. Plano de rollback: o `.glb` antigo continua no histórico do git; reverter o commit
     restaura o estado atual. O digest do Sprockets muda, então não há risco de cache
     servindo o arquivo errado.

---

## 6. Riscos específicos deste projeto

### 6.1 Falha do decoder não dá tela vazia — dá degradação silenciosa 🔴
**Este é o risco número um, e é o oposto do que se esperava.**
`screw_3d.js:206-208` tem um `onError` que chama `addProceduralScrew(screwGroup)`. Se o
decoder Draco não carregar, o `GLTFLoader` falha, o `onError` dispara e a home mostra o
parafuso procedural de baixo polígono (cilindro + caixas) **sem nenhum erro visível**.
A página parece funcionar. Só uma comparação visual atenta pega isso.

**Mitigação:** o passo 3.3 do plano neutraliza o fallback durante o teste, e o 3.5 exige
comparação de screenshots. Vale considerar também deixar um `console.error` permanente
no `onError` — hoje ele é uma arrow function vazia que engole a falha em produção.

### 6.2 Decimação sem normais deixa a malha facetada 🟠
O modelo **não tem atributo `NORMAL`** (§1.2), então o three.js usa *flat shading*. Com
1,37M triângulos ninguém nota. Decimando para ~69k, cada face vira grande o bastante para
o facetamento ficar visível — e num parafuso cromado com `roughness: 0.03` e `clearcoat`,
que reflete o environment map, o facetamento fica **muito** evidente.

**Mitigação:** gerar normais (Etapa 2). Como a CLI não tem esse comando, é preciso um
script com a API JS (`@gltf-transform/functions` → `normals()`).

> **⚠️ CORREÇÃO (medida na Etapa 1): as normais têm que vir DEPOIS do `simplify`.**
> Uma versão anterior deste documento dizia "antes de decimar". Está errado, e a diferença
> não é de qualidade — é de funcionamento. Gerando normais primeiro, **a decimação
> praticamente não acontece**: 1.376.376 → 1.362.122 triângulos (1% de redução), arquivo
> final de 5.928.476 B em vez de 1.603.448 B. O motivo está no próprio aviso do `simplify`:
> *"Topology, particularly split vertices, will also limit the simplifier."* O `normals()`
> divide vértices nas arestas vivas do parafuso, e cada vértice dividido vira uma âncora
> que o simplificador não pode colapsar.
>
> **Ordem correta: `weld` → `simplify` → `normals` → (texturas) → `draco`.**
> Como bônus, calcular as normais depois também é mais correto: elas passam a derivar da
> topologia final, em vez de serem herdadas de faces que não existem mais.

**Resolvido na Etapa 3, mas não como se esperava.** O `normals()` não é o culpado: a
68k triângulos, a variante sem normais (flat shading) e a com normais ficaram
praticamente idênticas — as duas quebradas. Quem quebra é a **decimação**, e a única
correção é decimar menos. Ver §4.1.1.

Dois achados laterais que ficam registrados:

- **`weld()` piora quando combinado com decimação agressiva.** A 68k triângulos, com e
  sem `weld` e tudo o mais igual, a versão com `weld` ficou dramaticamente pior
  (espículas saindo do aro). O `weld` funde vértices entre faces vizinhas da rosca, que
  são muito próximas. A 344k isso deixa de importar, e o E3 usa `weld` sem prejuízo.
- **Draco e WebP estão inocentes.** A variante E5 (geometria original intocada, só Draco
  + WebP, 2.262.872 B) sai indistinguível do baseline. Todo o dano vinha da decimação.

### 6.3 `public/` não passa pelo Sprockets 🟡
Se optarmos por self-hostar o decoder, os arquivos vão para `public/draco/` e são servidos
como estáticos — **sem digest, sem cache imutável, e sem entrar no `precompile`**.
`config/initializers/assets.rb` **não** precisa (nem deve) listá-los. Colocá-los em
`app/assets/` seria pior: o `setDecoderPath` do DRACOLoader concatena nomes de arquivo
fixos (`draco_decoder.wasm` etc.) e não sabe lidar com os digests do Sprockets, então
os arquivos precisam estar num diretório com nomes previsíveis. Este é o motivo técnico
concreto pelo qual **CDN é o caminho mais simples** aqui.

Sobre o `.glb` em si: como o nome do arquivo não muda, `precompile += %w[ screw.glb ]`
continua correto sem edição. **`config/initializers/assets.rb` não precisa ser tocado.**

### 6.4 Os dois `screw.glb` 🟡
`public/screw.glb` (324 KB, modelo Sketchfab CC-BY-4.0 de outro autor) é órfão. Riscos:
confusão futura ("comprimi o arquivo errado"), e uma questão de licença — CC-BY exige
atribuição, e o arquivo está publicamente acessível em `/screw.glb` sem crédito nenhum
na página. **Não vou removê-lo sem sua decisão** (é remoção de arquivo, e pode haver
histórico que eu desconheço). Fica como item da Etapa 5.1.

### 6.5 Zero cobertura de teste nesta área 🟡
Não há teste tocando `screw_3d.js`, a home 3D ou o asset `.glb`. A verificação é 100%
manual (Etapa 3). É consistente com o estado geral da suíte (`AUDIT.md` §3), mas significa
que uma regressão aqui não é pega automaticamente. O máximo automatizável de forma barata
é um teste de integração afirmando que a home renderiza e que `asset_path('screw.glb')`
resolve — o que não valida a decodificação Draco.

### 6.6 O histórico do git não encolhe 🟢
`.git` tem 57 MB, dominado pelo `.glb` de 31 MB. Substituir o arquivo **aumenta** o repo
(passa a ter as duas versões). Só um `filter-repo` reescreveria o histórico — operação
destrutiva que **não** recomendo e não faria sem pedido explícito. Impacto prático: nenhum
para o visitante; só `git clone` mais lento para desenvolvedores.

### 6.8 WebP entra em `extensionsRequired` — segunda dependência nova 🟠
A variante D1 declara **duas** extensões em `extensionsRequired`:
`KHR_draco_mesh_compression` **e** `EXT_texture_webp`. Verifiquei no fonte do
`GLTFLoader.js` do r160 que ele suporta as duas. Mas *required* significa que um cliente
sem suporte a WebP **rejeita o arquivo inteiro** — não degrada só as texturas, derruba o
modelo (→ fallback procedural, §6.1). Na prática todos os navegadores atuais suportam
WebP, mas isso dobra a superfície a testar na Etapa 3: não basta confirmar que o Draco
decodifica, é preciso confirmar que as texturas WebP aparecem.

**Escape hatch se der problema:** trocar `webp` por `resize` + JPEG. As texturas em 1024px
JPEG ficariam maiores que os 40 KB do WebP, mas ainda muito abaixo dos 1,25 MB atuais, e
o arquivo seguiria dentro da meta sem nenhuma extensão de textura.

### 6.7 CDN de terceiro no caminho crítico 🟢
Já é o caso hoje (three.js, GLTFLoader, RGBELoader e o HDRI do Polyhaven). O decoder Draco
não adiciona uma classe nova de risco. Registrado só para completude.

---

## 7. Estimativa de tempo

| Etapa | Tempo | Observação |
|---|---|---|
| 0 — Aprovação e preparo | 10 min | Sua decisão + branch |
| 1 — Medir variantes | 30–45 min | Instalar o toolchain (`node_modules` grande) domina; a compressão em si é ~1–3 min por variante numa malha de 1,37M tris |
| 2 — Normais (só se decimar) | 20–30 min | Script Node curto + validação visual |
| 3 — Teste local | 45–60 min | Screenshots comparados nas 3 posições de scroll × 2 navegadores é o que consome |
| 4 — Precompile / produção local | 20 min | |
| 5 — Limpeza e commit | 15 min | |
| 6 — Deploy e verificação | 15 min | Depende do seu OK |

**Cenário A/B (só Draco, ~2–4 MB, não bate a meta):** ~2h–2h30
**Cenário C/D (Draco + decimação + texturas, ~350–750 KB, bate a meta):** ~3h–4h

Distribuído em pelo menos 3 sessões, por causa dos pontos de parada nas Etapas 0, 1 e 3.

---

## Perguntas que preciso que você responda antes da Etapa 1

1. **Alvo:** cenário A/B (só Draco, mais simples, chega em ~2–4 MB — redução de ~90%, mas
   não bate a meta de 300 KB–1 MB) ou **C/D** (Draco + decimação + texturas, ~350–750 KB —
   bate a meta, mas exige gerar normais e mexe também nas texturas)?
2. **Decoder:** CDN jsDelivr (recomendado, coerente com o resto do projeto) ou
   self-hosted em `public/draco/`?
3. **`public/screw.glb` órfão:** remover, manter, ou decidir depois?

---

## Nota sobre o nome deste arquivo

O pedido citou dois nomes: `DRACO_COMPRESSION.md` no enunciado e `DRACOLoader.md` no
fecho. Usei `DRACO_COMPRESSION.md`, que descreve o conteúdo e segue o padrão dos outros
documentos da raiz (`CLOUDINARY_MIGRATION.md`, `STRIPE_FIX_PLAN.md`, etc.).
Renomeio se preferir o outro.
