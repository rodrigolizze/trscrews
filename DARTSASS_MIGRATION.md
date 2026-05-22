# Migração: sassc-rails → Dart Sass

**Criado em:** 2026-05-22
**Contexto:** Etapa B do UPGRADE_PLAN.md — eliminar `sassc-rails` (deprecated, usa LibSass abandonado)
antes de iniciar os upgrades de versão do Rails.

---

## 1. Estado atual do pipeline SCSS

### Gem que compila SCSS hoje

`sassc-rails 2.1.2` — integra o compilador LibSass (C++) ao Sprockets.
LibSass está oficialmente abandonado desde março de 2019. `sassc-rails`
continua funcionando mas não recebe atualizações e não suporta sintaxe
Sass moderna.

### Como o Sprockets encontra os arquivos SCSS

`application.scss` é o ponto de entrada. Ele usa dois mecanismos mistos:

```
*= require_tree .    ← Sprockets: carrega arquivos SEM prefixo _ no diretório
*= require_self      ← Sprockets: inclui o próprio arquivo
@import "variables"  ← Sass: resolve _variables.scss pelo load path
@import "components/navbar"      ← Sass: resolve _navbar.scss
@import "components/feature_cards" ← Sass: resolve _feature_cards.scss
@import "utilities"  ← Sass: resolve _utilities.scss
```

Na prática: `require_tree .` não carrega os partiais (arquivos com prefixo `_`)
— eles chegam exclusivamente pelos `@import` do Sass. O `require_tree` só
serviria para arquivos sem `_`, dos quais não existe nenhum além do próprio
`application.scss`.

### Arquivos SCSS existentes

| Arquivo | Linhas | Papel |
|---|---|---|
| `app/assets/stylesheets/application.scss` | 151 | Ponto de entrada, estilos globais |
| `app/assets/stylesheets/_variables.scss` | 8 | Variáveis de cor e tipografia |
| `app/assets/stylesheets/_utilities.scss` | 90 | Classes utilitárias, botões |
| `app/assets/stylesheets/_carousel.scss` | 8 | Estilos do carrossel (comentado no manifest) |
| `app/assets/stylesheets/components/_feature_cards.scss` | 236 | Cards metálicos da seção "Por que" |
| `app/assets/stylesheets/components/_navbar.scss` | 44 | Navbar |
| **Total** | **537** | |

---

## 2. Análise da sintaxe usada

### 2.1 — `@import` (sintaxe legada)

Total: **7 `@import`** em 4 arquivos. Zero `@use` ou `@forward`.

| Arquivo | Linha | Importa |
|---|---|---|
| `application.scss` | 16 | `"variables"` |
| `application.scss` | 17 | `"components/navbar"` |
| `application.scss` | 18 | `"components/feature_cards"` |
| `application.scss` | 19 | `"utilities"` |
| `_utilities.scss` | 1 | `"variables"` |
| `_carousel.scss` | 1 | `"variables"` |
| `components/_navbar.scss` | 1 | `"../variables"` |
| `components/_navbar.scss` | 2 | `"../utilities"` |

**Observação:** `_navbar.scss` importa `_utilities.scss`, mas não usa nenhuma
das classes definidas lá (apenas consome as variáveis de `_variables.scss` que
chegam transitivamente). O `@import "../utilities"` em `_navbar.scss` é
redundante — só existe porque `_utilities.scss` reexporta `_variables.scss`
via `@import`. Com `@use` isso ficará explícito.

### 2.2 — Funções de cor deprecated

Total: **4 ocorrências** em 3 arquivos. Estas funções emitem `DeprecationWarning`
no Dart Sass e serão removidas no Dart Sass 2.0.

| Arquivo | Linha | Função | Parâmetros |
|---|---|---|---|
| `application.scss` | 120 | `darken()` | `$color-primary, 8%` |
| `_utilities.scss` | 67 | `darken()` | `$color-primary, 12%` |
| `_utilities.scss` | 79 | `lighten()` | `$color-secondary, 5%` |
| `components/_navbar.scss` | 41 | `darken()` | `$color-secondary, 10%` |

### 2.3 — Divisão com `/` (deprecated)

**Zero ocorrências.** Nenhum uso de `10px / 2` ou similar. ✓

### 2.4 — Outras funções de cor potencialmente problemáticas

**Zero ocorrências** de `mix()`, `adjust-hue()`, `saturate()`, `desaturate()`.

A única função de cor em `_carousel.scss` é CSS nativo (`filter: hue-rotate()`),
não Sass — não é afetada.

### 2.5 — Variáveis globais cross-file

`_variables.scss` define 6 variáveis usadas por outros arquivos:

```scss
$color-primary:   #FBBF24   // usado em: application.scss, _utilities.scss, _navbar.scss
$color-secondary: #1F2937   // usado em: application.scss, _utilities.scss, _navbar.scss
$color-ogray:     #9CA3AF   // usado em: _utilities.scss
$color-owhite:    #F9FAFB   // usado em: application.scss, _utilities.scss, _navbar.scss
$color-otitle:    #374151   // usado em: _utilities.scss, _navbar.scss
$color-igray:     #808080   // usado em: _utilities.scss
$font-family-heading: ...   // definida, não referenciada em nenhum arquivo ainda
```

Com `@import`, essas variáveis ficam no escopo global de qualquer arquivo que
importe `_variables.scss`. Com `@use`, cada arquivo precisa declarar
`@use "variables" as *` para manter o mesmo acesso sem namespace.

### 2.6 — Bootstrap

**Descoberta importante:** Bootstrap **não é importado via Sass**. É carregado
via CDN no layout (`application.html.erb:20`):

```html
<%= stylesheet_link_tag "https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" %>
```

A gem `bootstrap 5.3.5` está no Gemfile mas **nunca é importada** no código SCSS.
Ela apenas adiciona os arquivos do Bootstrap ao load path do Sprockets — sem efeito
real enquanto não há `@import "bootstrap"` ou `@use "bootstrap"`.

**Consequência para a migração:** Zero risco de incompatibilidade Bootstrap/Dart Sass.
A gem `bootstrap` pode permanecer no Gemfile sem problemas.

---

## 3. Incompatibilidades específicas e correções propostas

### Problema 1 — `@import` deprecated (7 ocorrências)

Dart Sass emite `DeprecationWarning: @import is deprecated` para cada `@import`
de arquivo Sass. A compilação **não falha hoje** (Dart Sass ainda suporta),
mas o comportamento muda: com `@import` global, variáveis vazam entre arquivos;
com `@use` cada arquivo é isolado.

**Estratégia de migração:** usar `@use "nome" as *` para manter os nomes de
variáveis sem alteração (sem prefixo de namespace). Isso minimiza diff e risco.

| Arquivo | Linha | Antes | Depois |
|---|---|---|---|
| `application.scss` | 16 | `@import "variables"` | `@use "variables" as *` |
| `application.scss` | 17 | `@import "components/navbar"` | remover — partiais não precisam de `@use` no manifest |
| `application.scss` | 18 | `@import "components/feature_cards"` | remover — idem |
| `application.scss` | 19 | `@import "utilities"` | remover — idem |
| `_utilities.scss` | 1 | `@import "variables"` | `@use "variables" as *` |
| `_carousel.scss` | 1 | `@import "variables"` | `@use "variables" as *` (ou remover — variáveis não são usadas no arquivo) |
| `components/_navbar.scss` | 1 | `@import "../variables"` | `@use "../variables" as *` |
| `components/_navbar.scss` | 2 | `@import "../utilities"` | remover — nenhuma variável ou mixin de `_utilities` é usado aqui |

**Nota sobre `application.scss`:** com `@use`, partiais são incluídos via
Sprockets (`require_tree`) ou precisam ser explicitamente `@forward`ados.
A abordagem mais simples com Sprockets: manter `*= require_tree .` e deixar
que cada parcial (`_utilities`, `_navbar`, `_feature_cards`) declare seu próprio
`@use "variables" as *`. O `application.scss` só precisa de `@use "variables" as *`
para suas próprias referências a `$color-primary` etc.

### Problema 2 — `darken()` e `lighten()` deprecated (4 ocorrências)

Requerem adicionar `@use "sass:color"` no topo de cada arquivo afetado e
substituir as chamadas:

| Arquivo | Linha | Antes | Depois |
|---|---|---|---|
| `application.scss` | 120 | `darken($color-primary, 8%)` | `color.adjust($color-primary, $lightness: -8%)` |
| `_utilities.scss` | 67 | `darken($color-primary, 12%)` | `color.adjust($color-primary, $lightness: -12%)` |
| `_utilities.scss` | 79 | `lighten($color-secondary, 5%)` | `color.adjust($color-secondary, $lightness: 5%)` |
| `components/_navbar.scss` | 41 | `darken($color-secondary, 10%)` | `color.adjust($color-secondary, $lightness: -10%)` |

`color.adjust($color, $lightness: -N%)` é o equivalente exato de `darken($color, N%)`.
`color.adjust($color, $lightness: +N%)` é o equivalente de `lighten($color, N%)`.

---

## 4. Estimativa realista de trabalho

**Classificação: BAIXO (1–2h)**

Justificativa:
- **Projeto pequeno:** 537 linhas em 6 arquivos.
- **Bootstrap via CDN:** elimina o maior risco potencial da migração. Zero
  compatibilidade a verificar com o ecossistema Bootstrap.
- **Sem `/` division:** nenhuma ocorrência.
- **Mudanças cirúrgicas:** 7 `@import` → `@use` e 4 funções de cor.
- **Estratégia `as *`:** preserva todos os nomes de variáveis, minimiza diff.
- **`_feature_cards.scss`** (o maior arquivo, 236 linhas) **não precisa de nenhuma
  mudança** — não tem `@import`, não tem funções de cor deprecated.

**Recomendação:** Vale fazer hoje em 1–2h restantes. Os riscos são baixos e
bem mapeados. A única validação necessária é visual: confirmar que os estilos
globais (botões amarelos, navbar, cards metálicos) renderizam identicamente
após a troca.

---

## 5. Bootstrap

### Como é importado no projeto

**Via CDN, não via gem.** O layout `application.html.erb` carrega:
```
Bootstrap CSS 5.3.0  → cdn.jsdelivr.net (linha 20)
Bootstrap JS 5.3.0   → cdn.jsdelivr.net (linha 29)
Bootstrap Icons 1.10.5 → cdn.jsdelivr.net (linha 23)
```

A gem `bootstrap 5.3.5` está no Gemfile e adiciona os arquivos SCSS do Bootstrap
ao load path do Sprockets — mas nenhum arquivo do projeto importa esses SCSS.
A gem existe sem efeito prático para CSS.

### Compatibilidade Bootstrap 5 + Dart Sass

**Compatível.** Bootstrap 5 migrou oficialmente de LibSass para Dart Sass em
outubro de 2021 (v5.1.3). A versão `5.3.5` usa sintaxe Dart Sass (`@use`/`@forward`)
nos seus próprios arquivos SCSS internos. **Se o projeto importasse Bootstrap via
Sass, Dart Sass seria o compilador correto.** Como usa CDN, isso é irrelevante.

### Gem para a integração com Sprockets

O UPGRADE_PLAN.md menciona `dartsass-rails`. Há uma distinção importante:

| Gem | Integração | Recomendado para |
|---|---|---|
| `dartsass-sprockets` | Drop-in replacement do sassc-rails dentro do Sprockets | **Projetos que usam Sprockets (como este)** |
| `dartsass-rails` | Pipeline separado de compilação Sass (precisa de `bin/dev`) | Projetos que usam jsbundling-rails |

**Este projeto usa Sprockets.** A gem correta é `dartsass-sprockets`, não
`dartsass-rails`. A troca é:

```ruby
# Gemfile — antes
gem "sassc-rails"

# Gemfile — depois
gem "dartsass-sprockets"
```

`dartsass-sprockets` é mantida pelo time do Rails, é listada na documentação
oficial do Bootstrap como opção válida, e é o que o engine do `bootstrap` gem
tenta `require` primeiro (conforme `bootstrap/engine.rb`).

**Ação antes de executar:** confirmar versão mais recente disponível com
`gem search dartsass-sprockets` (verificar < 12 meses desde último release,
conforme CLAUDE.md).

---

## Apêndice: Arquivos que NÃO precisam de mudança

| Arquivo | Motivo |
|---|---|
| `components/_feature_cards.scss` | Sem `@import`, sem funções deprecated, sem variáveis Sass |
| `config/storage.yml` | Não relacionado |
| `config/environments/` | Não relacionado |
| `db/schema.rb` | Não relacionado — nenhuma migration necessária |
| Qualquer view `.html.erb` | CSS via asset pipeline, não muda |
