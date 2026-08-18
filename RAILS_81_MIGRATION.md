# Etapa E — Rails 8.0.5.1 → 8.1.3.1

**Status: ✅ EXECUTADO E DEPLOYADO** — Rails 8.1.3.1 em produção desde **2026-08-13** (release
**v56**, merge `88755c7`).

Nasceu como documento de investigação (elaborado em 2026-08-13, antes de qualquer mudança) e virou o
registro da execução. As seções §0–§5 e §7–§8 preservam a análise **como foi escrita antes de
executar**, para que o que ela acertou e o que errou fique auditável; a §3.8 e o registro abaixo são
posteriores.

**Estado de partida:** Rails 8.0.5.1 · Ruby 3.3.5 · produção no Heroku em v55 · suíte
20 runs / 54 assertions / 0 falhas · `master` em `4c826dc`.

**Estado final:** Rails 8.1.3.1 · Ruby 3.3.5 (inalterado) · produção no Heroku em **v56** · suíte
**20 runs / 54 assertions / 0 falhas** · `master` em `88755c7`.

### Registro da execução

| Etapa | Resultado |
|---|---|
| Backup do banco | **b009** (`Completed`, 51.83KB) antes do merge |
| Branch | `upgrade/rails-8.1`, commit `4c74cba`, publicada no `origin` como ponto de recuperação |
| Bundle | `bundle update rails` — 13 gems do stack para 8.1.3.1; **nenhuma gem de terceiro se moveu** |
| `app:update` | 20 arquivos propostos: **9 aceitos, 11 rejeitados** |
| `load_defaults` | `8.0` → `8.1`; os **7 flags** confirmados em runtime |
| YJIT em produção | **`false`** — override preservado (`enable_yjit` 377 > `load_config_initializers` 257) |
| Suíte | 20 runs / 54 assertions / **0 falhas** |
| `assets:precompile` | exit **0** em 2s, 65 assets, `screw.glb` no manifest |
| Migrations | **nenhuma** |
| Deploy | merge `--no-ff` `88755c7` → **v56** |
| Validação em produção | `/up`, `/`, `/screws`, `?page=999` → **200**; `Rails.version` 8.1.3.1; logs **sem** `R14`, `Regexp::TimeoutError` ou warn de `libvips` |
| Não validado | Fluxos de compra completos (carrinho → checkout → webhook → e-mail), Fluxo 1 (Devise) e Fluxo 9 (upload Cloudinary) — produção sem pedidos, mesmo caso da D1 |

### O que a investigação acertou e o que errou

**Acertou:** os 7 defaults reais do 8.1 (contra os 2 falsos do plano); o risco-fantasma dos callbacks;
a ordem dos initializers que neutraliza o YJIT; impacto zero dos 6 flags restantes; o teto ausente do
minitest; a natureza das constraints "de desenvolvimento" do Cloudinary.

**Errou em dois pontos, ambos benignos:**

1. **`config/cable.yml`** foi registrado como risco nº 1 (template do 8.1 propondo `solid_cable`).
   **O `app:update` do 8.1 não toca esse arquivo** — não havia o que rejeitar. Precaução barata,
   risco inexistente.
2. **`turbo-rails` e `importmap-rails`** foram previstos como "devem subir junto". **Não subiram** —
   as versões instaladas já satisfazem `railties >= 7.1.0`. Menos variáveis do que o previsto.

**O que a investigação não previu e apareceu na execução:** `development.rb` e `test.rb` carregando
customização real (letter_opener, `queue_adapter :inline`, `assets.quiet`, cache condicional) —
foram classificados como "cosméticos" e só o diff revelou o contrário; o `config/ci.rb` **existe**
(correção 7 estava marcada como não confirmada) e vem acompanhado de `bin/ci`; e o warn de `libvips`
no boot, comportamento novo do Active Storage 8.1, que resolve o `variant_transformer` no boot em vez
de sob demanda — **não apareceu no Heroku**, confirmando que era artefato do host de desenvolvimento.

---

## 0. Correções ao `UPGRADE_PLAN.md`

Mesma prática da D1: o plano foi escrito em maio/2026 e vários fatos envelheceram ou nasceram
errados. Cada item abaixo foi verificado na fonte, não deduzido.

### Correção 1 — a versão alvo é **8.1.3.1**, não 8.1.3

O plano diz "Rails 8.1.3" em todo lugar. A última da série é **8.1.3.1**, de **2026-07-29**.

Detalhe que importa: **8.1.3.1 e 8.0.5.1 saíram no mesmo dia** — são o par de releases de segurança
da mesma correção. Nós já estamos no 8.0.5.1, ou seja, já absorvemos esse patch no ramo 8.0. Subir
para 8.1.3.1 mantém a paridade de segurança.

### Correção 2 — a série 8.1 é de **outubro de 2025**, não de março de 2026

O plano afirma: *"Rails 8.1.3 foi lançado em março de 2026 e está em produção em Shopify e HEY há
mais de 7 meses"*. A frase é internamente contraditória — não dá para estar em produção há 7 meses
uma versão lançada há 5.

O que os dados do RubyGems mostram:

| Release | Data |
|---|---|
| 8.1.0 (primeira da série) | **2025-10-22** |
| 8.1.1 | 2025-10-28 |
| 8.1.2 | 2026-01-08 |
| 8.1.2.1 | 2026-03-23 |
| 8.1.3 | 2026-03-24 |
| **8.1.3.1** (atual) | **2026-07-29** |

O plano confundiu a data do **patch** 8.1.3 (março/2026) com a da **série** 8.1.0 (outubro/2025). A
alegação dos "7+ meses em produção" bate com a data da série, não a do patch.

### Correção 3 — a janela de suporte do 8.1 está mais curta do que o plano sugere

O plano diz "A série 8.1 recebe bug fixes até outubro de 2026, dando margem real de suporte". A
conclusão está certa; a derivação estava errada, e a margem é menor do que a frase sugere.

Pela [política de manutenção](https://guides.rubyonrails.org/maintenance_policy.html) — 1 ano de bug
fixes e 2 anos de security fixes **contados da primeira release da série**:

- **Bug fixes do 8.1:** até ~**2026-10-22**. Ou seja, **~2 meses a partir de hoje**, não um ano.
- **Security fixes do 8.1:** até ~**2027-10-22**.

Duas ressalvas que suavizam isso, ambas verificadas:

1. **Não existe Rails 8.2.** A última release de qualquer série é a 8.1.3.1 (julho/2026). A política
   diz que, passando um ano sem release nova, a janela da série anterior se estende até a próxima
   sair. Na prática, o 8.1 é hoje a série corrente e continua recebendo correções — o próprio
   8.1.3.1 é a prova.
2. A comparação que importa não muda: o 8.0 está em **security-only desde ~nov/2025**, com segurança
   até ~nov/2026. O 8.1 tem segurança até ~out/2027. **Subir continua sendo claramente certo** — é a
   diferença entre ~3 meses e ~14 meses de cobertura de segurança.

O que muda é o tom: a Etapa E não compra "um ano tranquilo", compra **paridade com a série corrente**.
A próxima decisão de upgrade (8.2) vai aparecer no radar assim que ela for lançada.

### Correção 4 — **§3.3 lista os defaults errados do 8.1**

Esta é a correção mais consequente. O plano afirma que `load_defaults 8.1` ativa:

- `config.active_record.run_after_transaction_callbacks_in_order_defined = true`
- `config.active_record.use_yaml_unsafe_load = false`

**Nenhum dos dois é default do 8.1.** Duas evidências independentes:

**(a) Na fonte.** O `load_defaults "8.1"` do `8-1-stable` é:

```ruby
when "8.1"
  load_defaults "8.0"

  self.yjit = !Rails.env.local?

  if respond_to?(:action_controller)
    action_controller.escape_json_responses = false
    action_controller.action_on_path_relative_redirect = :raise
  end

  if respond_to?(:active_record)
    active_record.raise_on_missing_required_finder_order_columns = true
  end

  if respond_to?(:active_support)
    active_support.escape_js_separators_in_json = false
  end

  if respond_to?(:action_view)
    action_view.render_tracker = :ruby
    action_view.remove_hidden_field_autocomplete = true
  end
```

Nenhuma menção a callbacks de transação ou a YAML.

**(b) Em runtime, no nosso app, hoje, sob `load_defaults 8.0`:**

```
run_after_transaction_callbacks_in_order_defined = true
use_yaml_unsafe_load = false
```

Já estão nos valores que o plano atribui ao 8.1. O `run_after_transaction_callbacks_in_order_defined`
é default do **Rails 7.1** — entrou no nosso app na Etapa C, não vai entrar na E.

**Consequências:**

- O passo 7 do cronograma da Etapa E ("Verificar comportamento dos novos defaults... verificar
  especificamente: login/logout com `remember_me`, criação de pedido (callbacks de `Order`), criação
  de endereço (callbacks de `ShippingAddress`)") está mirando no alvo errado. Os callbacks de `Order`
  e `ShippingAddress` **não mudam de ordem na E** — já rodam na ordem definida desde a Etapa C.
- A linha do **Apêndice "Flags de risco elevado"** — *"Callbacks de `Order` ou `ShippingAddress`
  executam em ordem diferente | E | ... desabilitar o novo default via
  `run_after_transaction_callbacks_in_order_defined = false`"* — **é letra morta**. O flag não é da E.
- O conselho de rollback da §6 da Etapa E ("O risco mais provável da Etapa E é o novo default
  `run_after_transaction_callbacks_in_order_defined = true` mudando comportamento de callbacks")
  também é falso. O risco mais provável está em outro lugar — ver §7 deste documento.

### Correção 5 — o teto do minitest **não volta** no 8.1

O plano não menciona o assunto; a Etapa G registra que o `activesupport` 8.0.5.1 removeu o teto
`< 6`, o que derrubou a suíte na D1 e obrigou ao pin `~> 5.27`.

Verificado no `activesupport` **8.1.3.1**: a dependência continua **`minitest (>= 5.1)`**, sem teto.
Portanto **o pin `gem "minitest", "~> 5.27"` tem que permanecer durante a Etapa E**. Removê-lo
"aproveitando o embalo" repetiria a quebra da D1. A Etapa G segue independente e inalterada.

### Correção 6 — `to_time_preserves_timezone` deixa de ser setado pelo próprio Rails

Detalhe fino, sem impacto para nós, mas o plano ficaria desatualizado sem ele. No `8-1-stable`, o
`load_defaults "8.0"` **não seta mais** `active_support.to_time_preserves_timezone = :zone` — a
release note do 8.1 registra a remoção do suporte a `to_time` preservando hora local do sistema e a
deprecação do próprio flag.

Ou seja: a tabela da §3.2 do plano ("os defaults do 8.0 são exatamente três") vale enquanto estamos
no 8.0; sob 8.1 o `load_defaults 8.0` encadeado passa a ativar **dois**. Impacto no nosso código:
**zero** — `grep -rn "\.to_time\b" app/ config/ lib/ test/ db/` continua devolvendo **zero
ocorrências** (reconfirmado hoje, §3).

### Correção 7 — não verificado: `config/ci.rb`

O plano manda "aceitar o arquivo `config/ci.rb` mas não configurar agora". **Não consegui confirmar**
nesta investigação se o `app:update` do 8.1 de fato oferece esse arquivo — ele não aparece nas
release notes que li, e confirmar exigiria rodar o gerador, que está fora do escopo desta sessão.
Fica como item a observar no passo 5 da execução, não como fato.

---

## 1. Versão alvo

| Item | Valor |
|---|---|
| **Versão alvo** | **Rails 8.1.3.1** |
| Data da release | 2026-07-29 |
| Primeira release da série (8.1.0) | 2025-10-22 |
| Bug fixes (nominal) | até ~2026-10-22 · estendido enquanto não sair o 8.2 |
| Security fixes | até ~2027-10-22 |
| Série atual em produção (8.0) | security-only desde ~nov/2025 · segurança até ~nov/2026 |

**Ruby: 3.3.5 basta.** Rails 8.1 exige **Ruby >= 3.2.0**. Estamos em 3.3.5 — sem necessidade de
upgrade de Ruby, e sem tocar em `.ruby-version` nem no buildpack do Heroku. Isso remove uma variável
inteira da etapa.

**Constraint sugerida no Gemfile:** `gem "rails", "~> 8.1.3", ">= 8.1.3.1"` — mesmo formato usado na
D1 (`"~> 8.0.5", ">= 8.0.5.1"`), que fixa a série e garante o patch de segurança.

---

## 2. O que o `rails app:update` vai propor

### 2.1 — Arquivo novo, a **aceitar**

| Arquivo | Ação | Motivo |
|---|---|---|
| `config/initializers/new_framework_defaults_8_1.rb` | **Aceitar** | Nasce com tudo comentado. É o mecanismo do upgrade, igual ao `_8_0.rb` que aceitamos na D1. Traz 6 dos 7 flags novos (o `yjit` não entra nesse arquivo). |

### 2.2 — Arquivos a **rejeitar** (customizados à mão)

Os "de sempre" continuam valendo. Reconfirmei o conteúdo customizado de cada um hoje:

| Arquivo | O que perderíamos se aceitássemos o template |
|---|---|
| `config/environments/production.rb` | `active_storage.service = :cloudinary` (L40), `assume_ssl = true` (L49), `force_ssl = true` (L52), bloco SMTP inteiro (L86-…), `action_mailer.default_url_options` e `asset_host` com `APP_HOST` (L77-83) |
| `config/initializers/assets.rb` | `assets.precompile += %w[ screw.glb ]` (L14) e `assets.version = "1.0"` |
| `public/robots.txt` | Regras de SEO próprias — `Disallow` de `/admin/`, `/cart`, `/orders/new`, `/letter_opener/`, `/rails/`, `/up`, e o ponteiro para `sitemap.xml` |
| `config/application.rb` | `i18n.default_locale = :"pt-BR"`, `available_locales`, `autoload_lib(ignore: ...)` — só a linha do `load_defaults` muda, à mão |
| `config/puma.rb` | Precedente da D1: o template traz `plugin :solid_queue`, remove o `worker_timeout` de dev e derruba o suporte a `RAILS_MIN_THREADS` |
| `config/storage.yml` | Configuração do Cloudinary — arquivo sensível por `CLAUDE.md` |
| `config/database.yml` | Configuração de produção do Heroku |
| Docker, Kamal, CI, devcontainer, PWA, `bin/*`, adições ao Gemfile (rubocop/brakeman) | Precedente das Etapas C e D1 |

### 2.3 — Item **novo** de rejeição, que não existia na D1: `config/cable.yml`

**Atenção especial.** Acabamos de trocar (commit `4c826dc`, deploy v55) o `cable.yml` de produção
para `adapter: async`, removendo o Redis fantasma. O template do 8.1 propõe **`adapter: solid_cable`**
em produção. Aceitar reintroduziria uma dependência de Solid que decidimos não adotar e desfaria a
correção de ontem.

**Rejeitar.** É o item mais fácil de aceitar por distração, porque na D1 esse arquivo não estava na
lista de rejeições — ele estava na lista de pendências.

### 2.4 — Arquivos com mudança manual de uma linha

| Arquivo | Mudança |
|---|---|
| `config/application.rb` | `config.load_defaults 8.0` → `8.1` |
| `Gemfile` | `gem "rails", "~> 8.0.5", ">= 8.0.5.1"` → `"~> 8.1.3", ">= 8.1.3.1"` |

### 2.5 — Não verificado

`config/ci.rb` — ver Correção 7. Se aparecer, aceitar sem configurar, conforme o plano.

---

## 3. Breaking changes do 8.1 que afetam o **nosso** código

### 3.1 — Os 7 novos defaults, um a um

| # | Flag | O que faz | Impacto medido aqui |
|---|---|---|---|
| 1 | `yjit = !Rails.env.local?` | Liga YJIT fora de dev/test | **Neutralizado pelo nosso initializer** — ver §3.2. É o único que merece atenção |
| 2 | `action_controller.escape_json_responses = false` | Para de escapar entidades HTML e separadores de linha em respostas JSON | **Zero** — ver §3.3 |
| 3 | `action_controller.action_on_path_relative_redirect = :raise` | Levanta em `redirect_to` com URL relativa sem barra inicial | **Zero** — ver §3.4 |
| 4 | `active_record.raise_on_missing_required_finder_order_columns = true` | Levanta `MissingRequiredOrderError` em `#first`/`#last` sem ordem quando o modelo não tem coluna de ordenação | **Zero** — ver §3.5 |
| 5 | `active_support.escape_js_separators_in_json = false` | Para de escapar U+2028/U+2029 em JSON (válidos desde ES2019) | **Zero** — mesma superfície do #2 |
| 6 | `action_view.render_tracker = :ruby` | Rastreia dependências entre templates com parser Ruby (Prism) em vez de regex | **Zero** — não usamos fragment caching (`grep` por `<% cache` nas views: **zero**) |
| 7 | `action_view.remove_hidden_field_autocomplete = true` | Omite `autocomplete="off"` de inputs hidden gerados pelo Rails | **Zero** — cosmético |

### 3.2 — YJIT: o único flag com superfície real

O default do 8.1 é `self.yjit = !Rails.env.local?`, o que em produção significa **YJIT ligado**. O
`TODO.md` tem uma seção inteira ("Habilitar YJIT em produção") registrando que o YJIT foi desligado
preventivamente na Etapa 7.2 por receio de `R14 (memory exceeded)` no dyno do Heroku, e que reabilitar
deve ser uma **release isolada e monitorada**.

**Pergunta:** o `load_defaults 8.1` liga o YJIT em produção por baixo dos panos, contra essa decisão?

**Resposta: não.** Verificado em duas frentes:

1. `config/initializers/new_framework_defaults_7_2.rb` termina com `Rails.application.config.yjit = false`,
   explícito e comentado.
2. O Rails aplica o flag no `initializer :enable_yjit`, que vive no `Finisher` e lê `config.yjit`
   **depois** que os `config/initializers/*.rb` já rodaram. Confirmado empiricamente no nosso boot:

   ```
   load_config_initializers: índice 257
   enable_yjit:              índice 377   (de 378 initializers)
   ```

   O nosso `= false` é escrito no índice 257 e lido no 377. **Ganha.**

**Mas duas ressalvas:**

- **Não é testável localmente.** Este host roda um Ruby 3.3.5 compilado **sem YJIT**
  (`defined?(RubyVM::YJIT)` → falso). Mesmo que a ordem invertesse, não veríamos aqui. A validação
  precisa ser em produção, pelo log.
- **A decisão fica viva.** Depois da E, manter o `yjit = false` passa a ser uma escolha ativa contra
  o default do framework, não mais inércia. O item do `TODO.md` ganha relevância — mas continua sendo
  release separada, não parte da E.

### 3.3 — JSON: onde `escape_json_responses = false` toca

Único ponto de `render json:` no app é o `CepController` (5 ocorrências), que devolve endereço vindo
do ViaCEP — **input externo**. Isso levantaria a pergunta certa: JSON não escapado + input de
terceiro = risco de XSS?

**Não neste caso.** O consumo é `app/javascript/controllers/cep_controller.js`, um Stimulus que faz
`fetch` do endpoint e atribui os valores a `.value` de inputs do formulário. Nenhum `innerHTML`,
nenhuma interpolação em HTML. O escape de entidades no corpo JSON é irrelevante para esse caminho.

Vale como nota de vigilância: se algum dia esse JSON for interpolado em template, o flag passa a
importar.

### 3.4 — `redirect_to`: auditoria completa

Auditei **as 37 chamadas de `redirect_to`** do app. Todas usam **helper de rota** (`cart_path`,
`admin_screw_path`, `root_path`, `thank_you_order_path`, …) ou **objeto de modelo** (`redirect_to @order`).

- Chamadas com string literal: **zero** (`grep` por `redirect_to "` e `redirect_to '` → vazio).
- Única URL externa: `checkout_sessions_controller.rb:92` — `redirect_to session.url, allow_other_host: true`,
  que é a URL absoluta do Stripe Checkout, já com o opt-in explícito.

O flag `action_on_path_relative_redirect = :raise` só dispara em URL relativa **sem barra inicial**
(ex.: `redirect_to "screws"`). Não temos nenhuma. **Impacto zero.**

### 3.5 — `raise_on_missing_required_finder_order_columns`

O flag levanta `ActiveRecord::MissingRequiredOrderError` em métodos dependentes de ordem (`#first`,
`#last`, `#second`) chamados sem `order`, **e** quando o modelo não tem `implicit_order_column`,
`query_constraints` nem `primary_key` para servir de fallback.

Nossa superfície:

- `db/schema.rb` não tem **nenhuma** tabela `id: false` — todas têm primary key.
- Nenhum modelo sobrescreve `implicit_order_column`, `query_constraints` ou `self.primary_key`.
- Os 9 call sites de `.first` (`user.rb:11`, `carts_controller.rb:17`, `orders_controller.rb:46`,
  `admin/screws/index.html.erb:61`, `screws/show.html.erb:29`, `carts/show.html.erb:27`,
  `orders/show.html.erb:94`, `orders/new.html.erb:26` e `:78`) são todos sobre associações de
  modelos com PK padrão (`ShippingAddress`, `ActiveStorage::Attachment`).

Com PK presente, o Rails usa a PK como ordem implícita e **não levanta**. **Impacto zero.**

### 3.6 — Remoções e deprecações do 8.1: varredura no código

Rodei `grep` para cada API citada nas release notes do 8.1 sobre `app/ config/ lib/ test/ db/`:

| API removida / deprecada no 8.1 | Ocorrências |
|---|---|
| `String#mb_chars` / `ActiveSupport::Multibyte::Chars` | **0** |
| `ActiveSupport::Configurable` | **0** |
| `Benchmark.ms` | **0** |
| `Time#since` com objeto `Time` | **0** |
| `.to_time` (qualquer uso) | **0** |
| `ActiveRecord::Base.signed_id_verifier_secret` | **0** |
| `insert_all` / `upsert_all` | **0** |
| `update_all` com `WITH` / `WITH RECURSIVE` / `DISTINCT` | **0** (há 3 `update_all`, todos `where(...).update_all(...)` simples — `shipping_address.rb:61` e 2 migrations) |
| Serviço `:azure` do Active Storage | **0** (usamos Cloudinary) |
| `:retries` do adapter SQLite3 | **0** (PostgreSQL) |
| `:unsigned_float` / `:unsigned_decimal` do MySQL | **0** (PostgreSQL) |
| `ignore_leading_brackets` / colchetes iniciais em nome de parâmetro | **0** |
| Ponto-e-vírgula como separador de query string | **0** |
| Roteamento para múltiplos paths | **0** — auditei `config/routes.rb` inteiro; todas as rotas são de path único |
| `rails/console/methods.rb`, `bin/rake stats`, `STATS_DIRECTORIES` | **0** |

**Nenhuma deprecação do 8.0 que virou erro no 8.1 nos atinge.**

### 3.7 — `schema.rb` com colunas em ordem alfabética

Mudança de comportamento do Active Record no 8.1: o dump do `schema.rb` passa a ordenar as colunas
alfabeticamente, para diffs estáveis entre máquinas.

**Impacto na Etapa E: nenhum.** A E não adiciona migration, e `app:update` não mexe em schema.

**Impacto depois:** a **primeira** migration rodada após o 8.1 vai reescrever `db/schema.rb` inteiro
com as colunas reordenadas — um diff enorme, misturado com a mudança real. Na prática isso cai na
**Etapa D2 (Solid Queue)**, que é a próxima com migration. Vale saber de antemão para não confundir
ruído com regressão, e para não tratar o diff como suspeito.

`db/schema.rb` é arquivo sensível por `CLAUDE.md` (só via migrations) — este reordenamento é
exatamente isso, um efeito de `db:migrate`, não uma edição manual.

### 3.8 — Deprecations observadas na execução (2026-08-13)

Sob Rails 8.1, o boot/suíte emite **4 `DEPRECATION WARNING`**, todas de `config/routes.rb:2`
(`devise_for :users`), originadas no **Devise 4.9.4** (`resource` com hash em vez de keywords;
`devise/rails/routes.rb:416`). Removidas no **Rails 8.2**.

```
DEPRECATION WARNING: resource received a hash argument only.       ... removed in Rails 8.2
DEPRECATION WARNING: resource received a hash argument path.       ... removed in Rails 8.2
DEPRECATION WARNING: resource received a hash argument path_names. ... removed in Rails 8.2
DEPRECATION WARNING: resource received a hash argument controller. ... removed in Rails 8.2
```

> **[PRECISÃO ACRESCENTADA 2026-08-14]** São **4 avisos de UMA única chamada**, não 4 chamadas
> distintas — um aviso por chave do hash. A chamada é `resource :registration, options` em
> `devise-4.9.4/lib/devise/rails/routes.rb:416`, onde `options` traz exatamente
> `only:`, `path:`, `path_names:` e `controller:`. As outras chamadas de `resource` do mesmo arquivo
> (`devise_session:378`, `devise_password:386`, `devise_confirmation:391`, `devise_unlock:397`) passam
> as opções inline, que o Ruby 3 entrega como keywords, e por isso não emitem. No Devise 5.0.x a linha
> é `resource :registration, **options` — a correção são dois caracteres. Ver
> `DEVISE_50_MIGRATION.md` §5.

**NÃO são do nosso código** — nossas rotas não emitem. As 4 mensagens citam a linha 2 sem exceção; a
linha 7 (`resources :shipping_addresses, only: [...]`) e todas as demais rotas próprias ficam
silenciosas. A origem confirmada na fonte da gem:

```ruby
# devise/lib/devise/rails/routes.rb
378:  resource :session, only: [], controller: controllers[:sessions], path: "" do
416:  resource :registration, options do        # ← hash explícito
```

**Correção = Etapa F (Devise 5.0.4)** — este é o **segundo motivo** para a F, além do lazy route
loading que motivou o contorno do `test_helper.rb`.

**A afirmação "zero deprecations" da D1 não vale mais sob 8.1.** A D1 fechou com boot sem uma única
`DEPRECATION WARNING`; a partir da E o piso é 4, todas de terceiro e com prazo até o 8.2.

---

## 4. Compatibilidade das gems com Rails 8.1

Constraints lidas do RubyGems (`gem dependency <gem> -r -v <versão>`), não de memória.

| Gem | Versão atual | Última disponível | Constraint relevante | Compatível 8.1? | Ação na Etapa E |
|---|---|---|---|---|---|
| **rails** | 8.0.5.1 | 8.1.3.1 | — | — | **Alvo:** `"~> 8.1.3", ">= 8.1.3.1"` |
| **devise** | 4.9.4 | **5.0.4** | `railties (>= 4.1.0)` — sem teto | ✅ instala | **Manter 4.9.4.** Ver §4.1 |
| **minitest** | 5.27.0 (pin `~> 5.27`) | 6.x | `activesupport 8.1.3.1` → `minitest (>= 5.1)`, **ainda sem teto** | ✅ | **Manter o pin.** Ver §4.2 |
| stripe | 11.7.0 (pin `~> 11.0`) | 19.5.0 | nenhuma dep de Rails | ✅ | Manter. Salto para 19.x é tarefa própria |
| cloudinary | 2.4.0 | 2.4.5 | runtime: só `faraday`, `ostruct` | ✅ | Manter. Ver §4.3 |
| friendly_id | 5.5.1 | 5.7.0 | `railties` só como dep de **desenvolvimento** | ✅ | Manter na E — o 5.5→5.7 é tarefa separada já acordada |
| pagy | 9.4.0 | **43.6.1** | nenhuma dep de Rails | ✅ | **Manter 9.4.0.** Ver §4.4 |
| sprockets-rails | 3.5.2 | 3.5.2 (é a última) | `actionpack (>= 6.1)`, `activesupport (>= 6.1)` — sem teto | ✅ | Manter |
| dartsass-sprockets | 3.2.1 | 3.2.1 (é a última) | `railties (>= 4.0.0)`, `sprockets (> 3.0)` | ✅ | Manter |
| turbo-rails | 2.0.16 | 2.0.23 | `railties (>= 7.1.0)`, `actionpack (>= 7.1.0)` | ✅ | Deve subir junto no `bundle update rails` |
| stimulus-rails | 1.3.4 | 1.3.4 (é a última) | `railties` | ✅ | Manter |
| importmap-rails | 2.2.0 | 2.2.3 | `railties` | ✅ | Deve subir junto |
| pg | 1.6.0 | 1.6.3 | independente de Rails | ✅ | Manter |
| puma | 6.6.0 | 8.0.2 | independente de Rails | ✅ | **Manter** — Gemfile diz `>= 5.0`, mas subir Puma na mesma etapa misturaria variáveis |
| image_processing | 1.14.0 | 2.0.3 | independente | ✅ | Manter (Gemfile fixa `~> 1.2`) |
| bootsnap, jbuilder, faker, bootstrap, capybara, selenium-webdriver, dotenv-rails, letter_opener_web, debug, tzinfo-data | — | — | sem teto de Rails | ✅ | Manter |

**Nenhuma gem do projeto tem teto que bloqueie o Rails 8.1.**

### 4.1 — Devise: fica no 4.9.4, e o contorno **continua necessário e suficiente**

Três perguntas, três respostas verificadas:

**O Devise 4.9.4 instala sob Rails 8.1?** Sim — declara `railties (>= 4.1.0)`, sem teto.

**O bug do lazy route loading piora no 8.1?** Não há indicação de mudança. O comportamento que causa
o bug (rotas desenhadas sob demanda, rails/rails#52353) entrou no 8.0 e continua no 8.1.

**O contorno do `test_helper.rb` ainda funciona?** **Sim, verificado na fonte.** O método
`Rails.application.routes_reloader.execute_unless_loaded` **existe no `8-1-stable`**. Detalhe: a
implementação interna mudou — o `@loaded` booleano virou uma máquina de estados `@load_state`
(`nil` / `:loading` / `:loaded`) com lock. O contrato público (`execute_unless_loaded`, desenha uma
única vez) é o mesmo, então a nossa linha continua valendo.

*Nota de manutenção:* o comentário do `test_helper.rb` cita "`routes @loaded == false`". Sob 8.1 isso
descreve um interno que não existe mais com esse nome. É comentário, não código — não quebra nada,
mas fica registrado que envelheceu.

**O Devise 5.0.4 está estável** (`railties (>= 7.0)`). A **Etapa F deixou de ser hipotética** — o
plano falava em "5.0.x" quando ainda era rc. Continua sendo etapa separada, e não deve ser misturada
à E: autenticação é o caminho crítico do app e merece isolamento próprio.

### 4.2 — minitest: o pin fica

Já detalhado na Correção 5. Em uma frase: **`activesupport` 8.1.3.1 continua com `minitest (>= 5.1)`
sem teto**, então remover o pin durante a E puxaria o minitest 6 e repetiria o `LoadError` de
`minitest/mock` que derrubou a suíte inteira na D1. **Não tocar no pin nesta etapa.**

### 4.3 — Cloudinary: um falso alarme que vale explicar

O `gem dependency cloudinary -v 2.4.0` mostra, à primeira vista, algo assustador:

```
rails (>= 6.1.7, < 8.0.0, development)
railties (>= 6.0.4, < 8.0.0, development)
```

Um teto `< 8.0.0` pareceria bloquear até o Rails 8.0 — que já estamos rodando. O sufixo resolve:
são **dependências de desenvolvimento** da gem (o que os mantenedores usam para testar), não
dependências de runtime. As de runtime são apenas `faraday`, `faraday-follow_redirects`,
`faraday-multipart` e `ostruct` — nenhuma toca Rails.

Prova prática: rodamos cloudinary 2.4.0 sobre Rails 8.0.5.1 em produção desde a v53, sem problema.
**Sem risco no 8.1.**

### 4.4 — pagy: a versão 43.6.1 existe, e não queremos ela agora

O pagy pulou de 9.x para a série 43.x. É salto de arquitetura, não patch — e a nossa configuração
depende diretamente da API 9.x: `require "pagy/extras/bootstrap"`, `require "pagy/extras/overflow"`,
`Pagy::DEFAULT[:overflow]`, `Pagy::DEFAULT[:limit]`, `pagy_bootstrap_nav`.

`bundle update rails` **não vai tocar no pagy** (não é dependência do Rails). Mas o `Gemfile` traz
`gem "pagy"` **sem constraint**, então qualquer `bundle update` amplo o levaria para a 43.x e
quebraria a paginação e os 3 testes que a cobrem.

**Ação na E: nenhuma** — só não rodar `bundle update` sem argumento. Fica registrado como tarefa
futura própria (e como argumento para pinar `gem "pagy", "~> 9.4"`, decisão para outro momento).

---

## 5. Solid Queue / Cache / Cable no 8.1

**Confirmado: dá para subir para 8.1 sem adotar nada de Solid**, exatamente como na D1.

Evidências:

- O Solid entra por **gems** (`solid_queue`, `solid_cache`, `solid_cable`), nenhuma das quais está
  no `Gemfile`. O `rails` 8.1.3.1 não as declara como dependência — o `railties` 8.1.3.1 depende de
  `actionpack`, `activesupport`, `irb`, `rackup`, `rake`, `thor`, `tsort`, `zeitwerk`. Nada de Solid.
- O que o 8.1 traz de Solid são **templates do gerador** (`config/queue.yml`, `config/cache.yml`,
  `db/queue_schema.rb`, `bin/jobs`, `plugin :solid_queue` no `puma.rb`, e `adapter: solid_cable` no
  `cable.yml`). Todos rejeitáveis no `app:update`, como fizemos na D1.
- Estado atual que a E preserva: sem `queue_adapter` em `production.rb` (default `:async`), sem
  `cache_store` em produção, `cable.yml` em `async`. Os dois `deliver_later`
  (`orders_controller.rb:126` e `stripe_webhooks_controller.rb:112`) continuam no `:async`.

**O ponto de atenção é o `cable.yml`** — ver §2.3. É a única superfície onde o Solid pode entrar por
descuido, porque desta vez o arquivo tem conteúdo nosso a preservar.

**A dívida dos e-mails continua aberta.** `:async` é in-memory e o Heroku reinicia dynos diariamente;
job pendente na hora do restart se perde. Isso é a **Etapa D2**, não a E, e a E não piora nem melhora
a situação.

---

## 6. Plano de execução

Pontos de parada marcados com **⏸**. A etapa inteira é local até o passo 12.

1. **Backup do banco de produção:** `heroku pg:backups:capture --app trscrews-prod`. Anotar o ID.
2. `git checkout -b upgrade/rails-8.1` (a partir de `master`, após confirmar árvore limpa).
3. `cp Gemfile.lock Gemfile.lock.8.0-backup` — **local, não versionado** (`.gitignore` já cobre
   `Gemfile.lock.*-backup`; a instrução do plano de commitar o backup foi corrigida na D1).
4. `Gemfile`: `gem "rails", "~> 8.0.5", ">= 8.0.5.1"` → `"~> 8.1.3", ">= 8.1.3.1"`.
   **Não tocar** no pin do minitest, nem no pagy, nem no stripe.
5. `bundle update rails` — **só `rails`**, nunca `bundle update` pelado.
   ⏸ **Parada 1:** revisar o diff do `Gemfile.lock` antes de seguir. Esperado: stack Rails para
   8.1.3.1, mais bumps de `turbo-rails` (2.0.16→2.0.23) e `importmap-rails` (2.2.0→2.2.3). Qualquer
   mexida em `pagy`, `stripe`, `devise`, `minitest` ou `cloudinary` é sinal de que algo saiu do
   trilho — parar e investigar.
6. `bin/rails app:update` — aplicar **arquivo a arquivo**, com a tabela da §2 na mão.
   ⏸ **Parada 2:** listar explicitamente o que foi aceito e o que foi rejeitado. Atenção ao
   `cable.yml` (§2.3) e ao `config/ci.rb` (Correção 7).
7. `config/application.rb`: `config.load_defaults 8.0` → `8.1`.
8. `bin/rails runner` para confirmar em runtime os 7 flags novos (valores esperados na tabela §3.1),
   e reconfirmar que `config.yjit` continua `false` e que `enable_yjit` segue depois de
   `load_config_initializers`.
9. `bin/rails test` — **baseline a bater: 20 runs / 54 assertions / 0 falhas**.
10. Boot em development e em production (`RAILS_ENV=production` com `SECRET_KEY_BASE` dummy),
    procurando **qualquer** `DEPRECATION WARNING`. A D1 terminou com zero; a meta é a mesma.
11. Validação manual local com os 22 screws do seed: catálogo (`/screws`, paginação, `?page=999`),
    página de produto (slug friendly_id), home, carrinho. Os fluxos que dependem de pedido e usuário
    seguem sem dado local — mesma limitação registrada no passo 10 da D1.
    ⏸ **Parada 3:** relatório completo antes de qualquer merge.
12. Merge para `master` + deploy Heroku — **só com aprovação explícita**, conforme `CLAUDE.md`.
13. Pós-deploy: `heroku logs` procurando `Regexp::TimeoutError`, erro de YJIT/memória (`R14`) e 500s.
    Validar `/up`, `/`, `/screws`, `/screws?page=999`, página de produto.
14. Atualizar `UPGRADE_PLAN.md` (§0 deste documento) e `TODO.md`.

---

## 7. Riscos específicos do nosso projeto

Ordenados por probabilidade × dano. Note que **o risco que o plano apontava como principal para a E
(ordem dos callbacks) não existe** — ver Correção 4.

| # | Risco | Probabilidade | Dano | Mitigação |
|---|---|---|---|---|
| 1 | **Aceitar o `cable.yml` do template** e reintroduzir `solid_cable`, desfazendo o fix da v55 | **Média** — é o arquivo que mudou de categoria desde a D1 | Baixo em runtime (Action Cable não é usado), mas suja o repo e contradiz a Decisão 3 | Parada 2 do §6; `git diff config/cable.yml` obrigatório antes do commit |
| 2 | **`bundle update` sem argumento** puxar pagy 9.4 → 43.x | Média (erro de digitação/hábito) | **Alto** — quebra paginação e 3 testes | Só `bundle update rails`. Parada 1 confere o lock |
| 3 | **Remover o pin do minitest** "de brinde" | Baixa | **Alto** — suíte inteira deixa de carregar (`LoadError` em `minitest/mock`), repetindo a D1 | Correção 5; não tocar no grupo `:test` |
| 4 | **YJIT ligar em produção** contra a decisão do `TODO.md` | **Baixa** — ordem dos initializers verificada (257 < 377) | Médio (`R14` no dyno) | Não é testável localmente (Ruby sem YJIT aqui); validar por `heroku logs` no passo 13 |
| 5 | `Regexp.timeout = 1` (herdado do 8.0) disparar sob gem de terceiro | Baixa | Médio | Já era risco da D1 e não apareceu em v53–v55; seguir monitorando |
| 6 | Devise 4.9.4 + lazy routes: um teste novo que chame `sign_in` quebrar | Baixa | Baixo | O contorno do `test_helper.rb` cobre; verificado que `execute_unless_loaded` existe no 8.1 |
| 7 | Diff gigante no `db/schema.rb` na primeira migration pós-8.1 | **Alta** (é certeza, quando houver migration) | Baixo, se esperado | §3.7 — cai na D2, não na E; não confundir com regressão |
| 8 | Fluxos de compra seguem sem validação em produção (herdado da D1) | — | Médio | Não é risco *da* E, é dívida que a E não paga. Passo 13 do `UPGRADE_PLAN` §7 continua 🔶 |

**O que NÃO é risco desta etapa** (e o plano dizia que era): ordem de callbacks `after_commit` em
`Order`/`ShippingAddress`, `to_time` com timezone, e `use_yaml_unsafe_load`.

---

## 8. Estimativa de tempo

| Bloco | Estimativa |
|---|---|
| Passos 1–5 (branch, Gemfile, `bundle update rails`, revisão do lock) | 30–45 min |
| Passo 6 (`app:update` arquivo a arquivo) | 45–60 min |
| Passos 7–10 (`load_defaults`, verificação em runtime, suíte, boots) | 30–45 min |
| Passo 11 (validação manual local) | 30–45 min |
| Passos 12–13 (merge, deploy, validação em produção) | 30 min |
| Passo 14 (documentação) | 20–30 min |
| **Total** | **~3h–4h15** |

O plano estimava 2–3h. A diferença é o ritual da D1 — `app:update` arquivo a arquivo e verificação
de flags em runtime — que se mostrou o que fez a D1 chegar em produção sem regressão.

**Cabe na sessão de hoje.** Comparação honesta: a D1 foi maior (3 flags novos com semântica de
timezone e ReDoS, o desastre do minitest 6, o contorno do Devise). A E tem 7 flags novos, mas **seis
deles com impacto medido zero** e um neutralizado por configuração que já existe. O trabalho está
mais no ritual do que na incerteza.

---

## Fontes

- [RubyGems — versões do rails](https://rubygems.org/api/v1/versions/rails.json)
- [Rails Maintenance Policy](https://guides.rubyonrails.org/maintenance_policy.html)
- [Upgrading Ruby on Rails — 8.0 → 8.1](https://guides.rubyonrails.org/upgrading_ruby_on_rails.html)
- [Rails 8.1 Release Notes](https://guides.rubyonrails.org/8_1_release_notes.html)
- [railties `configuration.rb` (8-1-stable) — `load_defaults`](https://raw.githubusercontent.com/rails/rails/8-1-stable/railties/lib/rails/application/configuration.rb)
- [railties `finisher.rb` (8-1-stable) — `initializer :enable_yjit`](https://raw.githubusercontent.com/rails/rails/8-1-stable/railties/lib/rails/application/finisher.rb)
- [railties `routes_reloader.rb` (8-1-stable) — `execute_unless_loaded`](https://raw.githubusercontent.com/rails/rails/8-1-stable/railties/lib/rails/application/routes_reloader.rb)
- [template `new_framework_defaults_8_1.rb.tt`](https://raw.githubusercontent.com/rails/rails/8-1-stable/railties/lib/rails/generators/rails/app/templates/config/initializers/new_framework_defaults_8_1.rb.tt)
- [activerecord CHANGELOG v8.1.3](https://github.com/rails/rails/blob/v8.1.3/activerecord/CHANGELOG.md)
- [Configuring Rails Applications](https://guides.rubyonrails.org/configuring.html)
