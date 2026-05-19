# Plano de Upgrade: Rails 7.1.5.1 → Rails 8.1.3

**Elaborado em:** 2026-05-19 · **Revisado em:** 2026-05-19  
**Estado atual:** Rails 7.1.5.1 · Ruby 3.3.5 · em produção no Heroku  
**Objetivo:** Migrar para Rails 8.1.3 com zero downtime e zero regressões em produção  

> **⚠️ CONTEXTO DE SEGURANÇA — LEIA ANTES DE QUALQUER COISA**
>
> Rails 7.1 está **end-of-life desde outubro de 2025**. Não recebe mais bug fixes nem security patches. Estamos rodando produção em versão sem suporte de segurança — este upgrade não é melhoria estrutural opcional, é **correção de dívida de segurança ativa**.
>
> A versão alvo é **Rails 8.1.3** (lançado em março de 2026), que está em produção em Shopify e HEY há mais de 7 meses e recebe bug fixes até outubro de 2026. Parar em Rails 8.0 seria insuficiente: a série 8.0 entra em modo "só security patches" em maio de 2026 — chegando lá quase no fim da janela de bug fixes.

---

## 1. Estratégia de Upgrade

### As três opções

#### (A) Upgrade direto: 7.1 → 8.0 em um passo

**Como funciona:** Atualizar `rails` direto para `~> 8.0` no Gemfile, rodar `bundle update rails`, resolver todos os conflitos de uma vez, rodar `rails app:update`.

**Riscos:**
- Pula todos os deprecation warnings que o Rails 7.2 emite — esses warnings existem exatamente para avisar o que vai quebrar no 8.0.
- Se algo quebrar em produção, não há como saber se foi mudança de 7.1→7.2 ou 7.2→8.0, dificultando o diagnóstico.
- Maior probabilidade de mudanças de comportamento silenciosas (novos defaults do `config.load_defaults 8.0` ativos todos de uma vez).
- Com cobertura de testes de ~1%, qualquer quebra silenciosa só aparece com usuário real.

**Tempo estimado:** 4–6h em um único bloco de trabalho.  
**Regressão esperada:** Alta. Nenhum sinal antecipado dos problemas.

---

#### (B) Upgrade incremental: 7.1 → 7.2 → 8.0

**Como funciona:** Dois passos separados. Cada um com seu próprio branch, `rails app:update`, testes manuais completos e deploy antes de avançar.

**Pontos positivos:**
- Rails 7.2 emite `DEPRECATION WARNING` para tudo que vai quebrar no 8.0, surfaceando problemas antes de chegar lá.
- Menor blast radius por etapa do que a Opção A.

**Problema:** Para em Rails 8.0, que entra em modo "só security patches" em maio de 2026. Adotar 8.0 como destino final significa chegar à versão quase no fim da janela de bug fixes — e precisar de um novo upgrade em breve de qualquer jeito.

**Tempo estimado:** ~7–8h.  
**Regressão esperada:** Baixa por etapa.

---

#### (C) Upgrade completo: 7.1 → 7.2 → 8.0 → 8.1 ← **RECOMENDADO**

**Como funciona:** Três saltos incrementais. Cada um deployado e validado antes de avançar. A guideline oficial do Rails recomenda explicitamente passar por 8.0 antes de 8.1.

**Por que 8.1 é o destino correto:**
- Rails 8.1.3 foi lançado em março de 2026 e está em produção em Shopify e HEY há mais de 7 meses — o ecossistema está maduro.
- A série 8.1 recebe bug fixes até outubro de 2026, dando margem real de suporte.
- Rails 8.0 entra em modo "só security patches" em maio de 2026: parar nele é quase equivalente a não sair do 7.1 em termos de suporte ativo.
- Cada salto incremental expõe um conjunto menor de mudanças — o 7.2 detecta deprecations do 8.0, o 8.0 detecta deprecations do 8.1.

**Tempo estimado:** ~12–17h distribuídas em ~3 semanas (inclui D1/D2/D3 para Solid Queue/Cache).  
**Regressão esperada:** Baixa por etapa, cada uma isolada e validada.

---

### Recomendação: Opção C

**Justificativa:** Estamos em produção em versão EOL. O objetivo do upgrade não é só modernizar — é sair de uma versão sem suporte de segurança e chegar em uma versão com janela de suporte real. Fazer isso em passos incrementais (7.2 como detector de problemas, 8.0 como ponte obrigatória, 8.1 como destino) é a abordagem mais segura dado que temos ~1% de cobertura de testes. Cada etapa pode ser validada manualmente e revertida de forma independente.

---

## 2. Análise de Compatibilidade das Gems

> Versões "mais recente disponível" são as estáveis no momento de elaboração deste plano. Verificar com `gem search <nome>` ou rubygems.org antes de executar.

### Gems do núcleo Rails

| Gem | Atual | Recente | Rails 8 compat | Risco | Ação |
|---|---|---|---|---|---|
| rails | 7.1.5.1 | 8.0.x | ✅ é o target | — | Atualizar em 2 passos |
| pg | 1.6.0 | ~1.6.x | ✅ não depende de versão Rails | Baixo | Manter |
| puma | 6.6.0 | ~6.6.x | ✅ | Baixo | Manter |
| sprockets-rails | 3.5.2 | ~3.5.x | ✅ (não é mais o default, mas funciona) | Baixo | Manter por ora |
| importmap-rails | 2.2.0 | ~2.x | ✅ mantido pelo time Rails | Baixo | Manter / atualizar junto |
| turbo-rails | 2.0.16 | ~2.x | ✅ mantido pelo time Rails | Baixo | Manter / atualizar junto |
| stimulus-rails | 1.3.4 | ~1.x | ✅ mantido pelo time Rails | Baixo | Manter / atualizar junto |
| jbuilder | ~2.x | ~2.x | ✅ | Baixo | Manter |
| bootsnap | 1.18.6 | ~1.x | ✅ | Baixo | Manter |
| image_processing | 1.14.0 | ~1.x | ✅ | Baixo | Manter |
| tzinfo-data | 1.2025.1 | atual | ✅ | Baixo | Manter |

### Gems de negócio / autenticação

| Gem | Atual | Rails 8.0 compat | Rails 8.1 compat | Risco | Ação |
|---|---|---|---|---|---|
| devise | 4.9.4 | ✅ | ✅ 4.9.x acompanha Rails ativamente | Baixo | Atualizar patch junto ao upgrade 8.0 |
| stripe | 11.7.0 | ✅ | ✅ não depende de versão Rails | Baixo | Manter |
| friendly_id | 5.5.1 | ✅ | ✅ | Baixo | Manter |
| pagy | 9.4.0 | ✅ | ✅ ativamente mantida | Baixo | Manter |
| faker | 3.5.1 | ✅ | ✅ | Baixo | Manter |

**Nota Rails 8.1 — Devise:** Rails 8.1 introduz `config.active_support.to_time_preserves_timezone = :zone` como novo default. Isso afeta a forma como timestamps são serializados na sessão. O Devise 4.9.x já trata esse caso, mas vale verificar o comportamento de `remember_me` e `sign_in` após o upgrade para 8.1.

### Gems de imagem e storage — ATENÇÃO

| Gem | Atual | Rails 8.0 compat | Rails 8.1 compat | Risco | Ação |
|---|---|---|---|---|---|
| cloudinary | 2.4.0 | ✅ SDK não depende de versão Rails | ✅ | Baixo | Manter |
| **activestorage-cloudinary-service** | **0.2.3** | ⚠️ **Incerto** | ⚠️ **Incerto** | **Alto** | **Verificar na Etapa A** |

**`activestorage-cloudinary-service` é o maior risco do upgrade, para 8.0 e 8.1.** É uma gem de comunidade (não oficial Cloudinary) sem versão nova em muito tempo. Ela se pluga diretamente nas entranhas do Active Storage. Se o Active Storage mudar internals em qualquer versão, esta gem pode silenciosamente parar de funcionar.

O risco para 8.1 é análogo ao de 8.0: se sobreviver ao 8.0 (ou se o Plano B tiver sido executado), o comportamento no 8.1 deve ser estável — o Active Storage não tem breaking changes significativos entre 8.0 e 8.1. Mas a incerteza só é resolvida pelo teste real no staging.

**Ação antes de qualquer upgrade:** Abrir o repositório da gem no GitHub, verificar se há issues ou PRs abertos reportando incompatibilidade com Rails 8.0 ou 8.1. Se não houver manutenção ativa, executar o Plano B (ver Etapa A).

### Gems de assets — ATENÇÃO

| Gem | Atual | Rails 8.0 compat | Rails 8.1 compat | Risco | Ação |
|---|---|---|---|---|---|
| bootstrap | 5.3.5 | ✅ é só CSS | ✅ | Baixo | Manter |
| **sassc-rails** | **2.1.2** | ⚠️ **Deprecated** | ⚠️ **Deprecated** | **Médio** | **Migrar para dartsass-rails (Etapa B)** |
| dartsass-rails | — | ✅ gem do time Rails | ✅ compatível com 8.1 | Baixo | Adotar na Etapa B |

**`sassc-rails` está deprecated** em qualquer versão do Rails. Será substituído por `dartsass-rails` na Etapa B, antes dos upgrades de Rails.

**Nota Rails 8.1 — dartsass-rails:** A gem `dartsass-rails` é mantida pelo time Rails e acompanha as versões de forma ativa. Compatibilidade com 8.1 confirmada pela manutenção contínua. Nenhuma ação especial necessária além da migração da Etapa B.

### Gems de infraestrutura (adicionadas durante o upgrade)

| Gem | Versão | Rails 8.0 compat | Rails 8.1 compat | Risco | Quando adotar |
|---|---|---|---|---|---|
| solid_queue | gem oficial Rails | ✅ | ✅ mantida pelo time Rails | Baixo | Etapa D2 |
| solid_cache | gem oficial Rails | ✅ | ✅ mantida pelo time Rails | Baixo | Etapa D3 |

**Nota Rails 8.1 — solid_queue:** A Etapa D2 instala Solid Queue quando o projeto está em Rails 8.0. Na Etapa E (upgrade para 8.1), o Solid Queue recebe atualização de versão junto com o `bundle update rails` — nenhuma migração adicional esperada para o upgrade de minor version.

### Gems de desenvolvimento/teste

| Gem | Atual | Rails 8.0 compat | Rails 8.1 compat | Risco | Ação |
|---|---|---|---|---|---|
| dotenv-rails | 3.1.8 | ✅ | ✅ | Baixo | Manter |
| letter_opener_web | 3.0.0 | ✅ | ✅ | Baixo | Manter |
| debug | ~1.x | ✅ | ✅ | Baixo | Manter |
| capybara | 3.40.0 | ✅ | ✅ | Baixo | Manter |
| selenium-webdriver | 4.34.0 | ✅ | ✅ | Baixo | Manter |

---

## 3. Mudanças de Configuração Esperadas

### 3.1 — Etapa 7.1 → 7.2

#### `config/application.rb`
- `config.load_defaults` deve ser atualizado para `7.2`
- Novos defaults ativos com 7.2:
  - `config.active_record.automatically_invert_plural_associations = true` — Rails vai tentar inferir automaticamente o `inverse_of` em associações. Testar se as associações do projeto (`Order → OrderItem`, `User → ShippingAddress`, etc.) se comportam igual.
  - `config.active_support.cache_format_version = 8.0` — formato do cache muda. Sem impacto aqui porque o cache está em `:null_store` no projeto.

#### `config/environments/development.rb`
- `rails app:update` adiciona **browser version guards** — bloqueia browsers muito antigos em desenvolvimento. Avaliar se é desejado:
  ```ruby
  config.browser_guard = -> (request) { ... }
  ```
- Novos logs de Active Record mais detalhados.

#### `config/environments/production.rb`
- `config.active_support.report_deprecations` — comportamento padrão muda.
- `config.assume_ssl` — pode aparecer como sugestão. No Heroku com SSL terminado no load balancer, configurar `config.assume_ssl = true` (descomenta a linha que já existe) é recomendado.

#### Arquivos novos (7.2)
- `config/puma.rb` — pode receber atualização do template para incluir `nakayoshi_fork`.
- Nenhum arquivo de infraestrutura novo significativo (Solid Queue/Cache/Cable são do 8.0).

---

### 3.2 — Etapa 7.2 → 8.0

#### `config/application.rb`
- `config.load_defaults` atualizar para `8.0`
- Novos defaults com 8.0:
  - `config.action_dispatch.show_exceptions = :rescuable` — comportamento de exibição de erros muda. Verificar se páginas de erro customizadas continuam funcionando.
  - `config.active_record.query_log_tags_enabled` — pode ativar por default. Impacto em performance mínimo.

#### `config/environments/production.rb`
- `config.assume_ssl = true` — descomenta a linha comentada existente. Necessário e correto para Heroku.
- **Não** adicionar `queue_adapter` ou `cache_store` na Etapa D1 — isso é D2 e D3 respectivamente.

#### `config/cable.yml` — MUDANÇA IMPORTANTE
Atualmente referencia Redis (que não está no Gemfile). Na Etapa D1, simplificar para `adapter: async` em todos os ambientes, já que Action Cable não é usado. Solid Cable (D3 potencial) não será adotado — ver §4 Decisão 3.

#### Novos arquivos que `rails app:update` vai criar (Etapa D1 — Rails puro)

| Arquivo | Propósito | Ação na D1 |
|---|---|---|
| `config/queue.yml` | Configuração do Solid Queue | Aceitar o arquivo, mas NÃO configurar o adapter em production.rb ainda (D2) |
| `config/cache.yml` | Configuração do Solid Cache | Aceitar o arquivo, mas NÃO configurar cache_store ainda (D3) |
| `bin/jobs` | Worker do Solid Queue | Criar apenas na D2 |
| `db/queue_schema.rb` | Schema do Solid Queue | Criar apenas na D2 |
| `db/cache_schema.rb` | Schema do Solid Cache | Criar apenas na D3 |

#### `config/initializers/` — sem mudanças obrigatórias
Os initializers existentes (`stripe.rb`, `devise.rb`, `shipping.rb`, etc.) não precisam mudar para o upgrade em si. `rails app:update` pode oferecer versões novas de `content_security_policy.rb` e `permissions_policy.rb` — comparar antes de aceitar.

---

### 3.3 — Etapa E — 8.0 → 8.1

#### `config/application.rb`
- `config.load_defaults` atualizar para `8.1`
- Novos defaults ativos com 8.1:
  - `config.active_support.to_time_preserves_timezone = :zone` — altera como timestamps são convertidos. Onde o código usa `.to_time` em objetos `ActiveSupport::TimeWithZone`, o resultado passa a preservar o timezone original em vez de converter para UTC. Verificar em: lógica de datas em `Order` (campo `placed_at`), qualquer comparação de tempo em callbacks.
  - `config.active_record.run_after_transaction_callbacks_in_order_defined = true` — callbacks `after_commit` passam a executar na ordem em que foram definidos no modelo, em vez de em ordem inversa. Verificar nos modelos `Order` e `ShippingAddress`, que têm múltiplos callbacks.
  - `config.active_record.use_yaml_unsafe_load = false` — melhoria de segurança na desserialização YAML. Sem impacto direto neste projeto (não usa `serialize` com tipos customizados).

#### `config/environments/production.rb`
- Sem mudanças obrigatórias em relação ao 8.0. O `rails app:update` pode sugerir ajustes de logging ou de exception handling — avaliar antes de aceitar.

#### Novo arquivo: `config/ci.rb`
O `rails app:update` no 8.1 oferece criar `config/ci.rb` — configuração para integração contínua local. **Aceitar o arquivo mas não configurar agora** — fica como tarefa futura junto com a expansão da cobertura de testes.

#### `config/initializers/`
Sem mudanças obrigatórias. O `rails app:update` pode oferecer atualizações de `content_security_policy.rb` — comparar antes de aceitar.

#### Novos defaults que **não serão adotados** na Etapa E
Conforme instrução: as features novas do 8.1 (Job Continuations, Local CI, Markdown nativo) **não são ativadas neste upgrade**. O objetivo da Etapa E é apenas trocar `config.load_defaults 8.0` por `8.1` e corrigir os breaking changes — features novas ficam como tarefas futuras independentes.

---

## 4. Decisões a Tomar Antes de Executar

### Decisão 1 — Solid Queue: adotar agora ou manter `:async`?

**Contexto:** Atualmente produção usa `:async` (in-memory, padrão do Rails quando nada é configurado). Heroku reinicia dynos diariamente — toda fila pendente é perdida. Isso afeta `OrderMailer.deliver_later`.

**Opção A — Adotar Solid Queue no upgrade 8.0:**
- Prós: resolve o problema de e-mails perdidos sem precisar de Redis ou dyno extra. Solid Queue usa PostgreSQL, que já temos.
- Contras: adiciona tabelas novas ao banco (`solid_queue_jobs`, etc.), exige que o worker rode junto com o web process (via `config.solid_queue.connects_to` + Puma plugin) ou como processo separado (Procfile).
- **No Heroku com um único dyno:** Solid Queue pode rodar embutido no processo Puma usando o plugin `solid_queue`. Não precisa de dyno extra.
- **Recomendação: ADOTAR.** O problema de e-mails perdidos é real e afeta usuários agora.

**Opção B — Manter `:async` e resolver depois:**
- Prós: menos mudanças no upgrade.
- Contras: o bug de e-mails em produção continua. Dívida técnica documentada no AUDIT.md permanece.

---

### Decisão 2 — Solid Cache: adotar agora?

**Contexto:** Projeto não usa cache de forma significativa hoje. `config.cache_store` não está configurado em produção (usa `:memory_store` por default). Não há `fragment_cache` ou `Rails.cache` nas views.

**Recomendação: ADOTAR passivamente.** Configurar `config.cache_store = :solid_cache_store` no 8.0 — tem impacto zero no comportamento atual e abre espaço para uso futuro de cache sem infraestrutura adicional.

---

### Decisão 3 — Solid Cable: adotar?

**Contexto:** Action Cable não é usado no projeto. `cable.yml` referencia Redis mas a gem `redis` está comentada no Gemfile — inconsistência inativa.

**Recomendação: NÃO ADOTAR. Limpar.** No upgrade 8.0, simplificar `cable.yml` para usar `adapter: async` em todos os ambientes (inclusive production) enquanto Action Cable não for necessário. Isso resolve a inconsistência sem adicionar tabelas desnecessárias.

---

### Decisão 4 — Importmap ou migrar para esbuild/jsbundling?

**Contexto:** Importmap funciona bem para o projeto atual. Não há JavaScript complexo que justifique build step. Bootstrap 5 é importado via gem + Sprockets.

**Recomendação: MANTER Importmap.** Migrar para esbuild introduz Node como dependência de build, aumenta complexidade do deploy, e não traz benefício real para este projeto.

---

### Decisão 5 — Sprockets ou migrar para Propshaft?

**Contexto:** Sprockets 4.2.2 está em uso. Propshaft é o novo default do Rails 8, mas Sprockets ainda é suportado.

**Recomendação: MANTER Sprockets no upgrade.** Migrar para Propshaft é uma tarefa separada que exige auditar todas as referências de assets (`asset_path`, `image_tag`, `stylesheet_link_tag`). Fazer isso junto com o upgrade de Rails é desnecessário e aumenta o risco. Planejar como tarefa futura independente.

---

### Decisão 6 — sassc-rails ou migrar para dartsass-rails?

**Contexto:** `sassc-rails` está deprecated. Usa LibSass (abandonado). Funciona, mas é dívida técnica.

**Recomendação: MIGRAR para `dartsass-rails` ANTES do upgrade para 8.0,** como tarefa separada. Fazer a migração enquanto ainda está no 7.2 reduz variáveis. A migração exige:
1. Substituir `gem "sassc-rails"` por `gem "dartsass-rails"` no Gemfile.
2. Revisar arquivos SCSS: Dart Sass é mais estrito com `@import` (deprecated na especificação Sass). Substituir por `@use` e `@forward`.
3. Verificar que o Bootstrap ainda compila corretamente — a gem `bootstrap` (5.3.5) já usa sintaxe compatível.

---

## 5. Plano de Validação Manual

Como a cobertura de testes é ~1%, cada etapa do upgrade precisa de validação manual completa antes do deploy. Executar em ambiente de desenvolvimento com `RAILS_ENV=development`.

### Fluxo 1 — Cadastro e autenticação (Devise)
- [ ] Acessar `/users/sign_up`, preencher formulário, submeter
- [ ] Receber e-mail de confirmação (verificar no letter_opener em `/letter_opener`)
- [ ] Clicar no link de confirmação
- [ ] Fazer login com as credenciais criadas
- [ ] Acessar `/users/edit`, alterar nome
- [ ] Fazer logout
- [ ] Tentar acessar `/orders/mine` sem estar logado — deve redirecionar para login
- [ ] Fazer login com conta existente via "Esqueci minha senha" (e-mail de reset)

### Fluxo 2 — Catálogo e busca
- [ ] Acessar `/screws` — listagem deve carregar com imagens e paginação
- [ ] Usar campo de busca com texto parcial
- [ ] Filtrar por fabricante (automaker) e modelo
- [ ] Acessar a página de um parafuso (`/screws/:slug`) — imagens devem carregar via Cloudinary
- [ ] Verificar que slugs amigáveis (friendly_id) continuam funcionando

### Fluxo 3 — Carrinho
- [ ] Adicionar produto ao carrinho
- [ ] Aumentar/diminuir quantidade
- [ ] Remover item
- [ ] Adicionar múltiplos produtos
- [ ] Limpar carrinho
- [ ] Verificar que o carrinho persiste na sessão ao navegar entre páginas

### Fluxo 4 — Checkout completo (sem pagamento real)
- [ ] Com carrinho preenchido, acessar `/orders/new`
- [ ] Preencher formulário de endereço manualmente
- [ ] Se logado: usar endereço salvo da lista
- [ ] Usar lookup de CEP (campo CEP deve preencher os outros campos via ViaCEP)
- [ ] Verificar cálculo de frete no resumo
- [ ] Submeter o pedido — deve criar o `Order` e redirecionar para checkout Stripe
- [ ] **NÃO completar o pagamento** — apenas verificar que chegou na tela do Stripe
- [ ] Verificar que e-mail de "pedido pendente" foi gerado (letter_opener)
- [ ] Verificar URL da página `thank_you` para pedido recém-criado

### Fluxo 5 — Webhook do Stripe
- [ ] Usar Stripe CLI: `stripe listen --forward-to localhost:3000/webhooks/stripe`
- [ ] Disparar evento de teste: `stripe trigger checkout.session.completed`
- [ ] Verificar nos logs que o evento foi recebido e processado
- [ ] Verificar que o `Order` teve `payment_status` atualizado para `paid`
- [ ] Verificar que e-mail de "pagamento confirmado" foi gerado
- [ ] Disparar o mesmo evento duas vezes — o segundo deve ser ignorado (idempotência)

### Fluxo 6 — Visualização de pedido
- [ ] Acessar `/orders/:id` logado como dono do pedido — deve mostrar detalhes
- [ ] Acessar `/orders/:id` logado como outro usuário — deve retornar 404 ou redirect
- [ ] Acessar `/orders/mine` — lista de pedidos do usuário logado
- [ ] Acessar URL de `thank_you` com `session[:last_order_id]` válido (como guest)

### Fluxo 7 — Endereços de entrega
- [ ] Acessar `/shipping_addresses/new`, criar endereço
- [ ] Criar segundo endereço, marcar como padrão
- [ ] Verificar que o primeiro não é mais padrão
- [ ] Editar endereço existente
- [ ] Excluir endereço

### Fluxo 8 — Área Admin
- [ ] Acessar `/admin` sem autenticação — deve pedir HTTP Basic Auth
- [ ] Acessar com credenciais corretas — deve entrar
- [ ] Acessar `/admin/screws` — listagem com imagens
- [ ] Editar um screw: alterar descrição, preço, estoque
- [ ] Upload de nova imagem — verificar que vai para Cloudinary
- [ ] Acessar `/admin/orders` — listagem de pedidos
- [ ] Acessar detalhes de um pedido

### Fluxo 9 — Imagens e Active Storage
- [ ] Em desenvolvimento: upload de imagem para screw — deve ir para storage local
- [ ] Em produção (após deploy): verificar que imagens existentes continuam acessíveis via Cloudinary
- [ ] Upload de nova imagem em produção: verificar URL gerada com domínio Cloudinary

---

## 6. Plano de Rollback

### Princípio geral
Cada etapa do upgrade vive em um branch isolado. Nenhum merge para `master` sem validação manual completa. Deploy para Heroku só após o merge.

### Etapa 1: 7.1 → 7.2

**Antes de começar:**
```bash
git checkout -b upgrade/rails-7.2
cp Gemfile.lock Gemfile.lock.7.1-backup
git add Gemfile.lock.7.1-backup
git commit -m "chore: backup Gemfile.lock before Rails 7.2 upgrade"
```

**Se precisar reverter:**
```bash
git checkout master
# O branch upgrade/rails-7.2 pode ser deletado ou mantido para referência
```

Sem migrations novas em `rails app:update` (só mudanças de config) — não há schema para reverter.

### Etapa 2: sassc-rails → dartsass-rails (pode ser feita junto com 7.2 ou antes)

**Antes de começar:**
```bash
git checkout -b upgrade/dartsass
# snapshot dos arquivos SCSS antes de qualquer mudança
```

**Se a compilação SCSS quebrar:**
```bash
git checkout master
# retorna sassc-rails no Gemfile, bundle install
```

Sem migrations. Rollback é simples.

### Etapa D1: 7.2 → 8.0 (Rails puro, sem Solid Queue/Cache)

**Antes de começar:**
```bash
git checkout -b upgrade/rails-8.0
cp Gemfile.lock Gemfile.lock.7.2-backup
git add Gemfile.lock.7.2-backup
git commit -m "chore: backup Gemfile.lock before Rails 8.0 upgrade"
```

**Se algo crítico quebrar em produção:**
1. Reverter o deploy: `git push heroku upgrade/rails-7.2:main --force`
   - **Requer aprovação explícita antes de executar.**
2. D1 não adiciona migrations — rollback de deploy é suficiente, sem necessidade de `db:rollback`.

### Etapa D2: Adoção do Solid Queue

**Antes de começar:**
```bash
git checkout -b feature/solid-queue
```

Solid Queue cria suas próprias migrations. Se precisar reverter após deploy:
```bash
# Em produção (Heroku):
heroku run bin/rails db:rollback STEP=N  # N = número de migrations do Solid Queue
git push heroku master:main --force      # Requer aprovação explícita
```

As migrations do Solid Queue são não-destrutivas (só adicionam tabelas) — um rollback não apaga dados existentes de pedidos ou usuários.

### Etapa D3: Adoção do Solid Cache

**Antes de começar:**
```bash
git checkout -b feature/solid-cache
```

Solid Cache também cria migrations próprias. Rollback análogo ao D2. Impacto zero em dados de negócio (cache é descartável por natureza).

### O que NÃO precisa de rollback de banco
- Mudanças em `config/` e `config/environments/` — apenas arquivos de configuração.
- Mudança de versão do Rails no Gemfile.
- Migração de `sassc-rails` para `dartsass-rails`.

### Etapa E: 8.0 → 8.1

**Antes de começar:**
```bash
git checkout -b upgrade/rails-8.1
cp Gemfile.lock Gemfile.lock.8.0-backup
git add Gemfile.lock.8.0-backup
git commit -m "chore: backup Gemfile.lock before Rails 8.1 upgrade"
```

**Se algo crítico quebrar em produção:**
1. Reverter o deploy: `git push heroku upgrade/rails-8.0:main --force`
   - **Requer aprovação explícita antes de executar.**
2. Etapa E não adiciona migrations — rollback de deploy é suficiente.

O risco mais provável da Etapa E é o novo default `run_after_transaction_callbacks_in_order_defined = true` mudando comportamento de callbacks. Se isso ocorrer: desabilitar explicitamente o novo default via `config.active_record.run_after_transaction_callbacks_in_order_defined = false` em `application.rb` e investigar o comportamento esperado antes de reabilitar.

### Backup antes de cada deploy
O backup do banco deve ser feito como **primeiro passo de toda etapa que inclui deploy para produção** (B, C, D1, D2, D3, E):
```bash
heroku pg:backups:capture --app trscrews-prod-4185ac87e394
```

---

## 7. Cronograma Sugerido

Cada etapa é independente e pode ser pausada/retomada. Nenhuma etapa é pré-requisito para as outras fora da sequência indicada.

---

### Etapa A — Preparação (1–2h) · PRÉ-REQUISITO para todas as demais

**Objetivo:** Resolver pendências antes de tocar no Rails.

1. Fazer backup do banco de produção via Heroku PG.
2. Verificar compatibilidade da `activestorage-cloudinary-service` 0.2.3 com Rails 8: abrir o repositório da gem no GitHub, checar issues abertas, último commit, PRs pendentes, e se há menção explícita de compatibilidade com Rails 8.
   - **Se houver suporte confirmado:** seguir o plano normal.
   - **Se não houver:** executar o Plano B abaixo antes de avançar para a Etapa C.

   #### Plano B — Substituição de `activestorage-cloudinary-service` pelo SDK nativo

   A alternativa é configurar o Active Storage para usar o Cloudinary SDK diretamente, sem depender da gem de comunidade. O SDK oficial (`cloudinary` 2.x) já expõe um serviço compatível com Active Storage via `Cloudinary::CarrierWave` ou via configuração do `storage.yml` com o serviço `Cloudinary`.

   **Trabalho estimado:** 2–4h

   **O que muda:**
   - Remover `gem "activestorage-cloudinary-service"` do Gemfile.
   - Verificar se o Cloudinary SDK 2.x inclui um `ActiveStorage::Service::CloudinaryService` nativo (confirmar na documentação oficial no momento da execução — o SDK evoluiu nessa direção).
   - Ajustar `config/storage.yml` conforme a nova configuração do SDK.
   - Testar exaustivamente o Fluxo 9 (imagens) em staging antes de qualquer deploy.
   - Verificar que URLs de imagens já existentes no banco (`active_storage_blobs`) continuam funcionando — a chave é que o `key` do blob no Cloudinary não mude.

   **Risco:** Médio. O risco principal é quebrar URLs de imagens de produtos existentes em produção. Mitigação: testar no staging com um restore do banco de produção antes de avançar.

   **Decisão de execução:** Se o Plano B for necessário, ele vira uma etapa nova entre A e B, e o cronograma se estende em 2–4h.

3. Limpar branches locais mergeadas (16 branches locais, maioria histórica).
4. Garantir que o deploy atual está funcionando: `git push heroku master`.

---

### Etapa A.5 — Configurar app de staging no Heroku (1–2h) · PRÉ-REQUISITO para B em diante

**Objetivo:** Ter um ambiente espelho da produção onde cada etapa do upgrade é validada antes de ir para produção real.

1. Criar novo app no Heroku:
   ```bash
   heroku create trscrews-staging --remote staging
   heroku addons:create heroku-postgresql:essential-0 --app trscrews-staging
   ```
2. Fazer backup do banco de produção e restaurar no staging:
   ```bash
   heroku pg:backups:capture --app trscrews-prod-4185ac87e394
   heroku pg:backups:restore <backup_url> DATABASE_URL --app trscrews-staging
   ```
3. Configurar ENV vars no staging — usar os mesmos valores de produção, **com exceção obrigatória:**
   - `STRIPE_SECRET_KEY` e `STRIPE_PUBLISHABLE_KEY`: usar chaves **test** do Stripe, não live.
   - `STRIPE_SIGNING_SECRET`: usar o secret de webhook do ambiente test.
   - Demais vars (Cloudinary, SMTP, APP_HOST, etc.): configurar equivalentes de staging.
4. Fazer deploy da branch `master` atual para staging:
   ```bash
   git push staging master
   heroku run bin/rails db:migrate --app trscrews-staging
   ```
5. Executar todos os 9 fluxos de validação manual no staging com o estado atual (Rails 7.1) — confirmar que tudo passa antes de começar qualquer upgrade.

**A partir desta etapa:** toda branch de upgrade é deployada primeiro em staging (`git push staging <branch>:main`), validada manualmente com os 9 fluxos, e só depois mergeada em `master` e deployada em produção.

---

### Etapa B — Migrar sassc-rails → dartsass-rails (1–2h)

**Objetivo:** Eliminar dependência deprecated antes de subir de versão do Rails.

1. **Backup do banco de produção:** `heroku pg:backups:capture --app trscrews-prod-4185ac87e394`
2. `git checkout -b upgrade/dartsass`
3. Substituir `gem "sassc-rails"` por `gem "dartsass-rails"` no Gemfile.
4. `bundle install`.
5. Auditar arquivos SCSS: substituir `@import` por `@use`/`@forward` onde necessário.
6. Verificar que `bin/rails assets:precompile` passa sem erros.
7. Deploy para **staging**: `git push staging upgrade/dartsass:main`
8. Executar Fluxo 2 (catálogo) e Fluxo 8 (admin) no staging — foco visual nos estilos.
9. Merge para `master`, deploy para produção.

---

### Etapa C — Upgrade 7.1 → 7.2 (3–4h)

**Objetivo:** Primeiro salto de versão com coleta de deprecation warnings.

1. **Backup do banco de produção:** `heroku pg:backups:capture --app trscrews-prod-4185ac87e394`
2. `git checkout -b upgrade/rails-7.2`
3. Atualizar `rails` para `~> 7.2` no Gemfile.
4. `bundle update rails` — resolver conflitos de versão de gems dependentes.
5. `bin/rails app:update` — aceitar mudanças de config com atenção (não aceitar cegamente).
6. Atualizar `config.load_defaults` para `7.2` em `application.rb`.
7. Rodar `bin/rails server` e observar todos os `DEPRECATION WARNING` no terminal — documentar cada um.
8. Corrigir os deprecations encontrados.
9. Executar todos os 9 fluxos do checklist manual **em staging primeiro**.
10. `bin/rails test` — reportar resultado (esperado: 3 testes passando).
11. Deploy para staging: `git push staging upgrade/rails-7.2:main` — validar os 9 fluxos.
12. Merge para `master`, deploy para produção.
13. Monitorar logs de produção por 24h antes de avançar para a D1.

---

### Etapa D1 — Upgrade 7.2 → 8.0 puro (3–4h)

**Objetivo:** Validar APENAS o upgrade do Rails. Sem Solid Queue, sem Solid Cache — jobs continuam `:async`, cache continua `:memory_store`.

1. **Backup do banco de produção:** `heroku pg:backups:capture --app trscrews-prod-4185ac87e394`
2. `git checkout -b upgrade/rails-8.0`
3. Atualizar `rails` para `~> 8.0` no Gemfile.
4. Remover linha comentada do `gem "redis"` (limpeza).
5. `bundle update rails` — resolver conflitos.
6. `bin/rails app:update` — aceitar mudanças de config com atenção. **Não** ativar Solid Queue ou Solid Cache mesmo que o gerador sugira.
7. Atualizar `config.load_defaults` para `8.0`.
8. Simplificar `cable.yml`: trocar `adapter: redis` em production por `adapter: async`.
9. Atualizar URL placeholder no `config/initializers/stripe.rb`.
10. Executar todos os 9 fluxos do checklist manual em desenvolvimento.
11. `bin/rails test` — reportar resultado.
12. Deploy para **staging**: `git push staging upgrade/rails-8.0:main`
13. Executar todos os 9 fluxos no staging — especialmente Fluxos 5 (webhook) e 9 (imagens Cloudinary).
14. Merge para `master`, deploy para produção.
15. Monitorar logs de produção por **48h** antes de avançar para D2.

---

### Etapa D2 — Adoção do Solid Queue (2–3h)

**Objetivo:** Resolver o problema de e-mails perdidos em restart do dyno. Executar somente após D1 estável em produção por 48h.

1. **Backup do banco de produção:** `heroku pg:backups:capture --app trscrews-prod-4185ac87e394`
2. `git checkout -b feature/solid-queue`
3. Adicionar `gem "solid_queue"` ao Gemfile.
4. `bundle install`.
5. `bin/rails solid_queue:install` — gera migrations e arquivos de configuração.
6. `bin/rails db:migrate`.
7. Configurar `config/environments/production.rb`: `config.active_job.queue_adapter = :solid_queue`.
8. Configurar `puma.rb` para rodar o Solid Queue embutido no processo Puma (via plugin `solid_queue`) — sem dyno extra no Heroku.
9. Verificar em desenvolvimento que `deliver_later` enfileira jobs corretamente.
10. Deploy para **staging**: `git push staging feature/solid-queue:main` — executar `heroku run bin/rails db:migrate --app trscrews-staging`.
11. No staging: executar Fluxo 4 (checkout — verificar que e-mail de pedido pendente é gerado) e Fluxo 5 (webhook — verificar que e-mail de pagamento confirmado é gerado).
12. Confirmar nos logs do staging que o worker Solid Queue está processando os jobs.
13. `bin/rails test` — reportar resultado.
14. Merge para `master`, deploy para produção, rodar migrations.
15. Monitorar logs de produção por 24h — verificar que jobs de e-mail são processados após restart do dyno.

---

### Etapa D3 — Adoção do Solid Cache (1–2h)

**Objetivo:** Configurar cache persistente no PostgreSQL para uso futuro. Mudança passiva — sem impacto no comportamento atual. Executar somente após D2 estável.

1. **Backup do banco de produção:** `heroku pg:backups:capture --app trscrews-prod-4185ac87e394`
2. `git checkout -b feature/solid-cache`
3. Adicionar `gem "solid_cache"` ao Gemfile.
4. `bundle install`.
5. `bin/rails solid_cache:install` — gera migrations e configuração.
6. `bin/rails db:migrate`.
7. Configurar `config/environments/production.rb`: `config.cache_store = :solid_cache_store`.
8. Deploy para **staging**: `git push staging feature/solid-cache:main` — rodar migrations no staging.
9. Executar Fluxos 2 (catálogo) e 8 (admin) no staging — confirmar que nada quebrou.
10. `bin/rails test` — reportar resultado.
11. Merge para `master`, deploy para produção, rodar migrations.
12. Monitorar logs por **48h** antes de avançar para a Etapa E.

---

### Etapa E — Upgrade 8.0 → 8.1.3 (2–3h)

**Objetivo:** Chegar à versão alvo final com janela de suporte ativa. Executar somente após D3 estável em produção por ≥48h. **Nenhuma feature nova do 8.1 é ativada aqui** — apenas o upgrade de versão e correção dos novos defaults.

1. **Backup do banco de produção:** `heroku pg:backups:capture --app trscrews-prod-4185ac87e394`
2. `git checkout -b upgrade/rails-8.1`
3. Atualizar `rails` para `~> 8.1` no Gemfile (ou `">= 8.1.3"`).
4. `bundle update rails` — gems do ecossistema Rails (solid_queue, solid_cache, importmap-rails, turbo-rails, stimulus-rails) recebem atualização junto.
5. `bin/rails app:update` — aceitar mudanças com atenção. Ao oferecer `config/ci.rb`: aceitar o arquivo, mas não configurar conteúdo agora.
6. Atualizar `config.load_defaults` para `8.1` em `application.rb`.
7. Verificar comportamento dos novos defaults (ver §3.3):
   - Rodar `bin/rails server` e navegar pelos fluxos principais observando o log para erros de callback ou conversão de tempo.
   - Verificar especificamente: login/logout com `remember_me`, criação de pedido (callbacks de `Order`), criação de endereço (callbacks de `ShippingAddress`).
8. Executar todos os 9 fluxos do checklist manual em desenvolvimento.
9. `bin/rails test` — reportar resultado.
10. Deploy para **staging**: `git push staging upgrade/rails-8.1:main`
11. Executar todos os 9 fluxos no staging, com atenção ao Fluxo 1 (autenticação Devise), Fluxo 4 (checkout), Fluxo 5 (webhook).
12. Merge para `master`, deploy para produção.
13. Monitorar logs de produção por **48h** — verificar ausência de erros de callback, tempo e serialização.

---

### Resumo visual

```
Hoje  [Rails 7.1 EOL — sem suporte de segurança]
 │
 ├─ Etapa A: Preparação (1–2h)
 │    Backup BD · verificar activestorage-cloudinary (+ Plano B se necessário)
 │    · limpar branches · confirmar deploy atual funcionando
 │
 ├─ Etapa A.5: Staging no Heroku (1–2h)  ← PRÉ-REQUISITO para B em diante
 │    Criar app staging · restaurar backup de prod · configurar ENVs (Stripe test)
 │    · validar os 9 fluxos no estado atual (Rails 7.1)
 │
 ├─ Etapa B: sassc → dartsass (1–2h)
 │    Backup BD · migrar SCSS · validar no staging · deploy prod
 │
 ├─ Etapa C: Rails 7.1 → 7.2 (3–4h)
 │    Backup BD · app:update · coletar deprecations · staging · deploy prod
 │    · aguardar 24h estável
 │
 ├─ Etapa D1: Rails 7.2 → 8.0 puro (3–4h)
 │    Backup BD · app:update · SEM Solid Queue/Cache · staging · deploy prod
 │    · aguardar 48h estável
 │
 ├─ Etapa D2: Solid Queue (2–3h)
 │    Backup BD · instalar · migrations · staging · deploy prod
 │    · aguardar 24h (confirmar e-mails após restart)
 │
 ├─ Etapa D3: Solid Cache (1–2h)
 │    Backup BD · instalar · migrations · staging · deploy prod
 │    · aguardar 48h estável
 │
 └─ Etapa E: Rails 8.0 → 8.1.3 (2–3h)  ← versão alvo final
      Backup BD · app:update · load_defaults 8.1 · verificar callbacks e timezone
      · staging · deploy prod · aguardar 48h
      [Rails 8.1 com bug fixes até outubro de 2026]

Total estimado: 14–20h distribuídas ao longo de ~4 semanas
(cada etapa separada por período de estabilidade monitorada)
```

---

## Apêndice: Flags de risco elevado

Estas são as situações que, se encontradas durante o upgrade, exigem parada e análise antes de continuar:

| Situação | Etapa | O que fazer |
|---|---|---|
| `activestorage-cloudinary-service` não funciona com Rails 8 | D1 | Parar. Executar Plano B (substituição pelo SDK nativo) antes de continuar. |
| Stripe webhook retorna 500 após qualquer upgrade | qualquer | Reverter imediatamente. Investigar em staging. |
| Imagens de produtos quebram em produção | qualquer | Reverter o deploy. Investigar Active Storage. |
| Checkout não completa pedido | qualquer | Reverter. Investigar `OrdersController#create`. |
| Devise não autentica usuários existentes | qualquer | Reverter. Checar se mudança de `config.load_defaults` alterou hash de senha ou serialização de sessão. |
| Callbacks de `Order` ou `ShippingAddress` executam em ordem diferente | E | Não reverter imediatamente — desabilitar o novo default via `config.active_record.run_after_transaction_callbacks_in_order_defined = false` e investigar o comportamento esperado. |
| Timestamps em pedidos aparecem com timezone errado | E | Provavelmente causado pelo novo default `to_time_preserves_timezone = :zone`. Verificar exibição de datas nas views e nos e-mails. Reverter o default se necessário. |
