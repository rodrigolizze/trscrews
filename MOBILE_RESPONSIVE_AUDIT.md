# Auditoria de responsividade mobile — TR Screws

**Data:** 2026-08-19
**Branch:** `master` @ `bc431a3` (produção v58)
**Escopo:** investigação apenas. **Nenhum arquivo de código, view, CSS ou config foi modificado.**
**Motivo:** Rodrigo abriu `trscrews-prod` no celular e a home aparece "sem formatação".

---

## 0. Nota de método — o que foi medido e o que foi deduzido

Ser explícito sobre isso importa, porque muda o quanto se deve confiar em cada item.

**Medido de fato (evidência dura):**
- HTML servido em **produção** (`curl` com User-Agent de iPhone) — `<head>` completo.
- CSS custom compilado, em dev e em produção (baixado e inspecionado).
- CSS do Bootstrap 5.3.0 do jsDelivr (baixado e as regras relevantes extraídas).
- Peso em bytes de **todos** os assets da home em produção (`Content-Length` real).
- Dimensões intrínsecas das imagens (`file`).

**Deduzido (leitura de CSS + regras do Bootstrap, sem renderizar):**
- Alturas e larguras resultantes a 375px.

**Não foi possível simular o viewport de 375px.** Existe Playwright em
`~/.cache/ms-playwright`, mas **nem o Chromium nem o Firefox iniciam** nesta máquina —
faltam bibliotecas de sistema:

```
chromium: error while loading shared libraries: libnspr4.so: cannot open shared object file
firefox:  XPCOMGlueLoad error ... libasound.so.2: cannot open shared object file
```

Resolver exigiria `sudo apt install libnspr4 libnss3 libasound2t64 ...`, que é mudança na
máquina e estava fora do "só investigação". **Recomendo instalar antes da fase de
correção** — sem renderizar de verdade, validar um fix de responsividade é adivinhação.
Cada achado abaixo vem marcado com o nível de confiança.

---

## 1. Como o projeto faz layout hoje

### 1.1 Framework CSS

**Bootstrap 5.3.0, via CDN (jsDelivr)** — não compilado no projeto.

`app/views/layouts/application.html.erb:20`:
```erb
<%= stylesheet_link_tag "https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css", crossorigin: "anonymous" %>
```

O `Gemfile:73` tem `gem "bootstrap", "~> 5.3.0"`, mas **essa gem não é usada para nada** —
nenhum `@import "bootstrap"` existe em `app/assets/stylesheets/`. O CSS que chega ao
navegador é o do CDN. A gem é peso morto no `Gemfile` (não é bug, é confusão em
potencial: quem for mexer em `_variables.scss` pode achar que está sobrescrevendo
variáveis do Bootstrap — não está).

Também vêm do CDN: Bootstrap Icons 1.10.5, Bootstrap JS Bundle, AOS 2.3.4 (CSS + JS),
Google Font Aldrich, e todo o `three@0.160.0`.

> Verificado: o jsDelivr responde `access-control-allow-origin: *`, então o
> `crossorigin="anonymous"` do `<link>` não bloqueia nada. O Bootstrap **carrega**.

### 1.2 Onde vive o CSS custom

`dartsass-sprockets` compilando `app/assets/stylesheets/`:

| Arquivo | Conteúdo |
|---|---|
| `application.scss` | manifest + estilos do banner/carousel da home + `#screw-3d-root` |
| `_variables.scss` | 6 cores + família de fonte |
| `_utilities.scss` | classes `.text-*-custom`, `.bg-*-custom`, `.btn-yellow`, `.section-porque-bg`, override de `.card` |
| `components/_navbar.scss` | navbar e logo |
| `components/_feature_cards.scss` | cards metálicos da seção "Por que escolher" |
| `_carousel.scss` | 6 linhas, **desativado** no `@use` (comentado) |

Total compilado: **12.556 bytes em produção**, 17.608 em dev.

**Achado colateral — o CSS sai duplicado.** O `application.scss` mantém o cabeçalho
Sprockets herdado do scaffold:

```scss
/*
 *= require_tree .
 *= require_self
 */
@use "variables" as *;
@use "utilities";
...
```

O `require_tree .` do Sprockets faz o trabalho de novo, por cima do que os `@use` do Sass
já fizeram. Medido no CSS compilado:

```
.tr-feature-card {     4 ocorrências
.navbar {              2 ocorrências
.btn-yellow {          2 ocorrências
@media (max-width:…)   6 ocorrências (são 3 regras, cada uma 2×)
```

E o `_carousel.scss` — **explicitamente desativado** (`// @use "carousel";`) — aparece
mesmo assim, na **linha 1** do arquivo compilado. O `require_tree` ignora a decisão.

Não quebra nada hoje (as regras são idênticas, a última vence), mas: (a) infla o CSS,
(b) faz "desativar um partial comentando o `@use`" não funcionar, e (c) a ordem de
cascata deixa de ser a que se lê no `application.scss`. **Relevante para a correção**:
se o fix mobile for escrito assumindo uma ordem de cascata, ela pode não valer.

### 1.3 A meta viewport existe?

**SIM — e está correta.** Não é a causa raiz.

Confirmado no HTML servido por **produção**, com User-Agent de iPhone:

```html
<meta name="viewport" content="width=device-width,initial-scale=1">
```

`app/views/layouts/application.html.erb:5`. É a única do projeto
(`grep -rn "viewport" app/ config/`).

**Portanto a hipótese principal do briefing está descartada.** O celular *não* está
renderizando como desktop encolhido. A página recebe viewport correto, recebe o Bootstrap
(CORS ok, HTTP 200), recebe o CSS custom (HTTP 200, 12.556 bytes). "Sem formatação" é
**layout quebrado**, não CSS ausente.

### 1.4 Como as páginas se estruturam

- **Home** — 4 `<section>` full-width. Carrossel de banner com 3 slides (`col-md-6`),
  seção "Por que escolher" (`col-lg-5` cards / `col-lg-7` 3D), destaques
  (`row-cols-1 row-cols-md-4`), CTA final.
- **Catálogo** (`/screws`) — filtros `col-6 col-md-2`, grid `row-cols-1 row-cols-sm-2 row-cols-lg-3`.
- **Produto** — thumbs verticais `d-none d-md-flex` + `col-12 col-lg-7` / `col-lg-5`.
- **Carrinho / checkout / pedidos** — `<table>` dentro de `.table-responsive`.
- **Login / cadastro** — `col-md-6 col-lg-5` centralizado.

**Breakpoints usados:** `sm`, `md`, `lg`. Nunca `xl`/`xxl`.

**O CSS custom tem exatamente 3 media queries** — todas em `_feature_cards.scss`
(`max-width: 992px`, `768px`, `520px`). **Nenhum outro arquivo custom tem uma única
media query.** Todo o resto — banner, navbar, logo, `#screw-3d-root`, `.section-porque-bg` —
foi escrito só para desktop. É a raiz estrutural do problema.

---

## 2. Mapa do que quebra no mobile (~375px)

Ordenado por gravidade dentro de cada página.

### 2.1 Navbar — afeta **todas** as páginas

#### 🔴 O menu principal é inacessível no celular — não existe botão hambúrguer

`app/views/shared/_navbar.html.erb:1-22`:

```erb
<nav class="navbar navbar-expand-lg" ...>
  ...
  <div class="collapse navbar-collapse justify-content-center">
    <ul class="navbar-nav ...">
      Início | Produtos | Sobre Nós | FAQ
```

Há um `.collapse.navbar-collapse`, mas **não há `.navbar-toggler`** em lugar nenhum do
projeto (`grep -rn "navbar-toggler" app/views/` → vazio).

Regras verificadas no Bootstrap 5.3.0 baixado do CDN:

```css
.collapse:not(.show){display:none}
@media (min-width:992px){ .navbar-expand-lg .navbar-collapse{display:flex!important} }
```

Abaixo de 992px o único que reexibe o menu é a media query — que não vale. Logo:
**"Início", "Produtos", "Sobre Nós" e "FAQ" ficam `display:none` sem nenhuma forma de
abrir.** Num e-commerce, o link "Produtos" some no celular.

Sobra apenas o grupo da direita (Carrinho / Entrar / Cadastrar), que não está dentro do
collapse.

**Confiança: máxima.** Regra do Bootstrap + ausência do elemento, ambas verificadas em arquivo.

#### 🔴 O logo vaza ~45px para fora da navbar e sobrepõe o conteúdo

`components/_navbar.scss`:
```scss
.navbar-brand { height: 70px; display: flex; align-items: center; padding-top: 20px; }
.navbar-logo  { height: 120px; width: auto; }
```

Uma imagem de **120px** dentro de um slot de **70px**, ainda empurrada 20px para baixo.
O logo é 1536×1024 → a 120px de altura ocupa **180px de largura**.

No desktop isso já sangra por cima do banner. No mobile fica pior: a `.navbar` do
Bootstrap é `flex-wrap: wrap`, e a soma `logo (180px) + Carrinho + Entrar + Cadastrar`
passa de 375px, então **o grupo da direita quebra para uma segunda linha — exatamente
debaixo da parte do logo que vazou.** Sobreposição.

**Confiança: alta** para o vazamento (aritmética de CSS). **Média** para a sobreposição
exata (depende da largura renderizada dos textos).

#### 🟡 O logo pesa 773 KB para ser exibido a 180×120

`logo-tr-autofix.png` = 1536×1024, **773 KB**, em **todas** as páginas.

---

### 2.2 Home

#### 🔴 Seção "Por que escolher a TR AutoFix?" — texto branco sobre fundo branco

**Este é o candidato mais forte para o "sem formatação" literal.**

`home.html.erb:71`:
```erb
<section class="py-5 section-porque-bg text-white" id="por-que-tr-autofix"
         style="background-image: url('bg_segundasection.png');">
```

`_utilities.scss:24`:
```scss
.section-porque-bg {
  background-size: 100%;       // = 100% auto → altura proporcional
  background-position: center;
  background-repeat: no-repeat;
  // nenhum background-color de fallback
}
```

A imagem é **1536×1024** (proporção 1,5:1). Com `background-size: 100%` ela cobre
`largura × (largura ÷ 1,5)`:

| Viewport | Imagem cobre | Altura estimada da seção | Coberto |
|---|---|---|---|
| Desktop 1440px | 1440 × 960 px | ~1.250 px | ~77% |
| **Mobile 375px** | **375 × 250 px** | **~2.100 px** | **~12%** |

No celular a seção fica quase **duas mil pixels de altura** e a imagem pinta só uma
faixa de **250px** no meio dela. Não há `background-color`, então o resto é o branco do
`<body>`. E a seção é `text-white`.

**Resultado: o título "Por que escolher a TR AutoFix?" e o parágrafo de apresentação —
texto branco — ficam sobre fundo branco.** Os pseudo-elementos `::before`/`::after`
pintam gradientes escuros nos 25% do topo e da base, mas eles se dissolvem em
transparente rumo ao meio — sobre branco viram cinza-claro. Contraste perto de zero.

E por que a seção fica tão alta no mobile? Porque as duas colunas empilham e **cada uma**
passa de 870px (ver 2.2.3). No desktop elas são lado a lado, a seção tem metade da
altura, e a imagem — proporcionalmente muito maior — cobre quase tudo. **É exatamente a
assinatura de "desktop certo, mobile quebrado".**

**Confiança: alta.** Aritmética direta de `background-size: 100%` sobre dimensões
medidas. A altura da seção é estimada; a *conclusão* (imagem cobre 12% vs 77%) não
depende da precisão dessa estimativa.

**Correção**: um `background-color` escuro de fallback resolve o pior (texto legível);
`background-size: cover` resolve de vez.

#### 🔴 A coluna do 3D vira um bloco de ~870px vazios acima do conteúdo

`home.html.erb:78-106`:
```erb
<div class="col-lg-5 order-2 order-lg-1" id="screw-cards-col">   <!-- 4 cards -->
<div class="col-lg-7 order-1 order-lg-2">
  <div id="screw-3d-root" class="position-sticky" style="top: 80px; min-height: 400px;">
```

`app/javascript/screw_3d.js:18`:
```js
function syncScrewHeight() {
  const h = cardsCol.offsetHeight;
  if (h > 0) { root.style.height = `${h}px`; ... camera.aspect = w / h; ... }
}
```

**A suspeita do TODO.md está correta.** No desktop as colunas são lado a lado, e igualar
a altura do 3D à dos cards é o que faz o efeito de scroll funcionar. **No mobile elas
empilham, e a regra deixa de fazer sentido:**

- 4 cards empilhados a 375px ≈ **870px** (min-height `auto` sob 768px, ~200px cada + `gap-4`).
- `syncScrewHeight()` copia isso: `#screw-3d-root` recebe **`height: 870px`**.
- `order-1` põe essa coluna **antes** dos cards → o visitante encontra **~870px de
  canvas 3D** logo abaixo do título, antes de qualquer texto útil.
- `camera.aspect = 375 / 870 = 0.43` — enquadramento vertical extremo, o parafuso
  renderiza minúsculo no meio de uma coluna estreita e altíssima.
- `position-sticky; top: 80px` num elemento **mais alto que a tela** (870 > 812): o
  sticky praticamente não gruda; rola quase como estático.
- Somando com os cards: **~1.740px** só nessa `.row`.

**Confiança: alta** no mecanismo (`syncScrewHeight` + `order-1` são fato lido em
arquivo). **Média** no número exato de 870px (estimativa a partir dos paddings do
`_feature_cards.scss`).

#### 🔴 O banner corta o próprio conteúdo — altura fixa de 420px

`application.scss:43`:
```scss
.banner-full-bleed .carousel-item { min-height: 320px; height: 420px; }
```

Altura **fixa**, sem media query. E o Bootstrap (verificado no CDN):
```css
.carousel-inner{position:relative;width:100%;overflow:hidden}
```

No mobile o slide 1 empilha (`col-md-6` → 100%) e fica com, estimando: `py-5` (96) +
`<h1 class="display-5">` em 2 linhas (~90) + `<p>` (~60) + botão (~50) + as 3 imagens
de 240px (240) ≈ **~540px** dentro de uma caixa de **420px**, com `overflow:hidden` no
pai. **Aproximadamente 120px são cortados** — na prática, as imagens do produto somem
pela metade.

#### 🔴 As 3 imagens do slide 1 somam 752px de largura em uma tela de 375px

`home.html.erb:32-35`:
```erb
<div class="col-md-6 d-flex justify-content-center gap-3">
  <% 3.times do |i| %>
    <%= image_tag "banner#{i+1}.jpeg", style: "width: 240px; height: 240px; object-fit: cover;" %>
```

`3 × 240px + 2 × 16px (gap-3)` = **752px**. Largura fixa em `style` inline, `d-flex`
sem `flex-wrap`, dentro de um container de ~343px. Com `justify-content-center` o excesso
vaza para os dois lados e é cortado pelo `overflow:hidden` do `.banner-full-bleed` +
`.carousel-inner`. **Só a imagem do meio aparece, e cortada.**

#### 🟡 Slides 2 e 3 declaram `min-height: 420px` inline, brigando com o CSS

`home.html.erb:44` e `:54` — `style="min-height: 420px"` no `.container` interno, dentro
de um `.carousel-item` que já tem `height: 420px`. Conflito de intenções sem breakpoint.

#### 🟡 Destaques: `row-cols-1 row-cols-md-4`

A 375px é 1 por linha (correto). Mas de 768px a 991px são **4 cards por linha em 768px de
largura** — ~180px cada, com carrossel + descrição + preço + botão. Apertadíssimo em
tablet. Faltou um degrau `row-cols-sm-2 row-cols-lg-4`.

#### 🔴 A home carrega ~16 MB no celular

Medido em produção, `Content-Length` real de cada asset:

| Asset | Peso |
|---|---|
| `bg_segundasection.png` | **3.313 KB** |
| `banner-tr-autofix.png` | **2.552 KB** |
| `banner-tr-autofix3.png` | **2.510 KB** |
| `banner-tr-autofix2.png` | **2.335 KB** |
| `logo-tr-autofix.png` | **773 KB** |
| **Subtotal PNG** | **≈ 11,2 MB** |
| `three.module.js` (CDN) | 1.243 KB |
| **`studio_small_03_1k.hdr` (polyhaven)** | **1.647 KB** |
| `screw.glb` | 1.513 KB |
| `draco_decoder.wasm` | 279 KB |
| GLTFLoader + DRACOLoader + RGBELoader | 129 KB |
| **Subtotal 3D** | **≈ 4,7 MB** |
| turbo + stimulus + app | ~160 KB |
| Bootstrap CSS + Icons + AOS (CDN) | ~300 KB |
| **TOTAL** | **≈ 16 MB** |

Três coisas que saltam:

1. **Os 4 PNGs de fundo (11,2 MB) são 2,3× todo o custo do 3D.** A compressão Draco
   (31 MB → 1,55 MB, v58) foi um ganho real, mas o gargalo da home hoje é outro. Todos
   são 1536×1024 servidos em tela de 375px.
2. **O HDR do polyhaven pesa 1.647 KB — mais que o próprio `.glb` (1.513 KB).** Ele não
   aparece em nenhum inventário do `DRACO_COMPRESSION.md`, e é buscado de um terceiro
   (`dl.polyhaven.org`) que não está no `importmap` nem sob nosso controle. Existe
   fallback procedural (`createProceduralEnvMap`, `screw_3d.js:34`) que custa **zero
   bytes** e já roda quando o HDR falha.
3. **Os 3 banners carregam todos.** `data-bs-ride="carousel"` faz o carrossel avançar
   sozinho, então em poucos segundos os 3 `background-image` são baixados — 7,4 MB só
   nos slides.

E o bug já registrado no TODO.md (`initScrew()` roda 2×) faz `.glb` **e** HDR serem
requisitados duas vezes: **+3,1 MB** em quem tem menos banda.

---

### 2.3 Catálogo (`/screws`)

#### 🟡 Botões do card podem vazar para fora — o `.card` teve o clipping desativado

`screws/_card.html.erb:30-51`: numa linha `d-flex` cabem preço + badge "Indisponível" +
botão "Ver" + botão "Adicionar ao carrinho". Num card de ~343px isso é justo.

E `_utilities.scss:89` desativa a proteção do Bootstrap:
```scss
.card { overflow: visible !important; }   // "allow arrows to extend outside"
```

Sem `overflow:hidden`, o excesso **não é cortado — ele vaza para fora do card**.

#### 🟡 Alvos de toque abaixo do mínimo

`btn-sm` no Bootstrap 5.3 = `padding: .25rem .5rem; font-size: .875rem` → **~31px de
altura**. As diretrizes de Apple e Google pedem 44px/48px. Vale para "Ver", "Adicionar
ao carrinho", "Remover" (carrinho) e a paginação do pagy.

#### 🟢 Filtros e grid

`col-6 col-md-2` (2 por linha no mobile) e `row-cols-1 row-cols-sm-2 row-cols-lg-3` estão
corretos. **A melhor parte responsiva do projeto** — inclusive é a única página com
`col-6` explícito para mobile.

---

### 2.4 Página de produto (`/screws/:id`)

#### 🟢 Estrutura correta

`col-12 col-lg-7` / `col-12 col-lg-5` empilha bem; thumbs desktop `d-none d-md-flex`,
thumbs mobile `d-md-none ... overflow-auto` (scroll horizontal deliberado). Tabela de
especificações em `.table-responsive`. **Foi feita com mobile em mente.**

#### 🟡 Caixa de preço + CTA pode apertar

`show.html.erb:165`: `d-flex align-items-center justify-content-between gap-3` com
`fs-3` (preço) de um lado e "COMPRAR" `px-4 py-2` do outro. Sem `flex-wrap`. Em 343px
menos os paddings do card (`p-4` = 48px) sobram ~295px — cabe justo, e "Estoque: 12 un."
embaixo do preço aumenta o risco. Merece verificação renderizada.

#### 🟡 `position-sticky` no mobile

`show.html.erb:108` — a coluna de detalhes é sticky; quando empilha o efeito é
inofensivo, mas é código sem propósito no mobile.

---

### 2.5 Carrinho (`/cart`)

#### 🟡 Tabela de 5 colunas → scroll horizontal

`.table-responsive` está lá (bom — não vaza para a página), mas o conteúdo mínimo é
5 colunas: imagem 72px + descrição + `<th style="width:140px">` com input de 90px e botão
"Atualizar" + preço + total + "Remover". Fácil passar de 600px, o que significa **rolar
lateralmente dentro da tabela para chegar no botão "Remover"**. Um layout de cards
empilhados é o padrão de e-commerce mobile aqui.

#### 🟡 Bug de markup no `tfoot`

`carts/show.html.erb`: o `<thead>` declara **5** `<th>`, mas todas as linhas do `<tfoot>`
somam **4** células (`colspan="3"` + 1, e `colspan="4"` na barra de frete grátis).
Subtotal / Frete / Total ficam desalinhados da coluna "Total" do corpo. Pré-existente,
visível também no desktop.

#### 🟡 Botões de ação sem `flex-wrap`

`carts/show.html.erb:110`: `d-flex gap-2` com "Continuar comprando" + "Esvaziar" +
"Finalizar compra" (`ms-auto`). Três botões de largura normal em 343px. Sem
`flex-wrap`, eles comprimem ou vazam. **"Finalizar compra" é o CTA mais importante do
site** — vale checar renderizado.

---

### 2.6 Login / Cadastro

#### 🟢 Corretos

`container my-5` → `row justify-content-center` → `col-md-6 col-lg-5`. Abaixo de `md`
ocupa 100%. `card-body p-4 p-md-5` (padding menor no mobile — bem feito), campos
`form-control` full-width, botão em `d-grid` (largura total). **As telas mais bem
adaptadas do projeto.** Mesma estrutura em `registrations/new.html.erb`.

Único senão: herdam a navbar quebrada (2.1) — o usuário loga e não tem como navegar.

---

### 2.7 Resumo

| Página | Estado no mobile |
|---|---|
| **Home** | 🔴 Quebrada em 4 frentes independentes |
| Navbar (todas) | 🔴 Menu inacessível + logo sobrepondo |
| Catálogo | 🟡 Grid ok; risco de vazamento nos botões do card |
| Produto | 🟢 Bom; um ponto a verificar |
| Carrinho | 🟡 Usável com scroll lateral; `tfoot` desalinhado |
| Login / Cadastro | 🟢 Bom |

---

## 3. A causa raiz mais provável

### A meta viewport **está presente e correta** — hipótese descartada

Verificado no HTML de **produção**, com UA de iPhone. O Bootstrap carrega (HTTP 200,
CORS ok), o CSS custom carrega (HTTP 200, 12.556 bytes). Nada disso é a causa.

### A causa raiz é: **o CSS custom foi escrito só para desktop**

Não é um bug — são **três decisões de layout com valores fixos** que funcionam numa tela
larga e deixam de funcionar numa estreita, agravadas por uma quarta que só existe no
mobile:

| # | Decisão | Por que funciona no desktop | Por que quebra no mobile |
|---|---|---|---|
| 1 | `.section-porque-bg { background-size: 100% }` sem `background-color` | imagem cobre ~77% de uma seção de ~1.250px | cobre ~12% de uma seção de ~2.100px → **texto branco sobre branco** |
| 2 | `syncScrewHeight()` copia a altura dos cards para o 3D | colunas lado a lado, alturas iguais é o objetivo | colunas empilham → **~870px de canvas antes do conteúdo** |
| 3 | `.carousel-item { height: 420px }` + imagens `width:240px` | conteúdo em 2 colunas cabe em 420px | empilha para ~540px → **corte**; 3×240px = **752px em 375px** |
| 4 | `.navbar-expand-lg` **sem** `.navbar-toggler` | ≥992px o menu é sempre visível | <992px `display:none` **sem forma de abrir** |

**O que provavelmente o Rodrigo viu como "sem formatação":** o item 1. Um bloco enorme
de branco onde deveria haver um título e um texto de apresentação — porque o texto
*está lá*, branco sobre branco. Somado ao item 2 (~870px de canvas 3D) logo abaixo, o
efeito é uma página que parece ter perdido o CSS, quando na verdade ela está pintando
exatamente o que foi pedido: fundo branco, letra branca.

**Evidência estrutural que amarra tudo:** o CSS custom inteiro tem **3 media queries**,
todas no mesmo arquivo (`_feature_cards.scss`). Banner, navbar, logo, `#screw-3d-root` e
`.section-porque-bg` — os cinco pontos que quebram — **não têm nenhuma**.

---

## 4. O parafuso 3D no mobile

### 4.1 Vale carregar?

**Não como está.** O custo medido:

| Item | Peso |
|---|---|
| `three.module.js` | 1.243 KB |
| `studio_small_03_1k.hdr` | **1.647 KB** |
| `screw.glb` | 1.513 KB |
| `draco_decoder.wasm` | 279 KB |
| 3 loaders | 129 KB |
| **Total** | **≈ 4,7 MB** — **9,4 MB** com o bug do init 2× |

Além dos bytes: descompressão Draco de 344k triângulos, geração de PMREM a partir de um
HDR, e um `requestAnimationFrame` rodando **continuamente** (`animate()` nunca pausa) —
com `antialias: true` e `pixelRatio` até 2. Num celular médio isso é bateria e calor.

**E o retorno no mobile é negativo**, porque o layout está errado: coluna estreita e
altíssima (aspect 0,43), parafuso minúsculo, empurrando ~870px o conteúdo que
efetivamente vende.

**Um detalhe que merece atenção:** o HDR (1.647 KB) é o **maior item isolado do 3D** —
maior que o `.glb` que custou uma sessão inteira de compressão. Ele vem de
`dl.polyhaven.org`, terceiro fora do `importmap`. E já existe um fallback procedural
(`createProceduralEnvMap`, `screw_3d.js:34`) que custa **zero bytes** e roda hoje quando
o HDR falha — ou seja, o caminho barato já está implementado e testado.

### 4.2 `syncScrewHeight()` funciona quando as colunas empilham?

**Não.** Ele *roda* corretamente — não lança erro, o `ResizeObserver` dispara. O problema
é que a **premissa** é falsa: a função existe para casar a altura de duas colunas
**lado a lado**. Quando elas empilham, casar as alturas significa "reserve para o canvas
a mesma altura que os cards ocupam", o que produz ~870px de canvas.

Não há nenhuma verificação de largura de tela em `screw_3d.js` — nem em `syncScrewHeight`,
nem em `initScrew`, nem em `run()`.

### 4.3 Opções

| Opção | Ganho | Risco | Trabalho |
|---|---|---|---|
| **A. Não inicializar abaixo de `lg` (992px)** | −4,7 MB, −CPU, −870px | Nenhum no desktop (guard em `run()`) | ~10 linhas |
| **B. Manter, mas com altura própria no mobile** | Mantém o efeito visual | Continua 4,7 MB em quem tem menos banda | ~15 linhas |
| **C. Imagem estática (WebP) no mobile** | −4,6 MB, mantém o visual | Precisa gerar e versionar o render | ~30 min + asset |
| **D. Carregar sob interação ("ver em 3D")** | −4,7 MB no carregamento | Mais complexo; quase ninguém clica | ~1h |
| **E. Manter como está** | — | Perde o visitante | 0 |

**Recomendo A agora e C depois.** A é a menor mudança com o maior efeito imediato: uma
guarda de `window.matchMedia("(min-width: 992px)")` em `run()`, e no HTML/CSS a coluna
do 3D vira `d-none d-lg-block`. O desktop não é tocado. C é a versão bonita, mas exige
gerar o render e não deve bloquear o conserto.

**Independente da opção**, vale trocar o HDR pelo `createProceduralEnvMap` já existente:
−1.647 KB **no desktop também**, sem código novo.

---

## 5. Plano de correção proposto (priorizado)

Ordenado por **resultado ÷ risco**. Cada fase é isolável e deployável sozinha.

### Fase 1 — Fazer a home ficar legível (risco baixíssimo, resultado enorme)

| # | Mudança | Arquivo | Risco |
|---|---|---|---|
| 1.1 | `background-color` escuro de fallback em `.section-porque-bg` + `background-size: cover` sob `lg` | `_utilities.scss` | **Muito baixo** — resolve texto-branco-sobre-branco |
| 1.2 | Adicionar `.navbar-toggler` com `data-bs-toggle="collapse"` | `shared/_navbar.html.erb` | **Baixo** — só aparece <992px |
| 1.3 | Não inicializar o 3D abaixo de 992px (guard em `run()` + `d-none d-lg-block` na coluna) | `screw_3d.js`, `home.html.erb` | **Baixo** — desktop intocado; −4,7 MB |
| 1.4 | `height: 420px` → `height: auto; min-height: 420px` abaixo de `lg` | `application.scss` | **Baixo** — para o corte do banner |
| 1.5 | Imagens do slide 1: `width: 240px` inline → classe com `max-width` + `flex-wrap` (ou `d-none d-md-flex`) | `home.html.erb` | **Baixo** — elimina os 752px |

Depois da Fase 1 a home fica legível e a navegação volta a funcionar. É o que resolve
o problema relatado.

### Fase 2 — Peso (risco baixo, efeito grande em 4G)

| # | Mudança | Ganho |
|---|---|---|
| 2.1 | Trocar o HDR do polyhaven pelo `createProceduralEnvMap` já existente | **−1.647 KB**, desktop incluído |
| 2.2 | Converter os 4 PNGs de fundo para WebP e reduzir para ~1024px | **−8 a −9 MB** |
| 2.3 | Redimensionar/converter o logo (773 KB → ~20 KB) | **−750 KB** em todas as páginas |
| 2.4 | Fechar o `initScrew()` 2× (já está no TODO.md) | −1,5 MB de `.glb` + −1,6 MB de HDR |
| 2.5 | Avaliar trocar `bg_segundasection.png` por gradiente CSS (já no TODO.md) | −3,3 MB |

> 2.2 e 2.3 já constam no TODO.md como "Otimização de assets binários (futuro)". Esta
> auditoria mostra que **não é futuro** — 11,2 MB de PNG é o maior item da home.

### Fase 3 — Navbar e logo

| # | Mudança |
|---|---|
| 3.1 | `.navbar-logo { height: 120px }` → altura responsiva, dentro do slot do brand |
| 3.2 | Corrigir o `.navbar-brand { height: 70px }` para conter o logo |
| 3.3 | Remover os `style="background-color: $color-secondary"` inline (`_navbar.html.erb:1,56`) — é sintaxe SCSS em HTML, o navegador descarta |

### Fase 4 — Catálogo e carrinho

| # | Mudança |
|---|---|
| 4.1 | Rever `.card { overflow: visible !important }` — hoje deixa conteúdo vazar |
| 4.2 | `btn-sm` → `btn` nos CTAs de mobile (alvo de toque ≥44px) |
| 4.3 | Carrinho: cards empilhados no lugar da tabela abaixo de `md` |
| 4.4 | Corrigir o `colspan` do `<tfoot>` (5 colunas no `thead`, 4 no `tfoot`) |
| 4.5 | `flex-wrap` nos botões de ação do carrinho |
| 4.6 | Destaques: `row-cols-1 row-cols-sm-2 row-cols-md-3 row-cols-lg-4` |

### Fase 5 — Higiene (não bloqueia nada)

| # | Mudança |
|---|---|
| 5.1 | Remover `*= require_tree .` do `application.scss` — hoje duplica todo o CSS e ressuscita o `_carousel.scss` desativado |
| 5.2 | Decidir sobre `gem "bootstrap"` no Gemfile — não é usada (o CSS vem do CDN) |

### Pré-requisito de método

**Antes da Fase 1: instalar as libs do Playwright** (`libnspr4`, `libnss3`,
`libasound2t64`) para poder renderizar a 375px e validar antes/depois com captura de tela.
Sem isso, cada correção é uma hipótese não testada. É a mesma lição do
`DRACO_COMPRESSION.md`: a estimativa de "~300KB sem perda visual" **estava errada** e só
caiu medindo 10 variantes.

---

## 6. Riscos — não quebrar o desktop que funciona

### O que protege

1. **Mobile-first por adição, não por substituição.** Toda regra nova entra em
   `@media (max-width: 991.98px)`. O desktop não recebe uma declaração diferente do que
   recebe hoje. Vale para 1.1, 1.4, 1.5.

2. **O 3D some do mobile por guarda, não por reescrita.** Um `if` em `run()` — o caminho
   de código do desktop é byte-a-byte o mesmo. Não mexer em `initScrew()`, `animate()`
   nem no `IntersectionObserver`.

3. **O `.navbar-toggler` é invisível ≥992px** por regra do próprio Bootstrap
   (`.navbar-expand-lg .navbar-toggler{display:none}`, verificada no CDN). Adicionar o
   botão é aditivo puro.

### O que exige cuidado

| Risco | Por quê | Mitigação |
|---|---|---|
| **A cascata do CSS não é a que se lê** | `require_tree .` duplica tudo e a ordem final não é a do `application.scss` | Fazer 5.1 **antes** de escrever media query nova, ou conferir o CSS compilado depois de cada mudança |
| **`background-size: cover` recorta a arte** | `cover` preenche, mas corta as bordas — o desenho de `bg_segundasection.png` pode ter elemento importante na borda | Aplicar `cover` **só abaixo de `lg`**; olhar renderizado |
| **`height: auto` no `.carousel-item` desalinha os slides** | Slides de alturas diferentes fazem o carrossel "pular" na transição | Usar `min-height` em vez de `height` livre, e testar os 3 slides |
| **`syncScrewHeight` mexe em `camera.aspect`** | Alterar quando o 3D inicializa muda quando o `ResizeObserver` é registrado | Se o 3D não inicializar no mobile, `heightObserver` também não deve — e a rotação de tela (portrait→landscape ≥992px) precisa de teste |
| **`.card { overflow: visible !important }` foi deliberado** | O comentário diz *"allow arrows to extend outside"* — as setas do carrossel do card | Não remover às cegas; se remover, conferir os cards de destaque da home |
| **Regressão nos 24 testes atuais** | Baseline `bin/rails test`: 24 runs / 64 assertions | Rodar depois de **cada** fase. A suíte não cobre layout — o teste real é visual |
| **`AOS.init()` roda sem `data-aos` em lugar nenhum** | `grep` não acha nenhum `data-aos` nas views; a lib é carregada e inicializada à toa | Não tocar nesta rodada — é higiene, não responsividade |
| **Deploy** | Produção tem usuários reais | Uma fase por release, validando no celular do Rodrigo entre elas. **CLAUDE.md: sem deploy sem aprovação explícita.** |

### Classificação segundo o CLAUDE.md

- **Fase 1 (1.1, 1.4, 1.5), Fase 3, Fase 4** — ajustes de CSS/HTML em views: **menores**.
- **1.2 (navbar-toggler)** — muda estrutura compartilhada por todas as páginas: apresentar antes.
- **1.3, 2.1, 2.4 (`screw_3d.js`)** — mudança de comportamento em JS: **apresentar abordagens**.
- **2.2, 2.3, 2.5 (assets binários)** — reescrevem arquivos versionados: **aprovação**.
- **5.1 (`require_tree`)** — mexe no manifest do pipeline: **aprovação**.
- **5.2 (Gemfile)** — remover gem: **aprovação explícita** (CLAUDE.md, regra de gems).

---

## 7. Ampliação — o funil de compra no mobile (2026-08-20)

A auditoria original (§2) focou a home, e as páginas do funil ficaram com análise
qualitativa: "fácil passar de 600px", "cabe justo", "merece verificação renderizada".
Esta seção **quantifica** esses pontos e cobre o que faltava — em especial o
**checkout (`/orders/new`), que não tinha seção nenhuma** apesar de ser o passo mais
crítico do funil.

Contexto: home já corrigida e no ar (v60, Fases 1 e 3). Fase 2 (peso dos PNGs) foi
**deliberadamente pulada** — as artes de fundo são de teste e serão trocadas pelas
oficiais; comprimir agora seria retrabalho.

### 7.0 Método e orçamento de largura

Todas as contas assumem **viewport de 375px** (iPhone SE/12 mini, o mais estreito
comum) e as regras do Bootstrap 5.3 conferidas em arquivo:

| camada | conta | largura útil |
|---|---|---|
| viewport | — | 375px |
| `.container` (<576px) | `width:100%` + `padding-inline: 12px` | **351px** |
| `.row` + `.col` | margem `-8/-12px` cancela o padding `8/12px` do col | **351px** |
| `.card-body` (`p-3`/1rem) | −16px de cada lado | **319px** |
| `.card-body p-4` (1.5rem) | −24px de cada lado | **303px** |

Larguras de texto estimadas com a fonte real do site (**Aldrich**, `body` em
`application.scss:25`), que é notavelmente larga: ~8px/caractere a 14px, ~9px a 16px.
Onde a estimativa decide o veredito, marco **Confiança: média** — é o mesmo critério
do §0.

**Não executado:** renderização real a 375px. Playwright continua sem iniciar nesta
máquina (§Apêndice). Tudo abaixo é aritmética de CSS sobre as classes das views.

---

### 7.1 Catálogo (`/screws`) — complementa §2.3

#### 🔴 A linha de ação do card estoura o orçamento — e o `.card` deixa vazar

`screws/_card.html.erb:30-51`. Card = 351px, `.card-body` (1rem) → **319px de
orçamento**. A linha é `d-flex justify-content-between`, **sem `flex-wrap`**:

| cenário | conteúdo | soma | veredito |
|---|---|---|---|
| em estoque | preço ~99 + "Ver" ~42 + gap 8 + "Adicionar ao carrinho" ~186 | **~335px** | estoura ~16px |
| sem estoque | preço ~99 + badge "Indisponível" ~98 + gap 8 + "Ver" ~42 + gap 8 + "Adicionar" ~90 | **~345px** | estoura ~26px |

E `_utilities.scss:110` desativa o clipping do Bootstrap:
```scss
.card { overflow: visible !important; } // allow arrows to extend outside
```
Sem `overflow:hidden`, o excedente **não é cortado — vaza para fora da borda do card**.

**"Adicionar ao carrinho" é o botão de conversão do catálogo.** É o achado de maior
impacto comercial desta ampliação.

**Confiança: média** — o veredito depende da métrica da Aldrich. Mas os dois cenários
estouram, e o de estoque zerado estoura com folga; um erro de 10% na estimativa não
inverte a conclusão.

#### 🔴 20 cards por página × ~483px = ~10.000px de rolagem

`config/initializers/pagy.rb:11-13` documenta que o `DEFAULT[:items] = 12` morreu na
migração para pagy 9 (`:items` → `:limit`) e **o catálogo caiu no default de 20**.

Altura de um card a 375px:

| parte | altura |
|---|---|
| `.ratio.ratio-1x1` a 351px de largura | **351px** |
| `.card-body`: padding 32 + spec ~17 + descrição ~44 (2 linhas) + `mb-2` 8 + linha de ação ~31 | ~132px |
| **total** | **~483px** |

20 × 483 + 19 gaps de 16px ≈ **9.960px**. Num viewport de 667px de altura são
**~15 telas de rolagem** para uma página de catálogo — e o produto do fim da página
custa 15 swipes.

A imagem 1:1 responde por **73% da altura do card**. É o parâmetro a mexer.

#### 🟡 Correção ao §2.3: os filtros não estão 🟢 em `md`

A auditoria classificou os filtros como "a melhor parte responsiva do projeto".
No **mobile isso se sustenta** (`col-6` = 2 por linha, correto). Mas a soma das
colunas Bootstrap passa de 12:

`col-md-4` (busca) + 5 × `col-md-2` (montadora, modelo, rosca, tratamento, ordenar)
= **4 + 10 = 14 colunas** num grid de 12.

Em `md` (768-991px, tablets em retrato) a linha quebra e sobram 2 colunas órfãs.
Não afeta 375px — mas o 🟢 do §2.3 é generoso demais.

#### 🟡 Paginação do pagy

`pagy_bootstrap_nav` gera `.page-link` com `padding: .375rem .75rem` → ~38px de altura,
abaixo dos 44px. Mesma família do problema de alvo de toque (§2.3), no fim de 10.000px
de rolagem.

---

### 7.2 Página de produto (`/screws/:slug`) — complementa §2.4

Confirmo o 🟢 estrutural do §2.4: `col-12 col-lg-7` / `col-12 col-lg-5`, thumbs desktop
`d-none d-md-flex`, thumbs mobile `d-md-none ... overflow-auto`, specs em
`.table-responsive`. **Foi a página feita com mais cuidado mobile do projeto.**

#### 🟡 Caixa de preço + CTA — o §2.4 pediu número, aqui está

`show.html.erb:165`. A caixa é `p-3` dentro de `.card-body.p-4` dentro do col:
351 − 48 (`p-4`) − 32 (`p-3`) = **271px de orçamento**, `d-flex justify-content-between
gap-3`, **sem `flex-wrap`**:

- preço `fs-3` (1.75rem = 28px): "R$ 1.234,56" ≈ **~150px**
- botão "COMPRAR" `px-4 py-2` ≈ **~120px**
- `gap-3` = 16px

Soma ≈ **286px em 271px** → estoura ~15px. Com preço de 4 dígitos ("R$ 12.345,67")
passa de 300px.

Atenuante real: o bloco da esquerda é uma `<div>` com "Estoque: 12 un." embaixo, e
flex items encolhem por padrão (`min-width:auto` só trava no conteúdo mínimo) — então
o mais provável é **compressão feia**, não vazamento. Ainda assim é o CTA da página.

**Confiança: média.**

#### 🟢 `position-sticky` no mobile — inofensivo, confirmado

`show.html.erb:108`. Quando a coluna empilha, o sticky não tem o que grudar dentro do
próprio col. Código sem propósito no mobile, sem efeito colateral. Não priorizar.

---

### 7.3 Carrinho (`/cart`) — quantifica §2.5

#### 🔴 A tabela precisa de ~800px num viewport de 375px

`carts/show.html.erb:9-107`. `.table-responsive` está lá (bom — não vaza para a
página), mas transforma o problema em **rolagem lateral**. Largura mínima por coluna:

| coluna | conteúdo | mínimo |
|---|---|---|
| Produto | thumb 72px + `gap-3` 16px + descrição (~180px antes de quebrar feio) | ~268px |
| Quantidade | `number_field` `width:90px` + `gap-2` 8px + botão "Atualizar" ~95px | **~193px** |
| Preço | `format_price` | ~85px |
| Total | `format_price` em `<strong>` | ~85px |
| (Remover) | `btn-sm btn-outline-danger` | ~85px |
| padding das células | `.table` usa `.5rem` → 5 col × 16px | 80px |
| **total** | | **~796px** |

**Razão: 2,1× a largura da tela.** O `<th style="width:140px">` da Quantidade é
inócuo — o conteúdo do `<td>` (input 90 + gap + botão) força ~193px de qualquer forma.

Consequência prática: para ver o **Total** da linha ou apertar **Remover**, o usuário
precisa rolar a tabela para o lado — um gesto que a maioria não descobre, porque não
há indicação visual de que há mais conteúdo à direita.

Cards empilhados abaixo de `md` é o padrão de e-commerce mobile aqui (já é o item
**4.3** do plano no §5).

#### 🟡 Botões de ação sem `flex-wrap` — número

`carts/show.html.erb:110`: `d-flex gap-2` com "Continuar comprando" (~200px),
"Esvaziar" (~110px) e "Finalizar compra" (`ms-auto`, ~190px) = **~516px em 351px**.
Sem `flex-wrap`, os três comprimem. **"Finalizar compra" é o CTA mais importante do
site** e vai chegar espremido.

#### 🟡 Correção ao §2.5: o `tfoot` não desalinha os totais

O §2.5 afirma que Subtotal/Frete/Total "ficam desalinhados da coluna Total". Conferindo
a marcação: `<colspan=3>` cobre Produto+Quantidade+Preço e o `<th>` seguinte cai na
**4ª coluna, que é exatamente "Total"**. O que falta é a 5ª célula (a de "Remover"),
então as linhas do `tfoot` têm 4 células num corpo de 5 colunas.

É marcação incompleta — não desalinhamento. Continua valendo corrigir (item 4.4 do
plano), mas **como higiene de HTML, não como bug visual**. Rebaixar a prioridade.

---

### 7.4 Checkout (`/orders/new`) — **seção nova, não existia na auditoria**

O passo mais crítico do funil não tinha análise. `orders/new.html.erb`, 243 linhas,
`col-lg-7` (resumo) + `col-lg-5` (formulário) — empilham abaixo de `lg`, resumo primeiro.

#### 🔴 CEP sem `inputmode` no cadastro de endereço — teclado errado

Este é o achado mais barato de consertar e o mais irritante de sofrer.

`orders/new.html.erb:143-154` faz **certo**:
```erb
inputmode: "numeric", autocomplete: "postal-code", pattern: "\\d{5}-\\d{3}", maxlength: 9
```

`shipping_addresses/_form.html.erb:33-41` — o mesmo campo CEP, alcançável pelo botão
"Novo endereço" **de dentro do próprio checkout** (`orders/new.html.erb:70`) — não tem
**nenhum** dos quatro:
```erb
<%= f.text_field :cep, class: "form-control", placeholder: "00000-000", maxlength: 9, ... %>
```

No celular, `text_field` sem `inputmode` abre o **teclado alfabético** para um campo de
8 dígitos. O usuário precisa trocar para o numérico manualmente, num formulário de
entrega. Sem `autocomplete="postal-code"`, o preenchimento automático do navegador
também não dispara.

A máscara em si funciona nos dois: `cep_controller.js:32-36` liga o listener direto no
elemento no `connect()`, então não depende do `data-action` — por isso o
`input->cep#mask` ausente no `_form` não quebra nada. **É só o teclado.**

Mesma falta em "Número" (`orders/new.html.erb:166` e `_form:54`): campo numérico,
teclado alfabético.

**Confiança: máxima** — ausência de atributo, verificada em arquivo.

#### 🟡 A tabela do resumo também rola (~544px)

`orders/new.html.erb:9-58`, 4 colunas: Produto (thumb 64 + gap 16 + descrição ~180) +
Qtd ~50 + Preço ~85 + Total ~85 + padding 64 = **~544px em 351px** → **1,5× a tela**.

Menos grave que o carrinho (§7.3) porque aqui não há botão a alcançar — é só leitura.
Mas o usuário chega ao checkout e a primeira coisa que vê é uma tabela cortada.

#### 🟡 Linha de totais sem `flex-wrap` — e o rótulo do frete é variável

`orders/new.html.erb:215-229`: `d-flex justify-content-between` com três blocos, dentro
de `.card-body.p-4` → **303px de orçamento**. Sem `flex-wrap`, sem `gap`:

- "Subtotal" + valor ≈ 70px
- "Frete (SP – Sudeste)" + valor ≈ **~140px** ← rótulo montado em runtime (linha 222)
- "Total" + valor `h5` ≈ 90px

Soma ≈ **300px em 303px**. Passa raspando com "Sudeste"; com **"Centro-oeste"** (a
região mais longa da lista) o rótulo cresce ~20px e a linha estoura.

É o resumo financeiro imediatamente acima do botão "Confirmar pedido". Quebrar ali
custa confiança no pior momento possível.

#### 🟢 O que está certo no checkout

- `d-grid` no "Confirmar pedido" (`:231`) → botão de largura total, alvo de toque bom
- pares `col-6`/`col-6` (Número/Complemento, Bairro/Cidade) → ~168px cada em 375px,
  apertado mas usável para campos curtos
- lista de endereços em `.list-group` → empilha nativamente

---

### 7.5 Endereços (`/shipping_addresses`)

#### 🟡 Rodapé do card com 3 botões sem `flex-wrap`

`shipping_addresses/index.html.erb:30-48`: `card-footer d-flex gap-2` com "Editar"
(~65px), "Tornar padrão" (~135px) e "Excluir" (~80px, `ms-auto`) = **~296px** de
orçamento **319px**. Cabe — mas sem margem, e o `button_to` de "Tornar padrão" gera um
`<form>` que vira flex item.

Os três são `btn-sm` → **~31px de altura**, abaixo dos 44px.

#### 🟢 O formulário empilha certo

`_form.html.erb` usa só `col-md-*` → abaixo de 768px tudo vira largura total. Estrutura
correta; o problema é o `inputmode` (§7.4).

---

### 7.6 Login / Cadastro — confirmado 🟢

Reli `devise/sessions/new.html.erb` e `devise/registrations/new.html.erb`. O §2.6 está
certo e **nada mudou**: `col-md-6 col-lg-5` (100% abaixo de `md`), `card-body p-4 p-md-5`
(padding menor no mobile — deliberado), campos `form-control` full-width, botão
`btn-lg` em `d-grid` (~48px de altura, **o único alvo de toque do funil que passa dos
44px por desenho**).

**São as telas mais bem adaptadas do projeto.** Não priorizar.

Dois pontos não-responsivos, registrados de passagem:
- copy diz "TR AutoParts" (`sessions/new:11`, `registrations/new:11`, `_footer:7`) —
  é o rebrand para **TR AutoFix**, já separado como tema próprio
- `sessions/new_old.html.erb` e `registrations/new_old.html.erb` são views mortas

---

### 7.7 Os 4 cards da home ("Por que escolher") — item 3 do pedido

Medi antes de opinar, porque a impressão do print ("cada um ocupa quase a tela toda")
**não se confirma**.

#### Como estão estruturados

`home.html.erb:79-101`: os 4 cards ficam num `col-lg-5`, empilhados por
`<div class="d-flex flex-column gap-4">` — **não** pelo `.tr-feature-grid`.

Cada card é `shared/_feature_card.html.erb` → `.tr-feature-card` (SVG de check + título
+ texto), estilizado em `components/_feature_cards.scss` (236 linhas).

#### 🟢 Já têm três níveis de responsividade

`_feature_cards.scss` tem breakpoints em **992px, 768px e 520px**, reduzindo padding,
ícone (78 → 62 → 56px), título (2,1 → 1,65 → 1,42rem) e texto (1 → 0,98 → 0,92rem), e
soltando o `min-height: 230px` para `auto` abaixo de 768px.

**É o arquivo mais bem adaptado do projeto** — ironicamente, o único que a auditoria
original acusou de ser desktop-only por associação (§3).

#### Altura real medida a 375px

Card = 351px de largura (col) → `padding: 20px 18px` (≤768px) → `__content` com
`padding: 18px 14px 22px` (≤520px) → sobram 263px, dos quais o ícone toma 56 + 12 de gap:

| parte | altura |
|---|---|
| título 1,42rem, 2 linhas (`<br>` explícito no `home.html.erb`) | ~46px |
| margem do título | 10px |
| texto 0,92rem, ~2 linhas em 195px | ~38px |
| corpo = max(ícone 56, texto 94) | 94px |
| paddings (20+18 topo, 22+20 base) | 80px |
| **card** | **~174px** |

4 cards × 174 + 3 gaps de 24px = **~768px**.

**Veredito: um card ocupa ~26% da tela (174px de 667px), não "quase a tela toda".**
O que pesa é o conjunto — 768px, ~1,15 tela — mais o `py-5` da seção. Compactar mais um
card individual rende pouco; o ganho estaria em **2 colunas**, e aí o título de 1,42rem
em ~130px de largura quebraria feio. **Não vale mexer agora.**

#### 🟡 Achado lateral: `.tr-feature-grid` é CSS morto

`_feature_cards.scss:148-162` define um grid de 2 colunas com fallback para 1 abaixo de
992px. `grep -rn "tr-feature-grid" app/views/` → **vazio**. Nunca foi ligado em view
nenhuma. São 15 linhas de CSS (**× 4** pelo `require_tree` — ver §7.9) que nunca pintam pixel.

Higiene, não responsividade.

---

### 7.9 Filtros do catálogo — medição e correção (aplicada em `afb5b46`)

**Não estão quebrados** — `col-6` põe dois por linha e os `select` nativos abrem o
seletor do sistema. O problema é **custo de espaço**.

Métricas extraídas do `bootstrap.min.css` do CDN (232.914 bytes), não estimadas:
`.form-label{margin-bottom:.5rem}`, `.form-control`/`.form-select` = `.375rem` +
`line-height:1.5` + borda → **38px**, `.g-2{--bs-gutter-y:.5rem}`.

Cada campo custa **67px** (label 21 + margem 8 + controle 38). Os 6 campos empilham em
4 linhas (busca `col-12`; 5 selects `col-6` → 2+2+**1 sozinho**, sobra ímpar) + linha de
botões 38px + gutters 32px + `.mb-4` 24px = **362px**.

| | antes | depois |
|---|---|---|
| altura antes do 1º produto (24 `py-4` + 50 `h1` + bloco) | **436px** | **128px** |
| sobra na 1ª tela (667 − ~90 navbar = 577px) | 141px | **449px** |
| do 1º card (483px) aparece | **29%** | **93%** |

**Correção:** form envolvido em `.collapse.d-lg-block` atrás de botão "Filtrar e
ordenar" (`.d-lg-none`) com badge de filtros ativos. Desktop intocado —
`.d-lg-block{display:block!important}` vence `.collapse:not(.show){display:none}`
(especificidade 0,2,0, sem `!important`). Form byte-a-byte idêntico (sha256
`7e206ad433072ecd` antes e depois); `display:none` não remove campo de submit.

**Não inverter a ordem do DOM** foi decisão deliberada: botão de filtro depois dos
produtos faz o usuário rolar ~10.000px (§7.1) sem descobrir que dá para filtrar.

#### Correção ao §5.1: a duplicação é ×4 para partials, não ×2

Contagem no `application.css` compilado:

| origem | ocorrências |
|---|---|
| partial `_utilities.scss` (`.text-title-custom`) | **4** |
| partial `components/_navbar.scss` (`navbar-logo`) | **4** |
| escrita direto em `application.scss` (`por-que-tr-autofix`) | **1** |

O que vem de partial é multiplicado por 4; o que é escrito no manifesto sai uma vez.
O §5.1 e o Apêndice dizem "× 2" — subestimam o efeito pela metade.

---

### 7.8 Achados priorizados — impacto no funil primeiro

Ordem por **dano à venda**, não por esforço.

| # | Achado | Onde | Impacto | Confiança |
|---|---|---|---|---|
| **P0-1** | Linha de ação do card estoura 319px (~335 em estoque, ~345 sem) e **vaza**, porque `.card{overflow:visible!important}` | `screws/_card.html.erb:30-51` + `_utilities.scss:110` | botão **"Adicionar ao carrinho"** deformado no catálogo | média |
| **P0-2** | CEP sem `inputmode`/`autocomplete`/`pattern` → **teclado alfabético** para 8 dígitos | `shipping_addresses/_form.html.erb:33-41` (checkout já faz certo) | atrito direto no **cadastro de entrega**, alcançável de dentro do checkout | **máxima** |
| **P0-3** | Tabela do carrinho precisa de **~796px** (2,1× a tela) → rolagem lateral para ver Total e alcançar "Remover" | `carts/show.html.erb:9-107` | último passo antes do checkout | alta |
| **P0-4** | Alvos de toque `btn-sm` ≈ **31px** (<44px) em 11 pontos do funil | catálogo, carrinho, checkout, endereços | erro de toque em botões de compra | **máxima** |
| **P1-5** | Botões do carrinho somam ~516px em 351px sem `flex-wrap` — **"Finalizar compra"** espremido | `carts/show.html.erb:110` | CTA principal do site | alta |
| **P1-6** | Linha de totais do checkout: ~300px em 303px, sem `flex-wrap`, rótulo de frete variável | `orders/new.html.erb:215-229` | resumo financeiro logo acima de "Confirmar pedido" | média |
| **P1-7** | Tabela do resumo do checkout: ~544px (1,5× a tela) | `orders/new.html.erb:9-58` | primeira coisa vista no checkout | alta |
| **P1-8** | Caixa preço + "COMPRAR": ~286px em 271px sem `flex-wrap` | `screws/show.html.erb:165` | CTA da página de produto | média |
| **P1-9** | 20 cards/página × ~483px = **~10.000px** (~15 telas) de rolagem | `pagy.rb:11-13` (default 20) + `_card.html.erb` | abandono na navegação do catálogo | alta |
| **P2-10** | Rodapé de endereço: 3 `btn-sm` em ~296px de 319px, sem `flex-wrap` | `shipping_addresses/index.html.erb:30-48` | cosmético | média |
| **P2-11** | Filtros somam **14 colunas** de 12 em `md` (tablet retrato) | `screws/index.html.erb:7-48` | não afeta 375px | **máxima** |
| **P2-12** | `tfoot` com 4 células num corpo de 5 colunas | `carts/show.html.erb:58-106` | **não** desalinha (corrige §2.5); só higiene de HTML | **máxima** |
| **P2-13** | `.tr-feature-grid` é CSS morto | `_feature_cards.scss:148-162` | higiene | **máxima** |
| **P2-14** | Paginação `.page-link` ≈ 38px de altura | `pagy_bootstrap_nav` | alvo de toque | alta |
| — | 4 cards da home: **~174px cada**, ~768px o conjunto | `_feature_cards.scss` | **já responsivo em 3 breakpoints — não mexer** | alta |
| — | Login / Cadastro | `devise/*/new.html.erb` | **corretos — não mexer** | **máxima** |

#### Leitura rápida da prioridade

**P0-2 é o mais barato**: quatro atributos numa linha de ERB, confiança máxima, zero
risco de desktop (atributo de teclado só existe no mobile). Deveria vir primeiro por
relação custo/benefício, mesmo não sendo o de maior impacto isolado.

**P0-1, P0-3 e P1-5** são a mesma família — `d-flex` sem `flex-wrap` num orçamento que
não fecha — e admitem a mesma correção mobile-only.

**P0-4** (alvos de toque) toca 11 pontos e é a única que muda a aparência do desktop se
feita sem media query. Exige `@media (max-width: 991.98px)`, como as Fases 1 e 3.

**P1-9** é o único que não é CSS: mexer no `limit` do pagy é `config/` → mudança
"maior" pelo CLAUDE.md, exige aprovação e as 2-3 abordagens.

---

## Apêndice — comandos usados

```bash
# Estado
git status --short && git log --oneline -3          # limpo, bc431a3

# Produção, com UA de iPhone
UA='Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) ... Mobile/15E148 Safari/604.1'
curl -s -A "$UA" https://trscrews-prod-4185ac87e394.herokuapp.com/ | sed -n '1,45p'

# CORS do Bootstrap no CDN → access-control-allow-origin: *
curl -sI -H "Origin: https://trscrews-prod-...herokuapp.com" \
  https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css

# Regras do Bootstrap conferidas em arquivo
grep -o '\.collapse:not(\.show){[^}]*}'  bs.css
grep -o '\.carousel-inner{[^}]*}'        bs.css
grep -o '@media (min-width:992px){\.navbar-expand-lg[^@]*' bs.css

# Ausência do toggler
grep -rn "navbar-toggler" app/views/                # vazio

# Duplicação do CSS compilado
grep -c -F ".tr-feature-card {" app.css             # 4
grep -n "@media" app.css                            # 6 (3 regras × 2)

# Dimensões e peso
file app/assets/images/*.png
curl -sI "$PROD/assets/<asset>" | grep -i content-length
```

**Não executado:** simulação a 375px — Chromium (`libnspr4.so`) e Firefox
(`libasound.so.2`) do Playwright não iniciam nesta máquina.
