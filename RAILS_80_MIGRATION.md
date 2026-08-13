# RAILS 8.0 MIGRATION — Investigação e Plano de Execução (Etapa D1)

**Data:** 2026-08-11 (investigação) · **Executado em:** 2026-08-12
**Autor:** investigação assistida (Claude Code)
**Status:** ✅ **EXECUTADO EM LOCAL — deploy pendente.** Branch `refactor/rails-80-upgrade`.
**Ponto de partida:** Rails 7.2.3.1 · Ruby 3.3.5 · `load_defaults 7.2` · produção Heroku release v52
**Ponto de chegada:** Rails 8.0.5.1 · Ruby 3.3.5 · `load_defaults 8.0` · suíte 17/17 · produção **ainda em 7.2.3.1**
**Relacionado:** `UPGRADE_PLAN.md` (Etapas D1, F e G), `RAILS_72_MIGRATION.md` (Etapa C, precedente direto), `AUDIT.md`

> **Quatro correções ao `UPGRADE_PLAN.md` saíram desta investigação.** Estão reunidas na §0 porque
> mudam premissas do plano original — inclusive a urgência da Etapa E. **As quatro foram aplicadas ao
> `UPGRADE_PLAN.md` em 2026-08-12.**

---

## 0-bis. Resultado da execução (2026-08-12)

**O que a execução confirmou e o que ela desmentiu.** Esta seção é o registro do que aconteceu de fato;
as seções seguintes preservam a análise original, feita *antes* de qualquer arquivo ser tocado.

### Confirmado

- **Nenhuma remoção ou deprecação do Rails 8.0 exigiu mudança no código de aplicação** (§5.8). O boot em
  development não emitiu **uma única** `DEPRECATION WARNING` — busca literal por `DEPRECATION` e ampla
  por `deprecat|warn|regexp|timeout|obsolete|removed` no stdout do servidor e no `development.log`: zero.
- **Os três defaults do 8.0** (§2.2) são exatamente três, confirmados na fonte do `railties` e ativos em
  runtime após `load_defaults 8.0`: `to_time_preserves_timezone = :zone`, `strict_freshness = true`,
  `Regexp.timeout = 1.0`. Impacto medido: zero nos dois primeiros.
- **Solid Queue/Cache/Cable não são dependências do Rails 8.0** (§3). Subimos sem nenhuma delas, custo zero.
- **O bug do Devise existe e é reprodutível** (§4.1). No boot da suíte: `routes @loaded == false`,
  `Devise.mappings == []`, e `Devise::Mapping.find_scope!(User)` levanta
  `RuntimeError: Could not find a valid mapping for User`.

### Desmentido pela medição

- **O Devise não era o "risco central" da D1.** §4.1 e o §7 do `UPGRADE_PLAN.md` o classificavam com
  probabilidade **Alta**. A suíte passou **17/17 sem o contorno**. Razão: `find_scope!` só é alcançado por
  `sign_in`, `sign_out`, URL helpers de Devise ou mailer — e `grep -rn "sign_in\|sign_out" test/` não
  retorna **nada**. O único teste que inclui `Devise::Test::ControllerHelpers`
  (`orders_thank_you_test.rb:12`) é de guest e nunca autentica; o `setup` do helper
  (`setup_controller_for_warden` + `warden`) não toca em `Devise.mappings`.
  **O contorno foi aplicado mesmo assim**, como proteção para o primeiro teste que autenticar — conforme
  a regra da §4.2 ("aplicamos mesmo assim, mas a decisão vira medida, não suposta").
- **O risco real era o minitest**, listado como risco genérico #6 de impacto "Baixo". O `activesupport`
  8.0.5.1 removeu o teto `minitest < 6` que o 7.2.3.1 tinha; o `bundle update rails` puxou o minitest
  6.0.6, que extraiu `minitest/mock` para uma gem separada, e a suíte **inteira** parou de carregar
  (`LoadError` em `stripe_webhooks_controller_test.rb:2`). **Zero testes rodavam** — e isso só foi
  descoberto porque o baseline do §6, passo 5, foi finalmente executado. Resolvido com pin
  `gem "minitest", "~> 5.27"`. Ver Etapa G do `UPGRADE_PLAN.md`.

### Desvios do plano da §6

| Passo | Planejado | Executado |
|---|---|---|
| 2 | branch `upgrade/rails-8.0` | `refactor/rails-80-upgrade` |
| 3 | remover linha comentada do `gem "redis"` | **não feito** |
| 4 | atualizar `friendly_id` para 5.7.0 junto | **não feito** — segue em 5.5.1 |
| 5 | baseline antes de mexer em config | executado **fora de ordem**, depois do `app:update` e do `load_defaults`, por causa da sessão interrompida |
| 7 | `bin/rails app:update` interativo | aplicado **por template** (cópia direta do `railties`), para eliminar o risco de um `a` acidental sobrescrever `production.rb` |
| 9 | `cable.yml` → `adapter: async` | **não feito** |
| 13 | 9 fluxos manuais em dev | **não feito** — banco de development vazio (0 screws/orders/users) |

### Estado final medido

```
Rails 8.0.5.1 · load_defaults 8.0 · minitest 5.27.0 (pinado) · devise 4.9.4
bin/rails test → 17 runs, 47 assertions, 0 failures, 0 errors, 0 skips  (~0,8s)
boot em development → 0 DEPRECATION WARNING
/up → 200 · / → 200 · /screws → 200
```

---

## 0. Correções ao UPGRADE_PLAN.md

| # | O que o `UPGRADE_PLAN.md` diz | O que é verdade | Impacto |
|---|---|---|---|
| 1 | *"`activestorage-cloudinary-service` 0.2.3 é **o maior risco do upgrade**"* (§2) | **A gem não está mais no projeto.** Não consta no `Gemfile` nem no `Gemfile.lock`. O serviço Active Storage vem do próprio `cloudinary` 2.4.0 (`storage.yml`: `service: Cloudinary`). | **O maior risco declarado do plano deixou de existir.** O "Plano B" da Etapa A é desnecessário. |
| 2 | *"`to_time_preserves_timezone = :zone` — novo default **com 8.1**"* (§3.3) | É default do **8.0**. Consta no `new_framework_defaults_8_0.rb` do Rails. | Antecipa uma verificação da Etapa E para a D1. **Impacto real no nosso código: zero** (§5.3). |
| 3 | *"Rails 8.0 entra em modo só security patches em **maio de 2026**"* (§1) | Rails 8.0.0 saiu em **2024-11-07**. Pela política oficial: bug fixes por 1 ano (**encerrados ~nov/2025**), security por 2 anos (**encerra ~nov/2026**). | **Rails 8.0 já está em modo security-only, e a janela fecha em ~3 meses.** A D1 é degrau, não destino — a Etapa E deixa de ser opcional. |
| 4 | *"Novos defaults com 8.0: `show_exceptions = :rescuable`, `query_log_tags_enabled`"* (§3.2) | Não são defaults do 8.0. O `new_framework_defaults_8_0.rb` tem **exatamente três** entradas (§2.2). O `show_exceptions` Boolean já foi tratado na Etapa C (`RAILS_72_MIGRATION.md` §5.6). | A superfície de mudança de defaults do 8.0 é **muito menor** que a prevista. |

Nota menor: a Etapa B foi executada com **`dartsass-sprockets`** (3.2.1), não com `dartsass-rails` como sugeria a Decisão 6 do plano. Sem consequência para o 8.0 — a gem exige apenas `railties >= 4.0.0`.

---

## 1. Versão alvo

### 1.1 Qual versão

**Rails 8.0.5.1**, lançada em **2026-07-29** (release de segurança, publicada no mesmo dia que a 8.1.3.1).

Histórico recente da série (fonte: rubygems.org):

```
8.0.5.1 | 2026-07-29   ← alvo
8.0.5   | 2026-03-24
8.0.4.1 | 2026-03-23
8.0.4   | 2025-10-28
8.0.3   | 2025-09-22
```

Pinagem sugerida no Gemfile, espelhando o critério da Etapa C:

```ruby
gem "rails", "~> 8.0.5", ">= 8.0.5.1"
```

### 1.2 Ruby 3.3.5 é suficiente — **não** exige 3.3.6+

`rails 8.0.5.1` declara `required_ruby_version >= 3.2.0`. Nosso `.ruby-version` e o `Gemfile` fixam
**3.3.5**, confirmado no ambiente local (`ruby 3.3.5p100`) e no `Gemfile.lock` (`RUBY VERSION ruby 3.3.5p100`).
**Nenhuma mudança de Ruby é necessária para a D1.**

### 1.3 Janela de suporte — ⚠️ leia antes de decidir

Pela [política de manutenção do Rails](https://guides.rubyonrails.org/maintenance_policy.html), cada
série minor recebe **bug fixes por 1 ano** e **security fixes por 2 anos** a partir do primeiro release.

| Série | Lançada | Bug fixes até | Security até | Situação hoje (2026-08-11) |
|---|---|---|---|---|
| 7.2 | ago/2024 | ago/2025 | ago/2026 | **security-only, expirando agora** |
| **8.0** | **nov/2024** | **nov/2025** | **nov/2026** | **security-only, ~3 meses de janela** |
| 8.1 | out/2025 | out/2026 | out/2027 | bug fixes por ~2 meses; security por ~14 meses |

Duas leituras honestas disso:

1. **Ficar no 7.2 é o pior cenário** — a janela de segurança dele fecha este mês. Sair dele é urgente,
   e é exatamente o que a D1 faz.
2. **O 8.0 não é destino.** Chegar nele resolve o problema imediato, mas em ~3 meses estaremos de novo
   sem suporte. A Etapa E (8.0 → 8.1) precisa vir **logo depois**, não "quando der". E vale registrar:
   a própria 8.1 sai da janela de bug fixes em out/2026 — quando a E for executada, convém reavaliar
   se o alvo não deve ser a série seguinte.

A recomendação do `UPGRADE_PLAN.md` (passar pelo 8.0 antes do 8.1) **continua correta** — é a
orientação oficial do Rails e reduz o blast radius por etapa. O que muda é o senso de urgência entre
D1 e E.

---

## 2. O que `rails app:update` vai propor

### 2.1 Como rodar

`bin/rails app:update` é interativo: para cada arquivo existente ele pergunta se deve sobrescrever
(`Y/n/a/q/d/h`). **A regra da Etapa C vale integralmente: nunca responder `a` (all).** Usar `d` (diff)
em cada arquivo customizado.

### 2.2 `config/application.rb` — `load_defaults 8.0`

Trocar `config.load_defaults 7.2` por `8.0`. O arquivo
`config/initializers/new_framework_defaults_8_0.rb` (novo) traz **exatamente três** opções — a
superfície é bem menor que a do 7.2:

| Config | O que faz | Nosso impacto |
|---|---|---|
| `active_support.to_time_preserves_timezone` | `:zone` faz `to_time` preservar o timezone do receptor em vez de converter para o offset UTC local. Valores: `:zone`, `:offset`, `false`. | **Nenhum.** `grep -rn "\.to_time\b" app/ config/ lib/` não retorna nada. Ver §5.3. |
| `action_dispatch.strict_freshness` | Quando o cliente manda `If-Modified-Since` **e** `If-None-Match`, considera só o `If-None-Match` (RFC 7232 §6). | **Baixíssimo.** Não fazemos conditional GET manual; nenhum `fresh_when`/`stale?` no código. |
| `Regexp.timeout` | Passa a valer `1` segundo, como defesa contra ReDoS. | **Baixo, mas é um global novo.** Nossas regexes são triviais (`/\A\d{5}-?\d{3}\z/` no CEP; `email_regexp` do Devise). Risco maior estaria em gems de terceiros — monitorar log. |

**Ação:** aceitar o arquivo com tudo comentado, como foi feito no 7.2. Habilitar um a um só depois do
deploy da D1 estável — ou aceitar todos de uma vez ao setar `load_defaults 8.0`, que é o que o passo
efetivamente faz. Ver §6 para a ordem proposta.

### 2.3 Arquivos que EXIGEM rejeição ou customização

Confirmando a sua pergunta: **sim, os três continuam sendo os pontos sensíveis**, pelo mesmo motivo da
Etapa C — todos foram customizados à mão e o gerador não sabe disso.

| Arquivo | Por que não pode ser sobrescrito | Ação |
|---|---|---|
| **`config/environments/production.rb`** | É o mais customizado do projeto: SMTP completo (Gmail via ENV), `active_storage.service = :cloudinary`, logger com `TaggedLogging` para STDOUT, `action_mailer.default_url_options` + `asset_host` com fallback do host Heroku, `force_ssl`, `i18n.fallbacks`, `report_deprecations = false`, `dump_schema_after_migration = false`. | **Rejeitar a sobrescrita.** Aplicar à mão só o que interessar (ver §2.4). |
| **`config/initializers/assets.rb`** | Contém `Rails.application.config.assets.precompile += %w[ screw.glb ]` — sem isso o modelo 3D da home quebra em produção. | **Rejeitar.** |
| **`public/robots.txt`** | Reescrito à mão: `Disallow` para `/admin/`, `/cart`, `/orders/new`, `/letter_opener/`, `/rails/`, `/up`, mais a linha `Sitemap:`. O template do Rails é genérico. | **Rejeitar.** |

### 2.4 `config/environments/production.rb` — o que vale considerar manualmente

- **`config.assume_ssl = true`** — hoje comentado (linha 49). No Heroku o SSL termina no roteador, e o
  `assume_ssl` faz o Rails tratar a requisição como HTTPS. O `UPGRADE_PLAN.md` (§3.2) recomenda ativar.
  Como já temos `force_ssl = true` e o app funciona, é melhoria, não correção. **DECIDIDO (2026-08-11):
  ativar.** As duas são complementares, não conflitantes: `assume_ssl` faz o Rails *tratar* a
  requisição como HTTPS (o TLS termina no roteador do Heroku, e o dyno recebe HTTP), enquanto
  `force_ssl` *redireciona* HTTP → HTTPS e liga HSTS + cookies seguros. Sem `assume_ssl`, o
  `force_ssl` pode entrar em loop de redirect atrás de um proxy que termina TLS.
- **Não aceitar** nenhuma linha que o template novo traga com `solid_queue` / `solid_cache` (ver §3).

### 2.5 Arquivos novos que o gerador vai oferecer

| Arquivo | Ação | Motivo |
|---|---|---|
| `config/initializers/new_framework_defaults_8_0.rb` | **Aceitar** | É o mecanismo do upgrade |
| `Dockerfile`, `.dockerignore`, `bin/docker-entrypoint` | **Rejeitar** | Deploy é Heroku via buildpack, não container |
| `config/deploy.yml`, `.kamal/` | **Rejeitar** | Kamal não é usado |
| `config/cache.yml`, `config/queue.yml`, `config/recurring.yml` | **Rejeitar na D1** | São configuração de Solid Cache/Queue — pertencem a D2/D3 |
| `bin/jobs` | **Rejeitar na D1** | Worker do Solid Queue — pertence a D2 |
| `.github/workflows/ci.yml` | **Rejeitar** | CI não configurado (precedente da Etapa C) |
| `.devcontainer/` | **Rejeitar** | WSL2 local + Heroku (precedente da Etapa C) |
| `app/views/pwa/*` | **Rejeitar** | Precedente da Etapa C |
| `Gemfile` (`rubocop-rails-omakase`, `brakeman`) | **Rejeitar** | Precedente da Etapa C — não usamos RuboCop |

---

## 3. Solid Queue / Solid Cache / Solid Cable — dá para NÃO adotar?

**Sim, e o custo é zero.** A confirmação é direta: as dependências de runtime da gem `rails 8.0.5.1` são

```
actioncable, actionmailbox, actionmailer, actionpack, actiontext, actionview,
activejob, activemodel, activerecord, activestorage, activesupport, railties, bundler
```

**Nenhum `solid_queue`, `solid_cache` ou `solid_cable`.** Essas três são gems **separadas**, adicionadas
ao `Gemfile` pelo **gerador de apps novas** (`rails new`) — não pelo `rails app:update`, e não pelo
framework. Subir para 8.0 sem elas é o caminho padrão de quem faz upgrade, não uma exceção.

### 3.1 O que precisa ficar explicitamente como está

Não há nada a "desativar" — há coisas a **não deixar o gerador mudar**:

| Item | Estado atual | Ação na D1 |
|---|---|---|
| Active Job em produção | `config.active_job.queue_adapter` **comentado** em `production.rb:71` → default `:async` | **Manter comentado.** Rejeitar qualquer `production.rb` que traga `:solid_queue`. |
| Active Job em desenvolvimento | `development.rb:52`: `queue_adapter = :inline` | Manter |
| Cache em produção | `config.cache_store` **comentado** em `production.rb:68` → default do Rails | Manter. Rejeitar `config/cache.yml`. |
| Cache em test / dev | `test.rb:29` `:null_store`; `development.rb` `:memory_store`/`:null_store` | Manter |
| Solid gems no Gemfile | ausentes | **Não adicionar** |

### 3.2 `config/cable.yml` — inconsistência a resolver na D1

Hoje:

```yaml
production:
  adapter: redis
  url: <%= ENV.fetch("REDIS_URL") { "redis://localhost:6379/1" } %>
  channel_prefix: trscrews_production
```

A gem `redis` **está comentada no Gemfile** e não há `REDIS_URL` configurada. Isso é uma bomba
desarmada: só explode se alguém usar Action Cable, o que não acontece hoje. O `UPGRADE_PLAN.md` (D1,
passo 8) já prevê simplificar para `adapter: async` em todos os ambientes, e a Decisão 3 rejeita
Solid Cable.

**Recomendação: fazer essa troca na D1.** É de baixo risco (Action Cable não é usado, `grep` não acha
nenhum channel de aplicação além do esqueleto), remove a inconsistência, e evita que o assunto volte
na D3.

---

## 4. Compatibilidade das gems com Rails 8.0

Dados obtidos da API do rubygems.org em 2026-08-11 (versão instalada vs. última publicada, e o
requisito declarado de Rails).

| Gem | Nossa versão | Última | Requisito declarado | Compat 8.0? | Ação proposta |
|---|---|---|---|---|---|
| **rails** | 7.2.3.1 | 8.1.3.1 | ruby >= 3.2.0 | — | **Atualizar para `~> 8.0.5`, `>= 8.0.5.1`** |
| **devise** | **4.9.4** | **5.0.4** | `railties >= 4.1.0` | ⚠️ **instala, mas com bug conhecido** | **Ver §4.1 — é o risco central da D1** |
| **friendly_id** | 5.5.1 | 5.7.0 | `activerecord >= 4.0.0` | ⚠️ instala; 5.5.1 é de nov/2023, anterior ao 8.0 | **Atualizar para 5.7.0** junto, e validar Fluxo 2 (slugs) |
| stripe | 11.7.0 | 19.5.0 | *(nenhuma dep de Rails)* | ✅ | **Manter.** Não misturar salto de 8 majors com upgrade de Rails |
| pagy | 9.4.0 | 43.6.1 | *(nenhuma dep)* | ✅ | **Manter.** O salto 9 → 43 é ruptura de API; tarefa separada |
| cloudinary | 2.4.0 | 2.4.5 | *(nenhuma dep de Rails)* | ✅ | Manter (ou patch 2.4.5) |
| turbo-rails | 2.0.16 | 2.0.23 | `railties >= 7.1.0` | ✅ | Manter ou atualizar junto |
| stimulus-rails | 1.3.4 | 1.3.4 | `railties >= 6.0.0` | ✅ | Manter |
| importmap-rails | 2.2.0 | 2.2.3 | `railties >= 6.0.0` | ✅ | Manter ou atualizar junto |
| dartsass-sprockets | 3.2.1 | 3.2.1 | `railties >= 4.0.0` | ✅ | Manter |
| sprockets-rails | 3.5.2 | 3.5.2 | `actionpack >= 6.1` | ✅ | Manter (Propshaft é tarefa futura) |
| sprockets | 4.2.2 | — | — | ✅ | Manter |
| bootstrap | 5.3.5 | — | CSS/JS puro | ✅ | Manter |
| jbuilder | 2.13.0 | 2.15.1 | `activesupport >= 7.0.0` | ✅ | Manter |
| pg | 1.6.0 | 1.6.x | *(nenhuma)* | ✅ | Manter |
| puma | 6.6.0 | 8.0.2 | *(nenhuma)* | ✅ | Manter (salto de major é tarefa separada) |
| image_processing | 1.14.0 | 2.0.3 | *(nenhuma)* | ✅ | **Manter 1.x.** O 2.0 é major novo; não misturar |
| bootsnap | 1.18.6 | 1.25.0 | *(nenhuma)* | ✅ | Manter ou atualizar junto |
| dotenv-rails | 3.1.8 | 3.2.0 | `railties >= 6.1` | ✅ | Manter |
| letter_opener_web | 3.0.0 | 3.0.0 | `railties >= 6.1` | ✅ | Manter |
| capybara | 3.40.0 | — | — | ✅ | Manter |
| selenium-webdriver | 4.34.0 | — | — | ✅ | Manter |
| faker | 3.5.1 | — | — | ✅ | Manter |
| debug | 1.11.0 | — | — | ✅ | Manter |
| tzinfo-data | — | — | — | ✅ | Manter |

**Gems removidas do risco desde o `UPGRADE_PLAN.md`:** `activestorage-cloudinary-service` (não está
mais no projeto — era o "maior risco" declarado) e `sassc-rails` (substituída por `dartsass-sprockets`
na Etapa B).

### 4.1 Devise — ⚠️ o risco central da Etapa D1

**O problema.** Rails 8.0 passou a **carregar rotas de forma preguiçosa (lazy) em development e test**
([rails/rails#52353](https://github.com/rails/rails/pull/52353)). O Devise monta seu `Devise.mappings`
durante o carregamento das rotas (`devise_for`). Quando algo pede a mapping antes de alguma rota ser
visitada — que é exatamente o que os test helpers fazem — o Devise levanta
`Could not find a valid mapping`
([rails/rails#53373](https://github.com/rails/rails/issues/53373),
[heartcombo/devise#5694](https://github.com/heartcombo/devise/issues/5694)).

**Nossa versão está do lado errado da linha.** `devise 4.9.4` foi publicada em **2024-04-10**; Rails
8.0.0 saiu em **2024-11-07**. A 4.9.4 é a última da série 4 — **não existe 4.9.5**. A correção entrou
no **Devise 5.0.0.rc** ([PR #5695](https://github.com/heartcombo/devise/pull/5695)), que passa a
carregar as rotas antes de resolver as mappings.

**Nossa exposição real, medida:**

| Ambiente | `eager_load` | Rotas | Exposição |
|---|---|---|---|
| production | `true` (`production.rb:13`) | carregadas no boot | **Nenhuma.** O bug não alcança produção. |
| development | `false` | lazy | Baixa — o fluxo normal visita rotas antes de tocar em Devise |
| **test** | `ENV["CI"].present?` → **false localmente** | lazy | ⚠️ **`test/controllers/orders_thank_you_test.rb:12` faz `include Devise::Test::ControllerHelpers`** — é precisamente a superfície quebrada |

Ou seja: o risco é **real mas contido** — 1 arquivo de teste, e produção intocada.

**Duas saídas:**

**(a) Manter `devise 4.9.4` + contornar no teste.** Forçar o carregamento com
`Rails.application.reload_routes!` no setup, ou setar `config.eager_load = true` em `test.rb`.
- *Prós:* nenhuma mudança de dependência de autenticação.
- *Contras:* gambiarra permanente num ponto sensível; fica uma gem de abr/2024 rodando num framework
  de nov/2024+, sem suporte do autor para essa combinação. A dívida só cresce rumo à Etapa E.

**(b) Subir para `devise 5.0.4` na mesma etapa.** Breaking changes do 5.0.0, conferidos contra o nosso código:

| Breaking change do Devise 5.0 | Nosso status |
|---|---|
| Derruba Ruby < 2.7 e Rails < 7.0 | ✅ Ruby 3.3.5, Rails 8.0 |
| `secret_key` passa a vir **sempre** de `application.secret_key_base` | ✅ Nosso `config.secret_key` está **comentado** (`devise.rb:17`) — já usamos o default |
| HTML dos forms muda de `<br>` para `<p>` | ✅ **Não afeta** — temos views próprias em `app/views/devise/` (confirmations, mailer, passwords, registrations, sessions, shared, unlocks) |
| Remove métodos de sign-in deprecados | ⚠️ Verificar — usamos `devise_parameter_sanitizer.permit` (`application_controller.rb:65,67`), que **não** é deprecado |
| Substitui diretiva de cache do Turbo deprecada | ✅ Sem impacto conhecido |

Nossa configuração é padrão: `devise :database_authenticatable, :registerable, :recoverable,
:rememberable, :validatable, :confirmable`, e o `devise.rb` só tem 15 linhas não-comentadas, todas de
opções comuns.

**Recomendação original desta investigação era (b).** A decisão do projeto foi **(a)** — ver §4.2.

### 4.2 DECISÃO (2026-08-11): Devise fica em 4.9.4 nesta etapa

**Escolhida a saída (a): manter `devise 4.9.4` com contorno no ambiente de teste.** A D1 fica sendo
Rails 8.0 **puro**, sem nenhuma mudança de autenticação. O upgrade para Devise 5.0 vira **etapa
própria e isolada**, registrada como **Etapa F** no `UPGRADE_PLAN.md`.

**Razões (do projeto, não desta investigação):**

1. O bug atinge **apenas teste** — produção roda `eager_load = true` e nunca vê o problema.
2. Devise 5.0 é **major version**; misturá-lo com o upgrade de framework junta duas migrações
   grandes numa etapa só e destrói a capacidade de isolar variáveis se algo quebrar.
3. O suporte do Rails 7.2 **encerra este mês** — uma D1 enxuta fecha mais rápido, e sair do 7.2 é
   o objetivo urgente.

**O contorno, integral** — em `test/test_helper.rb`, após `require "rails/test_help"`:

```ruby
# Rails 8.0 passou a desenhar as rotas sob demanda (lazy). O Devise 4.9.4 é anterior
# a isso e resolve Devise.mappings durante o carregamento das rotas, então um test
# helper que pede a mapping antes de qualquer rota ser visitada falha com
# "Could not find a valid mapping". Forçamos o desenho uma vez, no boot da suíte.
#
# `try` porque `execute_unless_loaded` só existe a partir do Rails 8.0 — no 7.2 a
# linha é inerte. É a MESMA chamada que o Devise 5.0 passou a fazer internamente
# (heartcombo/devise#5695), então este contorno some ao migrarmos para o Devise 5.
# Ver UPGRADE_PLAN.md, Etapa F.
Rails.application.routes_reloader.try(:execute_unless_loaded)
```

**Mecanismo:** `execute_unless_loaded` é a API que o Rails 8.0 criou para forçar o desenho das rotas
adiadas. Sai imediatamente se já estiverem carregadas, é thread-safe (monitor lock), protege contra
reentrância quando o próprio `routes.rb` chama `routes.draw`, e roda os hooks `after_routes_loaded` —
idempotente por construção. É literalmente a chamada que o Devise 5.0 embutiu em
`Devise::Mapping.find_scope!` ([PR #5695](https://github.com/heartcombo/devise/pull/5695)); a
diferença é só que chamamos uma vez no boot em vez de sob demanda.

**Por que `try`:** verificado no ambiente atual — o `Rails::Application::RoutesReloader` do Rails
7.2.3.1 **não responde** a `execute_unless_loaded` (só a `execute`). Sem o `try`, a linha levantaria
`NoMethodError` antes do bump. Com ele, é inerte no 7.2 e ativa no 8.0.

**Escopo:** `test/test_helper.rb` só é carregado por `require "test_helper"` nos arquivos de teste.
Não é lido por `rails server`, `console`, `runner`, nem por boot de development/production.
**Vazamento zero.** Descartadas: `config.eager_load = true` em `test.rb` (martelo grande, deixa a
suíte lenta e apaga a distinção `ENV["CI"].present?`), `reload_routes!` no setup (recarrega sempre,
risco de poluição entre testes) e initializer (vazaria para todos os ambientes).

**Superfície afetada:** um arquivo — `test/controllers/orders_thank_you_test.rb:12`.

**Aplicação condicional:** o contorno entra **depois** de observar a falha no baseline (§6, passo 5),
não antes. Se a suíte passar sem ele, registramos isso e aplicamos mesmo assim como proteção — mas a
decisão vira medida, não suposta.

**Dívida assumida, explicitamente:** ficamos com uma gem de abr/2024 rodando sobre um framework de
nov/2024+, numa combinação que o autor do Devise não suporta. A Etapa F existe para pagar isso.

---

## 5. Breaking changes do 8.0 que afetam o NOSSO código

Cada item abaixo foi verificado por `grep` no código real, não por leitura das release notes.

### 5.1 Remoções do Active Record — **nenhuma nos atinge**

| Removido no 8.0 | Nosso código |
|---|---|
| `config.active_record.commit_transaction_on_non_local_return` | ✅ não configurado (`grep` em `config/` não acha) |
| **Argumentos por keyword em `enum`** | ✅ já usamos a sintaxe nova: `enum :status, { draft: 0, ... }` e `enum :payment_status, { ... }, default: :pending` (`order.rb:5,8`) — tratado na Etapa C |
| `ConnectionPool#connection` | ✅ não usado |
| `warn_on_records_fetched_greater_than`, `SCHEMA_CACHE` env, config de associações no singular, descoberta de adapter | ✅ nenhum em uso |

### 5.2 Remoções do Active Support / Action Pack — **nenhuma nos atinge**

`ActiveSupport::ProxyObject`, `attr_internal_naming_format` com `@`, e
`action_controller.allow_deprecated_parameters_hash_equality`: nenhum aparece no `grep`. `mb_chars` e
`Benchmark.ms` (deprecados) também não.

### 5.3 `to_time_preserves_timezone` — **impacto zero, verificado**

```
$ grep -rn "\.to_time\b" app/ config/ lib/
(nenhum resultado)
```

Não há uma única chamada a `.to_time` no projeto. O campo `placed_at` de `Order` é gravado com
`Time.current` e lido diretamente. **Esta é a mudança de default que o `UPGRADE_PLAN.md` mais temia
para a Etapa E, e ela simplesmente não nos alcança.**

### 5.4 `params.require(...).permit(...)` — continua funcionando

O 8.0 **introduz** `params.expect(order: [:attr])` como forma mais segura, mas **não remove**
`require`/`permit`. Nossos 4 call sites seguem válidos:

```
app/controllers/orders_controller.rb:167
app/controllers/shipping_addresses_controller.rb:79
app/controllers/admin/screws_controller.rb:106
app/controllers/admin/orders_controller.rb:18
```

**Ação: nenhuma na D1.** Migrar para `params.expect` é melhoria opcional, tarefa separada.

### 5.5 `enqueue_after_transaction_commit` — deprecado no 8.0

O `new_framework_defaults_7_2.rb` traz essa opção **comentada** (não habilitamos na Etapa C). O 8.0 a
**deprecia**. **Ação: manter comentada e removê-la do arquivo quando o `new_framework_defaults_7_2.rb`
for descartado.** Não habilitar.

Relevante porque temos dois `deliver_later`:
`orders_controller.rb:126` (fora da transação, após `@order.persisted?`) e
`stripe_webhooks_controller.rb` (fora do `with_lock`). Ambos já estão no lado seguro.

### 5.6 Rotas com múltiplos paths — deprecado, não usamos

```
$ grep -nE "^\s*(get|post|put|patch|delete|match)\s+\[" config/routes.rb
(nenhuma)
```

### 5.7 Outros

- **`db:migrate` em banco novo passa a carregar o schema antes.** Sem impacto — nosso banco de produção
  existe e tem histórico de migrations.
- **Backend Azure do Active Storage deprecado.** Usamos Cloudinary. Sem impacto.
- **Adapter SuckerPunch interno deprecado.** Não usamos.

### 5.8 Resumo

**Nenhuma remoção ou deprecação do Rails 8.0 exige mudança no nosso código de aplicação.** O trabalho
da D1 é de **configuração e dependências**, não de refator. O único ponto que exige ação é o Devise
(§4.1), e ele é uma questão de versão de gem, não de código nosso.

---

## 6. Plano de execução proposto

Branch: `upgrade/rails-8.0`

| # | Passo | Tipo (`CLAUDE.md`) | Parada? |
|---|---|---|---|
| 0 | Revisão e aprovação deste documento | — | **Sim** |
| 1 | `heroku pg:backups:capture --app trscrews-prod` | backup | **Sim** |
| 2 | `git checkout -b upgrade/rails-8.0`; `cp Gemfile.lock Gemfile.lock.7.2-backup` | git | **Sim** |
| 3 | Gemfile: `rails` → `"~> 8.0.5", ">= 8.0.5.1"`; remover a linha comentada de `gem "redis"` | **maior** (Gemfile) | **Sim** |
| 4 | `bundle update rails` — registrar o diff do `Gemfile.lock` | dependências | Não |
| 5 | `bin/rails test` **antes** de qualquer mudança de config — baseline com Rails 8.0 e `load_defaults 7.2` | testes | Não |
| 6 | **Contorno Devise (§4.2):** se o passo 5 acusar `Could not find a valid mapping`, adicionar `routes_reloader.try(:execute_unless_loaded)` em `test/test_helper.rb` e rodar a suíte de novo | testes | **Sim** |
| 7 | `bin/rails app:update` — arquivo a arquivo, com `d` (diff). **Rejeitar** `production.rb`, `assets.rb`, `robots.txt`, Docker/Kamal/CI/devcontainer/PWA/Gemfile, e `cache.yml`/`queue.yml`/`recurring.yml`/`bin/jobs` | **maior** (config) | **Sim** |
| 8 | `config.load_defaults 8.0` em `application.rb`; aceitar `new_framework_defaults_8_0.rb` | **maior** (config) | **Sim** |
| 9 | `cable.yml`: `adapter: redis` → `adapter: async` em production (§3.2) | **maior** (config) | **Sim** |
| 10 | **`config.assume_ssl = true`** em `production.rb` — DECIDIDO: ativar (§2.4) | **maior** (config) | **Sim** |
| 11 | `bin/rails server` em dev — varrer o log atrás de `DEPRECATION WARNING`, documentar cada um | validação | Não |
| 12 | `bin/rails test` → verde (baseline atual: 17 runs / 47 assertions) | testes | Não |
| 13 | Rodar os 9 fluxos manuais do `UPGRADE_PLAN.md` §5 em dev — atenção a 1 (Devise), 5 (webhook) e 9 (Cloudinary) | validação | Não |
| 14 | `bin/rails assets:precompile` local — confirmar que `screw.glb` e o dartsass compilam | validação | Não |
| 15 | Commit(s) na branch | git | **Sim, por operação** |
| 16 | Merge para `master` | git | **Sim** |
| 17 | `git push origin master` e `git push heroku master` | deploy | **Sim, explícita** |
| 18 | Validar os 9 fluxos **no Heroku**; conferir `heroku logs` por R14/erros de boot | validação | Não |
| 19 | Confirmar estabilidade antes de considerar D2 | — | **Sim** |

**Paradas obrigatórias:** 0, 1, 2, 3, 6, 7, 8, 9, 10, 15, 16, 17, 19.

**Por que o passo 5 (testes antes de mexer em config) existe:** separa "quebrou por causa da versão do
Rails" de "quebrou por causa de `load_defaults 8.0`". Sem ele, um erro no passo 12 tem duas causas
possíveis e nenhuma forma barata de distinguir.

**Por que o Devise (6) vem antes do `app:update` (7):** o bug de lazy routes se manifesta em test, e
queremos a suíte confiável antes de começar a mexer em configuração. Se o Devise 5 der problema, ele
aparece isolado, sem estar misturado com 20 mudanças de config.

---

## 7. Riscos específicos deste projeto

| # | Risco | Prob. | Impacto | Mitigação |
|---|---|---|---|---|
| 1 | **Devise 4.9.4 + lazy routes quebra a suíte** (§4.1) | **Alta** | Médio — só test/dev; produção intocada | Passo 6: subir para 5.0.4 antes do resto. Fallback: `reload_routes!` no teste |
| 2 | **Devise 5.0 muda comportamento de autenticação em produção** | Baixa | **Alto** — login é crítico | Fluxo 1 inteiro validado em dev (passo 6) e de novo no Heroku (passo 18). Nossas views de Devise são próprias, e `config.secret_key` já usa o default |
| 3 | `rails app:update` sobrescreve `production.rb` | Média (erro humano) | **Alto** — perderia SMTP, Cloudinary, logger, mailer host | Nunca responder `a`. Usar `d` antes de cada `Y`. `git diff` obrigatório antes do commit |
| 4 | `assets.rb` sobrescrito → `screw.glb` some do precompile | Média | Médio — modelo 3D da home quebra | Rejeitar o arquivo; passo 14 valida o precompile |
| 5 | **`friendly_id` 5.5.1 (nov/2023) com Rails 8.0** | Média | Médio — slugs de produto são as URLs públicas | Atualizar para 5.7.0 no passo 4; validar Fluxo 2 |
| 6 | `bundle update rails` puxa gem indesejada junto | Média | Baixo | Passo 4 exige revisar o diff do `Gemfile.lock`; backup `Gemfile.lock.7.2-backup` no passo 2 |
| 7 | `Regexp.timeout = 1` derruba requisição por regex lenta em gem de terceiro | Baixa | Médio | Passo 11 e 18 monitoram log. Reversível: setar `Regexp.timeout = nil` |
| 8 | Cloudinary/Active Storage quebra no 8.0 | Baixa | **Alto** — todas as imagens de produto | Fluxo 9 nos passos 13 e 18. **Risco muito menor que o previsto**: a gem de comunidade saiu do projeto (§0) |
| 9 | Stripe webhook retorna 500 após o upgrade | Baixa | **Alto** — é o caminho de pagamento | Temos 4 testes de webhook (Fase 3). Flag do `UPGRADE_PLAN.md`: reverter imediatamente |
| 10 | Cobertura de testes insuficiente esconde regressão | **Alta** | Médio | 17 testes cobrem carrinho, webhook, thank_you, admin e agora os totais. Os 9 fluxos manuais são a rede real |
| 11 | **Chegar ao 8.0 e parar lá** | — | **Alto a médio prazo** | 8.0 sai do suporte em ~nov/2026 (§1.3). Agendar a Etapa E logo após a D1 estabilizar |

**Sem migrations nesta etapa** — D1 não adiciona schema. O rollback é `git push heroku <sha-anterior>:master`,
sem `db:rollback` e sem restauração de backup.

---

## 8. Estimativa de tempo

| Bloco | Estimativa |
|---|---|
| Passos 1-5 (backup, branch, Gemfile, `bundle update`, baseline) | 30-45 min |
| Passo 6 (contorno do Devise no teste) | **10 - 15 min** |
| Passos 7-10 (`app:update` arquivo a arquivo, `load_defaults`, cable, assume_ssl) | 45 min - 1h |
| Passos 11-14 (deprecations, testes, 9 fluxos manuais, precompile) | 1h - 1h30 |
| Passos 15-17 (commits, merge, deploy) | 20-30 min |
| Passo 18 (validação no Heroku) | 30-45 min |
| **Total** | **3h - 4h15** |

Alinhada com a estimativa do `UPGRADE_PLAN.md` para a D1 (3-4h), porque a decisão da §4.2 tirou o
upgrade do Devise desta etapa. O custo foi transferido para a **Etapa F**.

**Sugestão:** executar em **duas sessões**. Sessão 1: passos 1-6 (chegar ao Rails 8.0 com Devise
resolvido e suíte verde, ainda em `load_defaults 7.2`). Sessão 2: passos 7-19. O corte é natural
porque o passo 6 termina num estado consistente e testável.

---

## Fontes consultadas (2026-08-11)

- [Rails 8.0 Release Notes](https://guides.rubyonrails.org/8_0_release_notes.html) — remoções e deprecações por framework
- [Upgrading Ruby on Rails](https://guides.rubyonrails.org/upgrading_ruby_on_rails.html) — a seção 7.2 → 8.0 do guia está **vazia**, remetendo às release notes
- [`new_framework_defaults_8_0.rb.tt`](https://raw.githubusercontent.com/rails/rails/8-0-stable/railties/lib/rails/generators/rails/app/templates/config/initializers/new_framework_defaults_8_0.rb.tt) — fonte autoritativa dos 3 defaults do 8.0
- [Rails Maintenance Policy](https://guides.rubyonrails.org/maintenance_policy.html) — janelas de suporte
- [rails/rails#52353](https://github.com/rails/rails/pull/52353) — lazy route loading
- [rails/rails#53373](https://github.com/rails/rails/issues/53373) — testes de Devise quebrados
- [heartcombo/devise#5694](https://github.com/heartcombo/devise/issues/5694) e [PR #5695](https://github.com/heartcombo/devise/pull/5695) — correção do Devise
- [Devise CHANGELOG](https://github.com/heartcombo/devise/blob/main/CHANGELOG.md) — breaking changes do 5.0.0
- API do rubygems.org — versões e dependências declaradas de cada gem
