# Auditoria Técnica — TR Screws

**Data:** 2026-05-14  
**Auditor:** Claude Sonnet 4.6  
**Branch:** master  

---

## 1. Stack e Versões

### Versões Exatas

| Componente | Versão |
|---|---|
| Ruby | 3.3.5 |
| Rails | 7.1.5.1 |
| PostgreSQL (adapter) | pg 1.6.0 |
| Node | Não utilizado (sem package.json) |
| Bundler | 2.6.8 |

O projeto usa **Importmap + Sprockets** em vez de Node/Webpack. É uma escolha legítima para um projeto desse porte.

### Banco de Dados

- **Development:** PostgreSQL (mesmo adaptador em todos os ambientes)
- **Production:** PostgreSQL via ENV `DATABASE_URL` (padrão Heroku)
- Schema gerenciado por migrations. Versão atual: `2025_11_25_145931`.

### Gems Principais

| Gem | Versão | Propósito |
|---|---|---|
| rails | 7.1.5.1 | Framework principal |
| pg | ~> 1.1 | Adaptador PostgreSQL |
| puma | ~> 6.6 | Servidor web |
| devise | 4.9.4 | Autenticação de usuários |
| stripe | ~> 11.0 | Processamento de pagamentos |
| cloudinary | 2.4.0 | Hosting de imagens |
| activestorage-cloudinary-service | 0.2.3 | Adaptador Active Storage → Cloudinary |
| turbo-rails | 2.0.16 | Hotwire (navegação SPA-like) |
| stimulus-rails | 1.3.4 | JavaScript reativo leve |
| importmap-rails | 2.2.0 | Bundling de JS via ESM (sem Node) |
| friendly_id | 5.5.1 | Slugs amigáveis em URLs |
| pagy | 9.4.0 | Paginação leve |
| bootstrap | 5.3.5 | CSS framework |
| sassc-rails | 2.1.2 | Compilação de SCSS |
| dotenv-rails | 3.1.8 | Variáveis de ambiente em dev |
| letter_opener_web | 3.0.0 | Preview de e-mails em dev |
| faker | 3.5.1 | Geração de dados de seed |
| image_processing | 1.14.0 | Variantes de imagem (libvips) |
| bootsnap | 1.18.6 | Otimização de boot |
| capybara | 3.40.0 | Testes de sistema |
| selenium-webdriver | 4.34.0 | Automação de browser |

### Serviços Externos Integrados

| Serviço | Gem(s) | Onde aparece no código |
|---|---|---|
| **Stripe** | stripe ~> 11.0 | `config/initializers/stripe.rb`, `app/controllers/stripe_webhooks_controller.rb`, `app/controllers/checkout_sessions_controller.rb`, views de checkout |
| **Cloudinary** | cloudinary, activestorage-cloudinary-service | `config/storage.yml`, `config/environments/production.rb` |
| **Heroku** | — (infra) | `config/environments/production.rb` (APP_HOST default) |
| **Gmail/SMTP** | — (via ActionMailer) | `config/environments/production.rb` linhas 86-97 |
| **ViaCEP** | — (fetch JS) | `app/javascript/controllers/cep_controller.js`, `app/controllers/cep_controller.rb` |

---

## 2. Domínio

### Lista de Modelos

| Modelo | Representa | Linhas |
|---|---|---|
| `User` | Conta de cliente | 13 |
| `Screw` | Produto (parafuso) | 131 |
| `Order` | Pedido de compra | 111 |
| `OrderItem` | Item de linha do pedido | 7 |
| `ShippingAddress` | Endereço de entrega do usuário | 70 |
| `StripeWebhookEvent` | Log de idempotência para webhooks | 6 |

### Descrição dos Modelos

**User** — Conta de cliente gerenciada pelo Devise com módulos: `database_authenticatable`, `registerable`, `recoverable`, `rememberable`, `validatable`, `confirmable`. Tem `has_many :orders` e `has_many :shipping_addresses`. Simples e adequado.

**Screw** — O coração do negócio. Atributos: `description`, `thread`, `automaker`, `model`, `surface_treatment`, `price`, `stock`, `slug`. Slugs gerados via `friendly_id` com candidatos compostos. Scopes notáveis: `by_automaker`, `by_model`, `by_thread`, `by_surface`, `search(q)` (busca multi-coluna com ILIKE). `apply_filters` encadeia scopes dinamicamente. Bem implementado.

**Order** — Pedido de compra. Inclui snapshot do endereço de entrega (campos CEP, street, etc. copiados no momento do pedido). Enums para `status` (draft/placed/cancelled/shipped) e `payment_status` (pending/paid/failed). Callback `after_create_commit` gera número de pedido formatado (SC-YYMM-xxxxxx). Inclui cálculo de frete: R$20 fixo, grátis ≥ R$150.

**OrderItem** — Linha de pedido com snapshot: `quantity`, `unit_price`, `line_total`. Relacionado a `Order` e `Screw` por FK. Simples e correto — a captura de `unit_price` no momento da compra é uma boa prática.

**ShippingAddress** — Endereço salvo pelo usuário. Máximo um `is_default` por usuário (forçado por callback + índice único). Normalização de CEP e state em `before_validation`. Bem implementado.

**StripeWebhookEvent** — Tabela de idempotência: armazena `stripe_event_id` (unique) e `processed_at` para evitar reprocessamento de webhooks duplicados. Uso correto e intencional.

### Diagrama de Relacionamentos (ASCII)

```
User
 ├── has_many ShippingAddresses (dependent: :destroy)
 └── has_many Orders (dependent: :nullify)
      └── Order
           └── has_many OrderItems (dependent: :destroy)
                ├── belongs_to Order
                └── belongs_to Screw
                     └── has_many_attached :images (Active Storage → Cloudinary)

StripeWebhookEvent   (standalone, sem FK)
```

### Modelos Incompletos ou Abandonados

Nenhum. Todos os modelos têm propósito claro e são usados no código. O projeto está coerente com seu domínio.

---

## 3. Estado dos Testes

### Estrutura

Existe a pasta `test/` com a estrutura padrão do Rails (Minitest):

```
test/
  controllers/
    admin/
      base_controller_test.rb       (7 linhas, 0 testes reais)
      orders_controller_test.rb     (7 linhas, 0 testes reais)
      screws_controller_test.rb     (28 linhas, 3 testes reais) ← único arquivo com testes
    cart_controller_test.rb         (0 testes reais)
    checkout_sessions_controller_test.rb (0 testes reais)
    orders_controller_test.rb       (0 testes reais)
    pages_controller_test.rb        (0 testes reais)
    screws_controller_test.rb       (0 testes reais)
    sitemaps_controller_test.rb     (0 testes reais)
    stripe_webhooks_controller_test.rb   (0 testes reais)
  models/
    order_item_test.rb              (0 testes reais)
    order_test.rb                   (0 testes reais)
    screw_test.rb                   (0 testes reais)
    shipping_address_test.rb        (0 testes reais)
    user_test.rb                    (0 testes reais)
  channels/
    application_cable/connection_test.rb (0 testes reais)
  system/                           (vazio)
```

### Contagem Real

- **Total de arquivos de teste:** 16
- **Total de métodos de teste (`test "..." do`):** **3** (todos em `admin/screws_controller_test.rb`)
- **Cobertura estimada:** < 1%

### Os 3 Testes Existentes

São testes de integração básicos para o admin de screws: `GET /admin/screws`, `GET /admin/screws/:id/edit`, `PATCH /admin/screws/:id`. Testam apenas que a resposta HTTP é 200/redirect. Sem assertions de conteúdo.

### Áreas SEM Nenhum Teste

**Tudo**, exceto as 3 actions do admin de screws. Especificamente ausentes:

- Fluxo de checkout completo (carrinho → pedido → pagamento)
- Webhook do Stripe (processamento de `checkout.session.completed`)
- Autenticação e autorização de pedidos
- Busca e filtros de produtos
- Endereços de entrega do usuário
- Envio de e-mails transacionais
- Modelos (Order, Screw, ShippingAddress, etc.)
- Qualquer teste de sistema/browser

**Avaliação:** A infraestrutura de teste foi criada mas nunca preenchida. É o ponto mais crítico de qualidade do projeto.

---

## 4. Segurança — Problemas Concretos

### 4.1 Credenciais Hardcoded

**Resultado: Não há credenciais no código-fonte ou no git.**

O arquivo `.env` existe localmente mas está corretamente excluído pelo `.gitignore` (linha 11: `/.env*`). O repositório contém apenas `.env.example` com todos os valores em branco. Padrão correto.

O `config/initializers/stripe.rb` usa `ENV.fetch("STRIPE_SECRET_KEY", nil)` — correto.

### 4.2 XSS — `html_safe` e `raw()`

**Achado:** `app/views/pages/home.html.erb` linhas 83, 88, 93, 98

```ruby
title: "Qualidade<br>Garantida".html_safe,
title: "Entrega<br>Rápida".html_safe,
```

**Risco: BAIXO.** São strings literais hardcoded no código, sem nenhuma entrada do usuário. O uso de `.html_safe` aqui é para renderizar `<br>` nos títulos dos cards. Aceitável, mas poderia ser substituído por `content_tag` ou CSS para ser mais limpo.

Nenhum uso de `raw()` encontrado. Nenhum `<%==` em posição perigosa.

### 4.3 SQL Injection

**Resultado: Não há vulnerabilidades.**

O modelo `Screw` usa padrões corretos:
- `app/models/screw.rb:70` — `sanitize_sql_like` antes de interpolar em ILIKE
- `app/models/screw.rb:122-125` — queries com `:named_parameters`
- `app/controllers/admin/screws_controller.rb:19` — `sanitize_sql_like` antes de `.where`

Todas as queries filtram inputs de usuário através de parâmetros ou sanitização explícita.

### 4.4 Strong Parameters

**Resultado: Correto em todos os controllers.**

- `OrdersController` — `order_params` com `.permit(...)` explícito
- `Admin::ScrewsController` — `screw_params` com lista explícita
- `ShippingAddressesController` — `address_params` com permit
- `ScrewsController` — `params.permit(:automaker, :model, ...)` na listagem

### 4.5 CSRF

**Resultado: Correto.**

- `ApplicationController` não desabilita CSRF globalmente
- `StripeWebhooksController` desabilita CSRF para o endpoint de webhook — correto e necessário para receber POSTs externos
- O webhook usa verificação de assinatura HMAC como substituto do CSRF token

### 4.6 Autenticação e Autorização

**Resultado: Adequado.**

- `ShippingAddressesController` — `before_action :authenticate_user!` em todas as actions + queries escopadas com `current_user.shipping_addresses.find(...)`
- `OrdersController` — `authenticate_user!` em `:show`, autorização customizada com `authorize_order!` que verifica propriedade do pedido
- `CheckoutSessionsController` — `authorize_checkout!` verificando ownership ou `session[:last_order_id]` (suporte a guest checkout)
- Admin — `before_action :require_admin_basic_auth` no `Admin::BaseController`, herdado por todos os controllers admin

Não há endpoints sensíveis desprotegidos.

### 4.7 Stripe Webhooks

**Resultado: Bem implementado.**

- `app/controllers/stripe_webhooks_controller.rb:14` — `Stripe::Webhook.construct_event(payload, sig_header, secret)` com rescue de `SignatureVerificationError`
- Idempotência via `StripeWebhookEvent` (unique index em `stripe_event_id`)
- Fallback de desenvolvimento sem assinatura, com warning explícito no log

### 4.8 Content Security Policy

**Problema: CSP desabilitada (comentada).**

- `config/initializers/content_security_policy.rb` — todo o bloco está comentado
- Sem CSP, o browser não impede carregamento de scripts externos injetados via XSS
- **Risco: MÉDIO** para um e-commerce (formulários de pagamento são alvo frequente)
- `config/initializers/permissions_policy.rb` — também comentado

**Recomendação:** Ativar CSP ao menos com `default_src :self`, `script_src :self 'unsafe-inline'` (progressivamente removendo `unsafe-inline`), e `frame-ancestors :none`.

---

## 5. Qualidade do Código

### Arquivos com Mais de 200 Linhas

| Arquivo | Linhas | Status |
|---|---|---|
| `app/controllers/orders_controller.rb` | 258 | ⚠️ Fat controller |
| `app/views/orders/new.html.erb` | 243 | ⚠️ View complexa |

**`orders_controller.rb`** contém lógica de: renderização do formulário de checkout, criação de pedido com lock de estoque, persistência de endereço, cálculo de totais, autorização customizada. Parte dessa lógica pertence ao modelo `Order` ou a um service object.

**`orders/new.html.erb`** tem lógica de negócio inline (linhas 76-78):
```erb
<% is_active =
    (params[:address_id].present? && params[:address_id].to_i == a.id) ||
    (!params[:address_id].present? && (a.is_default? || a == @addresses.first)) %>
```
Isso deveria estar no controller ou num helper.

### Código Duplicado

Nenhum duplicado evidente. Os 258 linhas do orders_controller são lógica diversa, não repetida.

### N+1 Queries

**Resultado: Bem gerenciado.**

Todos os loops sobre coleções com imagens usam `includes` preventivos:
- `ScrewsController` — `Screw.includes(images_attachments: :blob)`
- `CartsController` — mesmo padrão
- `PagesController` — mesmo padrão
- `OrdersController` (show) — `Order.includes(order_items: [screw: { images_attachments: :blob }])`
- `Admin::ScrewsController` — `includes(images_attachments: :blob)`
- `Admin::OrdersController` — `includes(order_items: :screw)`

Não foram identificadas N+1 queries óbvias.

### TODOs e FIXMEs

Nenhum `TODO`, `FIXME`, `HACK`, ou `XXX` encontrado em `app/`.

O código tem comentários em português estilo `# //` que parecem anotações do autor durante o desenvolvimento. Não são problemas técnicos, mas poderiam ser limpos.

---

## 6. Integrações — Estado de Cada Uma

### Stripe

| Item | Status |
|---|---|
| Versão da gem | stripe 11.7.0 (versão atual ~> 11.x) ✅ |
| Versão da API pinada | `2024-06-20` ✅ |
| Verificação de assinatura no webhook | Presente ✅ |
| Tratamento de erro | `rescue JSON::ParserError, Stripe::SignatureVerificationError` ✅ |
| Idempotência | `StripeWebhookEvent` table ✅ |
| Credenciais em ENV | `ENV.fetch("STRIPE_SECRET_KEY")` ✅ |
| URL placeholder no `set_app_info` | `"https://example.com"` em `config/initializers/stripe.rb:15` ⚠️ |

A integração com Stripe é a parte mais bem feita do projeto. O único ajuste pendente é atualizar a URL placeholder no `set_app_info`.

### Cloudinary

| Item | Status |
|---|---|
| Versão da gem | cloudinary 2.4.0 ✅ |
| activestorage-cloudinary-service | 0.2.3 (gem jovem, verificar updates) ⚠️ |
| Credenciais em ENV | `CLOUDINARY_*` em ENV ✅ |
| Configuração em `storage.yml` | Via ENV vars ✅ |
| Tratamento de erro em uploads | Não verificado (delegado ao Active Storage) |

A gem `activestorage-cloudinary-service` (0.2.3) é menos madura — vale monitorar atualizações e testar uploads em staging antes de cada deploy.

### Devise (Autenticação)

| Item | Status |
|---|---|
| Versão | 4.9.4 (última stable) ✅ |
| Módulos ativos | `confirmable` ativo (requer confirmação de e-mail) ✅ |
| Configuração de CSRF | Usa padrões seguros do Devise ✅ |
| `pepper` | Comentado (sem pepper adicional) — aceitável |

### E-mail (SMTP/Gmail)

| Item | Status |
|---|---|
| Configuração em produção | SMTP via ENV ✅ |
| `deliver_later` em uso | Sim, em 2 pontos ⚠️ |
| Queue adapter configurado em produção | **Não** — comentado em `production.rb:71` ⚠️ |

`OrderMailer.pending_order(@order).deliver_later` e `OrderMailer.payment_confirmed(order).deliver_later` são chamados em produção sem um queue adapter durável configurado.

O Rails usa `:async` como default (pool de threads em memória) — os e-mails **funcionam**, mas jobs são **perdidos** em caso de restart do servidor. Para um e-commerce, isso significa pedidos sem confirmação por e-mail.

---

## 7. Compatibilidade com Rails 8

**Versão atual:** Rails 7.1.5.1  
**Caminho para Rails 8.0+:** direto, sem blockers críticos.

### Checklist

| Item | Status |
|---|---|
| Webpacker (deprecated) | Não usa ✅ |
| Importmap (padrão Rails 7+) | Usa ✅ |
| Sprockets compatível | sprockets-rails 3.5.2 ✅ |
| Gems incompatíveis | Nenhuma identificada ✅ |
| Solid Queue (padrão Rails 8) | Não configurado ⚠️ |
| Solid Cache (padrão Rails 8) | Não configurado ⚠️ |
| Action Cable / Redis | cable.yml referencia Redis, mas gem `redis` está **comentada** no Gemfile ⚠️ |
| SSL forçado em produção | `config.force_ssl = true` ✅ |
| Logs para stdout | `config.logger = ActiveSupport::Logger.new(STDOUT)` ✅ |
| Locale pt-BR | Configurado ✅ |

### Inconsistência: Redis sem gem

`config/cable.yml` está configurado com `adapter: redis` e referencia `REDIS_URL`, mas a gem `redis` está comentada no Gemfile. Action Cable não é usado na aplicação, então isso não gera erro agora — mas qualificaria como tech debt se Action Cable fosse ativado.

### Warnings Esperados na Migração para Rails 8

- `config.active_job.queue_adapter = :resque` comentado em production.rb → substituir por `:solid_queue` ou `:async`
- Cache store não configurado → adicionar `config.cache_store = :solid_cache_store` ou `:memory_store`
- Nenhuma gem tem incompatibilidade documentada com Rails 8

---

## 8. Recomendação Final

### Refatorar Incrementalmente ou Reescrever?

**Refatorar incrementalmente.** O projeto tem uma base sólida: domínio bem modelado, integração Stripe correta, sem SQL injection, sem credenciais expostas, N+1 queries tratadas. Não há dívida técnica acumulada que justifique reescrita. O principal deficit é cobertura de testes e alguns pontos de configuração de infra.

### Os 5 Problemas Mais Urgentes

---

**Problema 1 — Fila de jobs sem persistência em produção**  
*Prioridade: Alta | Estimativa: 2–4 horas*

`deliver_later` usa `:async` (in-memory) em produção. Restart do servidor = e-mails perdidos.

**O que fazer:** Adicionar `gem "solid_queue"` ao Gemfile, rodar `bin/rails solid_queue:install`, definir `config.active_job.queue_adapter = :solid_queue` em `production.rb`. Ou usar Sidekiq + Redis se já houver Redis provisionado no Heroku.

---

**Problema 2 — Cobertura de testes praticamente zero**  
*Prioridade: Alta | Estimativa: 20–40 horas*

3 testes reais em 16 arquivos. O fluxo de checkout, webhook Stripe e autorização de pedidos — todos sem nenhum teste.

**O que fazer:** Priorizar testes de integração para: (a) fluxo de pedido completo; (b) processamento de webhook `checkout.session.completed`; (c) autorização de acesso ao pedido. Depois cobrir modelos com testes unitários de validações e métodos.

---

**Problema 3 — Content Security Policy desabilitada**  
*Prioridade: Média | Estimativa: 2–3 horas*

Sem CSP, scripts injetados via XSS (improvável hoje, mas possível amanhã) não são bloqueados pelo browser. Para e-commerce com formulário de pagamento, isso é risco real.

**O que fazer:** Descomentar e configurar `config/initializers/content_security_policy.rb` com `default_src :self`, `script_src :self 'nonce-...'`, `connect_src :self https://js.stripe.com`, `frame_src https://js.stripe.com`.

---

**Problema 4 — Fat controller: `orders_controller.rb` (258 linhas)**  
*Prioridade: Média | Estimativa: 4–6 horas*

O controller faz demais: monta carrinho, valida estoque, cria pedido, persiste endereço, calcula frete. Se o código de criação de pedido crescer, vai ficar incontrolável.

**O que fazer:** Extrair a lógica de `create` para um service object `OrderCreationService` (ou método no modelo `Order`). O controller fica responsável apenas por receber params, chamar o service e redirecionar.

---

**Problema 5 — URL placeholder no initializer do Stripe**  
*Prioridade: Baixa | Estimativa: 15 minutos*

`config/initializers/stripe.rb:15`: `url: "https://example.com"`. Aparece nos logs do Stripe Dashboard identificando o app.

**O que fazer:** Substituir por `url: ENV.fetch("APP_HOST", "")`.

---

### O que Está Bem Feito

Vale registrar o que **não** precisa de atenção:

- Integração Stripe (assinatura, idempotência, error handling) — exemplar
- Proteção contra SQL injection (sanitize_sql_like, named params) — correto
- Strong parameters em todos os controllers — correto
- Eager loading de imagens para evitar N+1 — consistente
- Gestão de credenciais (.env nunca commitado) — correto
- Modelos coesos e bem dimensionados
- Suporte a guest checkout com autorização via session — bem implementado
