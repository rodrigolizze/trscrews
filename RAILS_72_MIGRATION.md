# RAILS 7.2 MIGRATION — Investigação e Plano de Execução

**Elaborado em:** 2026-05-25  
**Etapa:** C do UPGRADE_PLAN.md  
**Origem:** Rails 7.1.5.1 → Destino: Rails 7.2.3.1  

---

## 1. Versão Alvo

| Campo | Valor |
|---|---|
| **Versão mais recente da série 7.2** | 7.2.3.1 |
| **Data de lançamento** | 2026-03-23 (patch de segurança) |
| **Data de lançamento do 7.2.0** | 2024-08-09 |
| **Ruby mínimo** | 3.1.0 (nosso Ruby: 3.3.5 ✅) |
| **Bug fixes (active support)** | **Expirado em 2025-08-09** |
| **Security patches** | Até 2026-08-09 (~2.5 meses restantes) |

### Decisão de pinagem

Usar `~> 7.2.3`, `>= 7.2.3.1` no Gemfile:

```ruby
gem "rails", "~> 7.2.3", ">= 7.2.3.1"
```

Razão: `~> 7.2.3` permite patches futuros da série 7.2 (ex: 7.2.4) mas não sobe para 8.x. Pinagem explícita em `>= 7.2.3.1` garante que estamos no patch mais recente que inclui as correções de segurança de março/2026.

> **Nota sobre janela de suporte:** O Rails 7.2 está em modo "apenas patches de segurança" desde 2025-08-09. Isso significa que bugs não-críticos não são corrigidos. O upgrade para 7.2 é uma etapa de transição obrigatória no caminho para 8.x — não é destino final.

---

## 2. Mudanças que `rails app:update` vai propor

### Arquivo 1: `config/application.rb`

```diff
- config.load_defaults 7.1
+ config.load_defaults 7.2
```

> **Nossa ação:** Alterar a linha. Todos os novos defaults de 7.2 ficam ativos. Ver Seção 5 para impacto de cada default.

---

### Arquivo 2: `config/initializers/new_framework_defaults_7_2.rb` (NOVO)

O `rails app:update` cria este arquivo com as 5 novas opções **comentadas** por padrão. A estratégia oficial é descomentar uma de cada vez e validar. Conteúdo esperado:

```ruby
# Be sure to restart your server when you modify this file.

# active_job.enqueue_after_transaction_commit default is :phase_one_five_1
# which will be true in 7.2+
# Rails.application.config.active_job.enqueue_after_transaction_commit = :phase_one_five_1

# active_storage.web_image_content_types now includes image/webp
# Rails.application.config.active_storage.web_image_content_types << "image/webp"

# active_record.validate_migration_timestamps = true
# Rails.application.config.active_record.validate_migration_timestamps = true

# active_record.postgresql_adapter_decode_dates = true
# Rails.application.config.active_record.postgresql_adapter_decode_dates = true

# Enable YJIT on Ruby 3.3+
# Rails.application.config.yjit = true
```

> **Nossa ação:** Aceitar o arquivo. Manter todos os itens comentados inicialmente. Cada um será avaliado na Seção 5.

---

### Arquivo 3: `config/environments/development.rb`

```diff
+ config.action_view.annotate_rendered_view_with_filenames = true
```

> **Nossa ação:** Aceitar. Não afeta produção. Em desenvolvimento, adiciona comentários HTML indicando qual partial gerou cada bloco — útil para debug de templates.

---

### Arquivos opcionais que `rails app:update` pode oferecer

| Arquivo/Diretório | Aceitar? | Motivo |
|---|---|---|
| `.devcontainer/` | **Rejeitar** | Projeto usa WSL2 local + Heroku, não Dev Containers |
| `.github/workflows/` | **Rejeitar** | CI não configurado — adicionar manualmente quando for relevante |
| `app/views/pwa/` (manifest + service worker) | **Rejeitar** | E-commerce de parafusos não precisa de PWA agora |
| `Gemfile` (rubocop-rails-omakase) | **Rejeitar** | Não usamos RuboCop |

---

## 3. Análise de Compatibilidade das Gems

Versões baseadas no `Gemfile.lock` atual (2026-05-25).

| Gem | Versão atual | Compatível 7.2? | Ação |
|---|---|---|---|
| **rails** | 7.1.5.1 | — é o alvo | Atualizar para `~> 7.2.3, >= 7.2.3.1` |
| **devise** | 4.9.4 | ✅ Sim (4.9.x suporta Rails 7.x oficialmente) | Manter |
| **stripe** | 11.7.0 | ✅ Sim (cliente de API puro, sem dep Rails) | Manter |
| **cloudinary** | 2.4.0 | ✅ Sim (gem usa Faraday + Active Storage adapter) | Manter |
| **dartsass-sprockets** | 3.2.1 | ✅ Sim (requer `railties >= 4.0.0`) | Manter |
| **friendly_id** | 5.5.1 | ✅ Sim (requer `activerecord >= 4.0.0`) | Manter |
| **pagy** | 9.4.0 | ✅ Sim (Ruby puro, sem dep Rails rígida) | Manter |
| **turbo-rails** | 2.0.16 | ✅ Sim (requer `railties >= 7.1.0`; Rails 7.2 satisfaz) | Manter (2.0.23 disponível se quiser) |
| **stimulus-rails** | 1.3.4 | ✅ Sim (requer `railties >= 6.0.0`) | Manter |
| **importmap-rails** | 2.2.0 | ✅ Sim (requer `railties >= 6.0.0`) | Manter |
| **bootstrap** (gem) | 5.3.5 | ✅ Sim (CSS/JS, sem dep de runtime Rails) | Manter |
| **sprockets-rails** | 3.5.2 | ✅ Sim (requer `actionpack >= 6.1`) | Manter |
| **pg** | 1.6.0 | ✅ Sim (driver PostgreSQL, independente) | Manter |
| **puma** | 6.6.0 | ✅ Sim (servidor independente) | Manter (Heroku recomenda 7.0.3+, mas não é bloqueador) |
| **image_processing** | 1.14.0 | ✅ Sim | Manter |
| **jbuilder** | 2.13.0 | ✅ Sim | Manter |
| **bootsnap** | 1.18.6 | ✅ Sim | Manter |
| **letter_opener_web** | 3.0.0 | ✅ Sim (requer `railties >= 6.1`) | Manter |
| **capybara** | 3.40.0 | ✅ Sim | Manter |
| **dotenv-rails** | 3.1.8 | ✅ Sim (requer `railties >= 6.1`) | Manter |
| **faker** | 3.5.1 | ✅ Sim | Manter |

### Conclusão de compatibilidade

Nenhuma gem precisa ser atualizada como pré-requisito do upgrade para 7.2. O `bundle update rails` vai puxar somente as gems do núcleo Rails (`actionpack`, `activerecord`, `railties`, etc.) — as outras devem permanecer nas versões atuais.

---

## 4. Deprecations Conhecidas

Mudanças que Rails 7.2 sinaliza com `DEPRECATION WARNING` (quebra em Rails 8.0).

### 4.1 Sintaxe de enum — ⚠️ NOSSO CÓDIGO USA

O Rails 7.1 iniciou a deprecação da sintaxe de keyword argument para `enum`. O Rails 7.2 mantém o aviso. O Rails 8.0 remove o suporte.

**Código atual em `app/models/order.rb`:**

```ruby
enum status: { draft: 0, placed: 1, cancelled: 2, shipped: 3 }
enum payment_status: { pending: 0, paid: 1, failed: 2 }, _default: :pending
```

**Sintaxe nova (Rails 7.0+):**

```ruby
enum :status, { draft: 0, placed: 1, cancelled: 2, shipped: 3 }
enum :payment_status, { pending: 0, paid: 1, failed: 2 }, default: :pending
```

> **Ação:** Corrigir no mesmo PR do upgrade 7.2. Simples busca/substituição. Não é breaking em 7.2, mas gera deprecation warnings em log de produção.

---

### 4.2 `ActiveRecord::ConnectionAdapters::ConnectionPool#connection`

Renomeado para `#lease_connection` no Rails 7.2 (deprecation), removido no 8.0.

> **Verificação:** Nenhuma ocorrência em nosso código. Risco zero.

---

### 4.3 `String#mb_chars`

Deprecated em 7.2, removido no 8.0.

> **Verificação:** Nenhuma ocorrência em nosso código. Risco zero.

---

### 4.4 Order-dependent finders sem `.order`

`.first` e `.last` sem `.order` explícito podem gerar deprecation warning quando a relação não tem ordenação implícita definida.

**Ocorrências no nosso código:**

```ruby
# app/models/user.rb:11
shipping_addresses.find_by(is_default: true) || shipping_addresses.first

# app/controllers/orders_controller.rb:46
@addresses.find_by(is_default: true) || @addresses.first
```

> **Análise:** Ambas as chamadas são em `has_many :shipping_addresses` — uma coleção já associada ao usuário, não um scan completo da tabela. O Rails ordena por `id` asc por padrão nessas coleções. Improvável que gere deprecation warning, mas vale monitorar o log após o upgrade.

---

### 4.5 `config.active_record.commit_transaction_on_non_local_return`

Deprecated em 7.2, removido no 8.0.

> **Verificação:** Não usamos este config. Risco zero.

---

## 5. Mudanças Sutis de Comportamento

### 5.1 `active_job.enqueue_after_transaction_commit` — ⚠️ NOSSO CÓDIGO USA

**Novo default (7.2):** Jobs são enfileirados apenas APÓS o commit da transação, não durante.

**Comportamento antigo:** Jobs enfileirados imediatamente — se a transação fizer rollback depois, o job já foi para a fila com dados que foram revertidos.

**Ocorrências no nosso código:**

```ruby
# app/controllers/orders_controller.rb:126
OrderMailer.pending_order(@order).deliver_later

# app/controllers/stripe_webhooks_controller.rb:104
OrderMailer.payment_confirmed(order).deliver_later
```

**Análise:**
- `deliver_later` usa Active Job internamente
- Ambas as chamadas estão em controllers, não dentro de transações explícitas
- O `stripe_webhooks_controller` não tem transaction wrapper — usa `update!` direto
- O `orders_controller` pode ter transaction implícita via `Order.create!` no `create` action
- **Efeito prático:** O email de confirmação só seria enviado após o `Order` realmente persistir no banco. Isso é MAIS CORRETO que o comportamento atual (email poderia ser enfileirado antes do rollback)
- **Risco:** LOW — comportamento melhora. Não deve quebrar nada.
- **Observação:** Como Active Job está configurado como `:inline` em development, esse default só tem efeito visível em produção (onde não há queue adapter configurado, usando `AsyncAdapter` padrão)

> **Decisão:** Aceitar o default novo (habilitar no `new_framework_defaults_7_2.rb`). É mais correto para o nosso fluxo de pedidos.

---

### 5.2 `active_storage.web_image_content_types` — WebP adicionado

**Novo default:** `image/webp` agora é tratado como web image nativo, não convertido para PNG.

**Impacto no nosso projeto:** Usamos `has_many_attached :images` no modelo `Screw`. Se um admin fizer upload de um `.webp` a partir do upgrade, ele será processado nativamente em vez de ser convertido para PNG.

> **Risco:** BAIXO. Mudança de comportamento positiva. Imagens WebP são menores. Cloudinary lida bem com WebP. Aceitar.

---

### 5.3 `active_record.validate_migration_timestamps`

**Novo default:** Impede a criação de migrations com timestamp no futuro.

> **Impacto:** Zero em produção. Afeta apenas o workflow de criação de migrations em desenvolvimento. Aceitar.

---

### 5.4 `active_record.postgresql_adapter_decode_dates`

**Novo default:** Queries SQL brutas retornam `Date` Ruby em vez de string ISO-8601 para colunas `date` do PostgreSQL.

**Nosso schema:** Usamos `datetime` (não `date` simples) para `created_at`, `updated_at`, `placed_at`, `paid_at`. Não temos colunas `date` no schema atual.

> **Risco:** ZERO para nosso schema. Aceitar.

---

### 5.5 YJIT habilitado (Ruby 3.3+)

**Novo default:** YJIT é habilitado automaticamente em Ruby 3.3+.

**Nosso ambiente:** Ruby 3.3.5 — YJIT será ativado.

> **Decisão: DESABILITAR preventivamente no release v50.** Habilitar em release separada (v51) após confirmar baseline de memória do Rails 7.2 em produção. Razão: isolamento de variável — se algo quebrar, saberemos se foi Rails 7.2 ou YJIT. Ver TODO.md.

---

### 5.6 `action_dispatch.show_exceptions` — Boolean removido

**Rails 7.2 remove** o suporte a `true`/`false` para esta config. Só aceita `:all`, `:rescuable`, `:none`.

**Verificação em nosso código:**

```ruby
# config/environments/test.rb
config.action_dispatch.show_exceptions = :rescuable  # ✅ já correto
# development.rb e production.rb: não definem esta config → usa default (:all em dev, :all em prod)
```

> **Risco:** ZERO. Nosso código já usa a sintaxe correta.

---

### 5.7 `automatically_invert_plural_associations`

Feature experimental no Rails 7.2. **Não é habilitada por default.** Só afeta quem tinha habilitado explicitamente via opt-in.

> **Risco:** ZERO. Não usamos este config.

---

## 6. Plano de Execução

### Branch: `refactor/rails-72-upgrade`

---

**Passo 1 — Criar branch** *(local, sem aprovação)*

```bash
git checkout -b refactor/rails-72-upgrade
```

---

**Passo 2 — Atualizar Gemfile** *(mudança maior → aprovação prévia)*

```diff
- gem "rails", "~> 7.1.5", ">= 7.1.5.1"
+ gem "rails", "~> 7.2.3", ">= 7.2.3.1"
```

⏸ **PARAR — aguardar aprovação do diff antes de salvar**

---

**Passo 3 — `bundle update rails`** *(após aprovação do Passo 2)*

Apenas gems do núcleo Rails devem ser atualizadas. Se alguma gem de terceiro mostrar conflito, PARAR e reportar antes de resolver.

Reportar saída completa.

---

**Passo 4 — `rails app:update`** *(após aprovação do Passo 3)*

Executar interativamente. Para cada arquivo proposto:
- Mostrar o diff COMPLETO como texto
- ⏸ PARAR e aguardar aprovação explícita
- Salvar somente após OK

Seguir as decisões da Seção 2 deste documento.

---

**Passo 5 — Corrigir sintaxe de enum** *(após app:update aprovado)*

Arquivo: `app/models/order.rb`

```diff
- enum status: { draft: 0, placed: 1, cancelled: 2, shipped: 3 }
- enum payment_status: { pending: 0, paid: 1, failed: 2 }, _default: :pending
+ enum :status, { draft: 0, placed: 1, cancelled: 2, shipped: 3 }
+ enum :payment_status, { pending: 0, paid: 1, failed: 2 }, default: :pending
```

⏸ **PARAR — aguardar aprovação do diff antes de salvar**

---

**Passo 6 — Configurar `new_framework_defaults_7_2.rb`**

O arquivo tem 5 itens comentados. Com `load_defaults 7.2` já ativo, todos os defaults
já estão em vigor — o arquivo serve para opt-out seletivo, não para opt-in.

Sintaxe verificada no source do railties 7.2.3.1: valores aceitos são `:always`,
`:never`, `:default`. Com `load_defaults 7.2`, `enqueue_after_transaction_commit`
já é `:default` (deixa o adapter decidir) — nenhuma linha precisa ser descomentada
para isso.

Única ação necessária: adicionar ao final do arquivo:

```ruby
# Mantém YJIT desabilitado nesta release. Habilitar em release separada
# após confirmar baseline de memória do Rails 7.2 em produção. Ver TODO.md.
Rails.application.config.yjit = false
```

⏸ **PARAR — aguardar aprovação do diff antes de salvar**

---

**Passo 7 — Rodar testes**

```bash
bin/rails test
```

Reportar: total de testes, falhas, erros, tempo.

---

**Passo 8 — Validação visual local**

Boot do servidor: `bin/rails server`

Verificar:
- [ ] Home (`/`) — carrossel, seção 3D
- [ ] Catálogo (`/screws`)
- [ ] Página de produto
- [ ] Admin (`/admin/screws`)
- [ ] Log de boot: sem DEPRECATION WARNINGs inesperados
- [ ] Criar pedido de teste (Stripe test mode) e confirmar email no letter_opener (`/letter_opener`)

---

**Passo 9 — Commit** *(após aprovação da validação visual)*

⏸ **PARAR — aguardar aprovação da mensagem de commit antes de executar**

---

**Passo 10 — Push para GitHub + PR** 

⏸ **PARAR — aguardar aprovação**

---

**Passo 11 — Merge em master**

⏸ **PARAR — aguardar aprovação**

---

**Passo 12 — Deploy para Heroku + validação**

```bash
git push heroku master
heroku logs --tail --app trscrews-prod
```

Verificar boot limpo. Validar as mesmas páginas do Passo 8 em produção.

Adicionalmente:
- [ ] Criar pedido de teste em produção (Stripe test mode) e confirmar email nos logs:
  `heroku logs --tail --app trscrews-prod | grep -E "mail|deliver|Enqueued|Performed"`

⏸ **PARAR — reportar resultado antes de qualquer próximo passo**

---

## 7. Riscos Identificados e Mitigação

### Risco 1 — Enum deprecation warnings em log de produção
- **Nível:** MÉDIO
- **O que acontece:** `DEPRECATION WARNING` no log para cada `enum` com sintaxe antiga após upgrade
- **Mitigação:** Corrigir no Passo 5 (mesmo PR do upgrade)
- **Status:** Incluído no plano ✅

---

### Risco 2 — Devise + `load_defaults 7.2`
- **Nível:** BAIXO
- **Análise:** Devise 4.9.4 é testado contra Rails 7.2. Os novos defaults de 7.2 não tocam autenticação, sessions, ou cookies da forma que afetaria o Devise. `secret_key_base` continua sendo usado como default para `config.secret_key` do Devise.
- **Mitigação:** Nenhuma necessária. Validar login/logout/reset de senha no Passo 8.

---

### Risco 3 — Stripe webhooks + `enqueue_after_transaction_commit`
- **Nível:** BAIXO
- **Análise:** `OrderMailer.payment_confirmed(order).deliver_later` no webhook controller vai enfileirar o email somente após o commit do `update!`. Como o `update!` não está dentro de uma transaction explícita mais ampla, o comportamento na prática não muda. A idempotência do webhook continua garantida pela tabela `StripeWebhookEvent`.
- **Mitigação:** Nenhuma. Comportamento melhora.

---

### Risco 4 — Cloudinary + `active_storage.web_image_content_types`
- **Nível:** BAIXO
- **Análise:** Cloudinary aceita WebP nativamente. A mudança só afeta uploads novos de imagens WebP. Imagens existentes (PNG/JPEG) não são reprocessadas.
- **Mitigação:** Nenhuma.

---

### Risco 5 — YJIT + memória no Heroku
- **Nível:** BAIXO-MÉDIO
- **Análise:** YJIT consome ~5–10% mais RAM para armazenar código JIT compilado. Em dyno Eco (512MB), pode causar R14 (memory exceeded) se o app já estiver próximo do limite.
- **Mitigação:** Monitorar `heroku logs --tail` no boot após deploy. Se aparecer R14, desabilitar via `config.yjit = false` em `new_framework_defaults_7_2.rb`.

---

### Risco 6 — `dartsass-sprockets` + Rails 7.2 (recém-adicionado)
- **Nível:** BAIXO
- **Análise:** `dartsass-sprockets 3.2.1` requer `railties >= 4.0.0` — sem restrição de versão máxima. Foi instalado há menos de 1 semana e compilou sem erros no Heroku v49. Nenhum issue conhecido com Rails 7.2.
- **Mitigação:** Se `rails app:update` gerar conflito com assets, reportar antes de resolver.

---

### Risco 7 — `bundle update rails` puxa gem indesejada
- **Nível:** BAIXO
- **Análise:** O comando `bundle update rails` pode atualizar gems transitivas além do núcleo Rails. Inspecionar o diff do `Gemfile.lock` antes de commitar.
- **Mitigação:** Revisar diff completo do `Gemfile.lock` no Passo 3. PARAR se qualquer gem de segurança (`devise`, `stripe`, `cloudinary`) for atualizada de forma inesperada.

---

## 8. Estimativa de Tempo

| Fase | Atividade | Tempo estimado |
|---|---|---|
| Implementação | Passos 1–6 (Gemfile, bundle, app:update, enum fix, defaults) | 1–1.5h |
| Testes + validação local | Passos 7–8 | 30–45min |
| Code review + commit + push | Passos 9–11 | 15min |
| Deploy Heroku + validação | Passo 12 | 20–30min |
| **Total** | | **~2–3h** |

> **Comparação com Etapa B (dartsass):** A Etapa B levou ~3h incluindo investigação. A Etapa C é mais simples do ponto de vista de SCSS (zero), mas tem mais pontos de parada para aprovação. Estimativa conservadora: 3h com pontos de parada incluídos.

---

*Criado por Claude Code | Contexto: UPGRADE_PLAN.md Etapa C | Branch alvo: refactor/rails-72-upgrade*
