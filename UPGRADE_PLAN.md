# Plano de Upgrade: Rails 7.1.5.1 → Rails 8.1.3.1

**Elaborado em:** 2026-05-19 · **Revisado em:** 2026-05-19  
**Estado atual:** Rails 8.0.5.1 · Ruby 3.3.5 · em produção no Heroku (v55)  
**Objetivo:** Migrar para Rails 8.1.3.1 com zero downtime e zero regressões em produção  

> **⚠️ CONTEXTO DE SEGURANÇA — LEIA ANTES DE QUALQUER COISA**
>
> Rails 7.1 está **end-of-life desde outubro de 2025**. Não recebe mais bug fixes nem security patches. Estamos rodando produção em versão sem suporte de segurança — este upgrade não é melhoria estrutural opcional, é **correção de dívida de segurança ativa**. *(Resolvido em parte: a D1 tirou a produção do 7.1 e a levou ao 8.0.5.1 em 2026-08-13.)*
>
> A versão alvo é **Rails 8.1.3.1**. Parar em Rails 8.0 seria insuficiente: a série 8.0 foi lançada em **novembro de 2024**, encerrou a janela de bug fixes por volta de **novembro de 2025** e **já está em modo security-only**, com o suporte de segurança terminando por volta de **novembro de 2026**.
>
> **[CORRIGIDO 2026-08-12]** O texto original dizia que a série 8.0 "entra em modo só security patches em maio de 2026". Está errado — ela já entrou. Ver `RAILS_80_MIGRATION.md` §0, correção 3. A consequência prática é que **a Etapa E deixou de ser opcional**: ao concluir a D1 estamos numa série com ~3 meses de janela restante.
>
> **[CORRIGIDO 2026-08-13 — data e versão da série 8.1]** O texto original dizia que a versão alvo era o "**Rails 8.1.3** (lançado em março de 2026), que está em produção em Shopify e HEY há mais de 7 meses e recebe bug fixes até outubro de 2026". Havia dois erros e uma contradição interna (não se está em produção há 7 meses uma versão lançada há 5):
>
> - **A série 8.1.0 foi lançada em 2025-10-22**, não em março de 2026. Março de 2026 (dia 24) é a data do **patch** 8.1.3, não da série. A alegação dos "7+ meses em produção" bate com a data da série.
> - **A última da série é a 8.1.3.1** (2026-07-29), não a 8.1.3. Detalhe útil: **8.1.3.1 e 8.0.5.1 saíram no mesmo dia** — são o par de releases da mesma correção de segurança, e nós já absorvemos esse patch no ramo 8.0.
> - **A janela de bug fixes é mais curta do que o texto sugeria.** Pela política oficial (1 ano de bug fixes e 2 de segurança, contados da **primeira** release da série), o 8.1 tem bug fixes até ~**2026-10-22** e segurança até ~**2027-10-22**. "Até outubro de 2026" estava certo por acidente, derivado da data errada.
>
> **A conclusão não muda — subir continua claramente certo** (segurança do 8.0 acaba ~nov/2026; a do 8.1 vai até ~out/2027), e **não existe Rails 8.2**: a última release de qualquer série é a 8.1.3.1. O que muda é o tom: a Etapa E compra **paridade com a série corrente**, não um ano tranquilo. Ver `RAILS_81_MIGRATION.md` §0, correções 1–3.

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

**Problema:** Para em Rails 8.0, que **já está em modo "só security patches"** desde ~novembro de 2025 (série lançada em nov/2024). Adotar 8.0 como destino final significa chegar a uma versão já fora da janela de bug fixes — e precisar de um novo upgrade em breve de qualquer jeito. *(Data corrigida em 2026-08-12; ver `RAILS_80_MIGRATION.md` §0.)*

**Tempo estimado:** ~7–8h.  
**Regressão esperada:** Baixa por etapa.

---

#### (C) Upgrade completo: 7.1 → 7.2 → 8.0 → 8.1 ← **RECOMENDADO**

**Como funciona:** Três saltos incrementais. Cada um deployado e validado antes de avançar. A guideline oficial do Rails recomenda explicitamente passar por 8.0 antes de 8.1.

**Por que 8.1 é o destino correto:**
- A série 8.1 foi lançada em **outubro de 2025** e está em produção em Shopify e HEY desde então — o ecossistema está maduro. *(Data corrigida em 2026-08-13; o original dizia "8.1.3 foi lançado em março de 2026", confundindo a data do patch com a da série.)*
- A série 8.1 recebe bug fixes até ~**outubro de 2026** e security fixes até ~**outubro de 2027**. É a série corrente do framework — não existe 8.2. *(Janela de segurança acrescentada em 2026-08-13: é ela, e não a de bug fixes, que sustenta a decisão.)*
- Rails 8.0 **já está** em modo "só security patches" (bug fixes encerrados ~nov/2025, segurança até ~nov/2026): parar nele é quase equivalente a não sair do 7.1 em termos de suporte ativo. *(Data corrigida em 2026-08-12.)*
- Cada salto incremental expõe um conjunto menor de mudanças — o 7.2 detecta deprecations do 8.0, o 8.0 detecta deprecations do 8.1.

**Tempo estimado:** ~12–17h distribuídas em ~3 semanas (inclui D1/D2/D3 para Solid Queue/Cache).  
**Regressão esperada:** Baixa por etapa, cada uma isolada e validada.

---

### Recomendação: Opção C

**Justificativa:** Estamos em produção em versão EOL. O objetivo do upgrade não é só modernizar — é sair de uma versão sem suporte de segurança e chegar em uma versão com janela de suporte real. Fazer isso em passos incrementais (7.2 como detector de problemas, 8.0 como ponte obrigatória, 8.1 como destino) é a abordagem mais segura dado que temos ~1% de cobertura de testes. Cada etapa pode ser validada manualmente e revertida de forma independente.

> **Contexto do projeto (simplifica o plano):** O app está no Heroku mas não tem usuários reais nem compras efetuadas — todos os dados são de teste. Não há domínio próprio. Isso elimina a necessidade de um ambiente de staging separado: o próprio Heroku serve como ambiente de validação pós-deploy. Cada etapa segue o padrão: validar localmente → deploy para Heroku → validar no Heroku → prosseguir quando confirmar estabilidade (sem prazo fixo de horas).

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

**Nota — Devise e `to_time_preserves_timezone`:** `config.active_support.to_time_preserves_timezone = :zone` é novo default do **Rails 8.0**, não do 8.1. *(Corrigido em 2026-08-12; ver `RAILS_80_MIGRATION.md` §0, correção 2.)* **Impacto real medido neste projeto: zero** — `grep -rn "\.to_time\b" app/ config/ lib/` não retorna nenhuma ocorrência. Ativado na D1 junto com `load_defaults 8.0`, sem regressão observada.

**Nota Rails 8.0 — Devise 4.9.4 (risco superestimado):** o plano original classificava o Devise como risco alto da D1, por causa do lazy route loading do Rails 8.0. Na execução (2026-08-12) o bug foi **reproduzido** (`Devise::Mapping.find_scope!` levanta `Could not find a valid mapping`), mas a suíte passou 17/17 sem contorno — nenhum teste chama `sign_in`, que é o único caminho que alcança o bug. O contorno foi aplicado mesmo assim, como proteção. Ver Etapa F e `RAILS_80_MIGRATION.md` §4.2.

### Gems de imagem e storage — ATENÇÃO

| Gem | Atual | Rails 8.0 compat | Rails 8.1 compat | Risco | Ação |
|---|---|---|---|---|---|
| cloudinary | 2.4.0 | ✅ SDK não depende de versão Rails | ✅ | Baixo | Manter |
| ~~activestorage-cloudinary-service~~ | ~~0.2.3~~ | — | — | — | **REMOVIDA DO PROJETO** |

> **[CORRIGIDO 2026-08-12] O maior risco declarado deste plano não existe mais.** A gem
> `activestorage-cloudinary-service` **não está no `Gemfile` nem no `Gemfile.lock`** — foi removida do
> projeto em algum momento entre a elaboração do plano (maio/2026) e a execução da D1. O serviço de
> Active Storage vem do próprio SDK `cloudinary` 2.4.0, configurado em `config/storage.yml` com
> `service: Cloudinary`. Ver `RAILS_80_MIGRATION.md` §0, correção 1.
>
> **Consequência:** o "Plano B" da Etapa A é desnecessário e o risco de imagens no upgrade cai de
> **Alto** para **Baixo**. Na D1 (executada em 2026-08-12) nenhum ajuste de Active Storage foi
> necessário. A validação do Fluxo 9 (imagens) segue no checklist, mas como verificação de rotina,
> não como mitigação de risco alto.

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
- **[CORRIGIDO 2026-08-12]** Os defaults listados originalmente aqui (`show_exceptions = :rescuable` e `query_log_tags_enabled`) **não são defaults do 8.0**. O `show_exceptions` Boolean→Symbol foi tratado na Etapa C, e o `query_log_tags_enabled` é uma linha do template de `development.rb`, não um default do framework. Ver `RAILS_80_MIGRATION.md` §0, correção 4.
- Os defaults do 8.0 são **exatamente três** (confirmado na fonte do `railties`, onde `load_defaults "8.0"` é `load_defaults "7.2"` mais estas três linhas):

  | Config | O que faz | Impacto medido na D1 |
  |---|---|---|
  | `active_support.to_time_preserves_timezone = :zone` | `to_time` preserva o timezone do receptor | **Zero** — nenhum `.to_time` no código |
  | `action_dispatch.strict_freshness = true` | com `If-Modified-Since` + `If-None-Match`, considera só o segundo (RFC 7232 §6) | **Zero** — nenhum `fresh_when`/`stale?` |
  | `Regexp.timeout = 1` | defesa contra ReDoS | Único com superfície real; nossas regexes são triviais, risco está em gems de terceiros — **monitorar log em produção** |

#### `config/environments/production.rb`
- `config.assume_ssl = true` — descomenta a linha comentada existente. Necessário e correto para Heroku.
- **Não** adicionar `queue_adapter` ou `cache_store` na Etapa D1 — isso é D2 e D3 respectivamente.

#### `config/cable.yml` — MUDANÇA IMPORTANTE
Atualmente referencia Redis (que não está no Gemfile). Na Etapa D1, simplificar para `adapter: async` em todos os ambientes, já que Action Cable não é usado. Solid Cable (D3 potencial) não será adotado — ver §4 Decisão 3.

#### Novos arquivos que `rails app:update` vai criar (Etapa D1 — Rails puro)

**[ATUALIZADO 2026-08-12 — o que foi de fato decidido e executado na D1.]** A tabela original mandava
"aceitar" `queue.yml` e `cache.yml` na D1; na execução optou-se por **rejeitar** os dois, para que a D1
não deixasse nenhum artefato de Solid no repo. Nada de Solid entrou.

| Arquivo | Propósito | Ação executada na D1 |
|---|---|---|
| `config/initializers/new_framework_defaults_8_0.rb` | Mecanismo do upgrade (3 flags) | **Aceito** — criado com tudo comentado |
| `public/400.html` | Página de erro 400 (nova no 8.0) | **Aceito** — criado |
| `config/queue.yml` | Configuração do Solid Queue | **Rejeitado** — pertence à D2 |
| `config/cache.yml` | Configuração do Solid Cache | **Rejeitado** — pertence à D3 |
| `bin/jobs` | Worker do Solid Queue | **Rejeitado** — pertence à D2 |
| `bin/dev` | Foreman/Solid | **Rejeitado** — não usamos |
| `config/puma.rb` | Template novo do 8.0 | **Rejeitado** — o template traz `plugin :solid_queue`, remove o `worker_timeout` de dev e derruba o suporte a `RAILS_MIN_THREADS`. Sem ganho funcional |
| `production.rb`, `assets.rb`, `robots.txt`, `application.rb` | Customizados à mão | **Rejeitados** — alterados manualmente depois, linha a linha |
| Docker, Kamal, CI, devcontainer, PWA, Gemfile (rubocop/brakeman) | — | **Rejeitados** — precedente da Etapa C |
| `db/queue_schema.rb` | Schema do Solid Queue | Criar apenas na D2 |
| `db/cache_schema.rb` | Schema do Solid Cache | Criar apenas na D3 |

#### `config/initializers/` — sem mudanças obrigatórias
Os initializers existentes (`stripe.rb`, `devise.rb`, `shipping.rb`, etc.) não precisam mudar para o upgrade em si. `rails app:update` pode oferecer versões novas de `content_security_policy.rb` e `permissions_policy.rb` — comparar antes de aceitar.

---

### 3.3 — Etapa E — 8.0 → 8.1

#### `config/application.rb`
- `config.load_defaults` atualizar para `8.1`

> **[CORRIGIDO 2026-08-13 — esta seção listava os defaults errados.]** O texto original afirmava que
> os novos defaults do 8.1 eram `run_after_transaction_callbacks_in_order_defined = true` e
> `use_yaml_unsafe_load = false`. **Nenhum dos dois é default do 8.1.** Verificado em duas frentes
> independentes (`RAILS_81_MIGRATION.md` §0, correção 4):
>
> - **Na fonte:** o `load_defaults "8.1"` do branch `8-1-stable` não menciona nem callbacks de
>   transação nem YAML.
> - **Em runtime, no nosso app, sob `load_defaults 8.0`:** `run_after_transaction_callbacks_in_order_defined`
>   já é `true` e `use_yaml_unsafe_load` já é `false`. O primeiro é default do **Rails 7.1** —
>   entrou neste projeto na **Etapa C**, não vai entrar na E.
>
> **Consequência: o "risco de ordem de callbacks" da Etapa E NÃO existe.** Os callbacks de `Order`
> (`after_create_commit :assign_order_number!`) e de `ShippingAddress` já rodam na ordem definida
> desde a Etapa C, em produção, sem incidente. Toda orientação deste plano baseada nesse flag —
> o passo 7 do cronograma da E, a linha do Apêndice de riscos e o conselho de rollback da §6 — está
> corrigida nos respectivos lugares.
>
> - ~~`config.active_support.to_time_preserves_timezone = :zone`~~ — **[CORRIGIDO 2026-08-12] não é default do 8.1: é do 8.0**, e já foi ativado na D1 sem impacto (nenhum `.to_time` no código). **[Nota de 2026-08-13]** No `8-1-stable`, o `load_defaults "8.0"` encadeado **não seta mais** esse flag: o suporte a `to_time` preservando hora local do sistema foi removido e o próprio flag foi deprecado no 8.1. Impacto aqui segue **zero** — `grep` por `.to_time` continua devolvendo zero ocorrências.

**Os 7 defaults REAIS do `load_defaults 8.1`**, com o impacto medido neste projeto em 2026-08-13
(detalhamento e evidência de cada um em `RAILS_81_MIGRATION.md` §3):

| # | Config | O que faz | Impacto medido aqui |
|---|---|---|---|
| 1 | `config.yjit = !Rails.env.local?` | Liga YJIT fora de dev/test | **Neutralizado** — nosso `new_framework_defaults_7_2.rb` seta `yjit = false`, e o `initializer :enable_yjit` (índice 377) roda **depois** do `load_config_initializers` (257). Único flag com superfície real |
| 2 | `action_controller.escape_json_responses = false` | Para de escapar entidades HTML em respostas JSON | **Zero** — único `render json:` é o `CepController`, consumido por Stimulus via `fetch` e atribuído a `.value` de inputs, nunca a `innerHTML` |
| 3 | `action_controller.action_on_path_relative_redirect = :raise` | Levanta em `redirect_to` com URL relativa sem barra inicial | **Zero** — auditadas as 37 chamadas de `redirect_to`: todas por helper de rota ou objeto de modelo; zero string literal |
| 4 | `active_record.raise_on_missing_required_finder_order_columns = true` | Levanta `MissingRequiredOrderError` em `#first`/`#last` sem ordem quando o modelo não tem coluna de ordenação | **Zero** — nenhuma tabela `id: false` no schema, nenhum override de `implicit_order_column`/`query_constraints`/`primary_key` |
| 5 | `active_support.escape_js_separators_in_json = false` | Para de escapar U+2028/U+2029 em JSON | **Zero** — mesma superfície do #2 |
| 6 | `action_view.render_tracker = :ruby` | Rastreia dependências entre templates com parser Ruby em vez de regex | **Zero** — não usamos fragment caching (zero `<% cache %>` nas views) |
| 7 | `action_view.remove_hidden_field_autocomplete = true` | Omite `autocomplete="off"` de inputs hidden | **Zero** — cosmético |

**Seis dos sete têm impacto zero medido; o sétimo está neutralizado por configuração que já existe.**

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
git checkout -b refactor/rails-80-upgrade
cp Gemfile.lock Gemfile.lock.7.2-backup   # snapshot LOCAL, não versionado
```

> **[CORRIGIDO 2026-08-12]** O texto original mandava `git add Gemfile.lock.7.2-backup` e commitar o
> snapshot. Isso contradizia a regra `Gemfile.lock.*-backup` do `.gitignore` e versionaria um artefato
> descartável. **O backup é local e ignorado pelo git** — o histórico já guarda o lock anterior, e o
> conteúdo é recuperável a qualquer momento com `git show <sha-anterior>:Gemfile.lock`. Apagar o
> snapshot só depois do deploy da etapa ser validado em produção.

**Se algo crítico quebrar em produção:**
1. Reverter o deploy: `git push heroku <sha-anterior>:master`
   - **Requer aprovação explícita antes de executar.**
2. D1 não adiciona migrations — rollback de deploy é suficiente, sem necessidade de `db:rollback`.
3. Para voltar as dependências em local: `git show <sha-anterior>:Gemfile.lock > Gemfile.lock && bundle install`.

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

> **[CORRIGIDO 2026-08-13]** O texto original dizia: *"O risco mais provável da Etapa E é o novo
> default `run_after_transaction_callbacks_in_order_defined = true` mudando comportamento de
> callbacks. Se isso ocorrer: desabilitar explicitamente o novo default..."*. **Esse flag não é
> default do 8.1** — já está `true` desde a Etapa C (é default do 7.1). O conselho de rollback era
> para um risco inexistente. Ver §3.3 e `RAILS_81_MIGRATION.md` §0, correção 4.

Os dois riscos mais prováveis da Etapa E são de **processo**, não de framework:

1. **Aceitar o `config/cable.yml` do template do 8.1**, que propõe `adapter: solid_cable` em
   produção. Isso reintroduziria uma dependência de Solid que decidimos não adotar (Decisão 3) e
   **desfaria o fix deployado na v55**, que trocou o Redis fantasma por `adapter: async`. Este
   arquivo mudou de categoria desde a D1: lá era pendência a resolver, aqui é conteúdo nosso a
   preservar — e por isso é o mais fácil de aceitar por distração.
   **Mitigação:** `git diff config/cable.yml` obrigatório antes de qualquer commit da etapa.
2. **Rodar `bundle update` sem argumento.** O `Gemfile` traz `gem "pagy"` **sem constraint**, e o
   pagy saltou da série 9 para a **43.x**. Um update amplo levaria o pagy junto e quebraria a
   paginação do catálogo (`pagy/extras/bootstrap`, `pagy/extras/overflow`, `Pagy::DEFAULT[:overflow]`,
   `Pagy::DEFAULT[:limit]`) e os 3 testes que a cobrem.
   **Mitigação:** apenas `bundle update rails`, e revisar o diff do `Gemfile.lock` antes de seguir —
   qualquer mexida em `pagy`, `stripe`, `devise`, `minitest` ou `cloudinary` é sinal de desvio.

Um terceiro, de menor probabilidade mas dano real: **remover o pin `gem "minitest", "~> 5.27"`**
aproveitando o embalo do upgrade. O `activesupport` 8.1.3.1 **continua sem teto** para o minitest
(`>= 5.1`), então isso repetiria a quebra da D1 — suíte inteira deixando de carregar por `LoadError`
em `minitest/mock`. O pin fica; migrar é a Etapa G.

### Padrão de rollback (todas as etapas)

Se algo crítico quebrar após um deploy:

```bash
# 1. Reverter o código (requer aprovação explícita)
git push heroku <branch-anterior>:main --force

# 2. Se havia migrations na etapa: restaurar banco do backup pré-deploy
heroku pg:backups:restore <backup-id> DATABASE_URL --app trscrews-prod --confirm trscrews-prod
```

O `<backup-id>` é o ID do backup capturado no início da etapa (ex: `b003`). Consultar com `heroku pg:backups --app trscrews-prod`.

### Backup antes de cada deploy
O backup do banco deve ser feito como **primeiro passo de toda etapa que inclui deploy para produção** (B, C, D1, D2, D3, E):
```bash
heroku pg:backups:capture --app trscrews-prod
```

---

## 7. Cronograma Sugerido

Cada etapa é independente e pode ser pausada/retomada. Nenhuma etapa é pré-requisito para as outras fora da sequência indicada.

---

### Etapa A — Preparação (1–2h) · PRÉ-REQUISITO para todas as demais

**Objetivo:** Resolver pendências antes de tocar no Rails.

1. Fazer backup do banco de produção via Heroku PG.
2. ~~Verificar compatibilidade da `activestorage-cloudinary-service` 0.2.3 com Rails 8.~~
   **[OBSOLETO 2026-08-12 — PASSO CANCELADO.]** A gem não está mais no projeto (ver §2). Não há o que
   verificar e o **Plano B abaixo é desnecessário**. Mantido no documento apenas como registro
   histórico da análise original; **não executar**.

   #### ~~Plano B~~ — Substituição de `activestorage-cloudinary-service` pelo SDK nativo *(cancelado — a gem já saiu do projeto)*

   A alternativa é configurar o Active Storage para usar o Cloudinary SDK diretamente, sem depender da gem de comunidade. O SDK oficial (`cloudinary` 2.x) já expõe um serviço compatível com Active Storage via `Cloudinary::CarrierWave` ou via configuração do `storage.yml` com o serviço `Cloudinary`.

   **Trabalho estimado:** 2–4h

   **O que muda:**
   - Remover `gem "activestorage-cloudinary-service"` do Gemfile.
   - Verificar se o Cloudinary SDK 2.x inclui um `ActiveStorage::Service::CloudinaryService` nativo (confirmar na documentação oficial no momento da execução — o SDK evoluiu nessa direção).
   - Ajustar `config/storage.yml` conforme a nova configuração do SDK.
   - Testar exaustivamente o Fluxo 9 (imagens) localmente antes de qualquer deploy.
   - Verificar que URLs de imagens já existentes no banco (`active_storage_blobs`) continuam funcionando — a chave é que o `key` do blob no Cloudinary não mude.

   **Risco:** Médio. O risco principal é quebrar URLs de imagens de produtos existentes. Mitigação: validar o Fluxo 9 com cuidado localmente antes do deploy; rollback via `heroku pg:backups:restore` se quebrar em produção.

   **Decisão de execução:** Se o Plano B for necessário, ele vira uma etapa nova entre A e B, e o cronograma se estende em 2–4h.

3. Limpar branches locais mergeadas (16 branches locais, maioria histórica).

---

### Etapa B — Migrar sassc-rails → dartsass-rails (1–2h)

**Objetivo:** Eliminar dependência deprecated antes de subir de versão do Rails.

1. **Backup do banco de produção:** `heroku pg:backups:capture --app trscrews-prod`
2. `git checkout -b upgrade/dartsass`
3. Substituir `gem "sassc-rails"` por `gem "dartsass-rails"` no Gemfile.
4. `bundle install`.
5. Auditar arquivos SCSS: substituir `@import` por `@use`/`@forward` onde necessário.
6. Verificar que `bin/rails assets:precompile` passa sem erros.
7. Executar Fluxo 2 (catálogo) e Fluxo 8 (admin) localmente — confirmar que estilos estão corretos.
8. Merge para `master`, deploy para Heroku.
9. Verificar Fluxo 2 e Fluxo 8 no Heroku após o deploy.

---

### Etapa C — Upgrade 7.1 → 7.2 (3–4h)

**Objetivo:** Primeiro salto de versão com coleta de deprecation warnings.

1. **Backup do banco de produção:** `heroku pg:backups:capture --app trscrews-prod`
2. `git checkout -b upgrade/rails-7.2`
3. Atualizar `rails` para `~> 7.2` no Gemfile.
4. `bundle update rails` — resolver conflitos de versão de gems dependentes.
5. `bin/rails app:update` — aceitar mudanças de config com atenção (não aceitar cegamente).
6. Atualizar `config.load_defaults` para `7.2` em `application.rb`.
7. Rodar `bin/rails server` e observar todos os `DEPRECATION WARNING` no terminal — documentar cada um.
8. Corrigir os deprecations encontrados.
9. Executar todos os 9 fluxos do checklist manual localmente.
10. `bin/rails test` — reportar resultado (esperado: 3 testes passando).
11. Merge para `master`, deploy para Heroku.
12. Verificar os 9 fluxos no Heroku após o deploy.
13. Prosseguir para D1 quando confirmar estabilidade.

---

### Etapa D1 — Upgrade 7.2 → 8.0 puro (3–4h) · ✅ **DEPLOYADA (v53/v54, Rails 8.0.5.1 em produção); fluxos de compra completos pendentes de verificação manual**

> **Status:** executada localmente em 2026-08-12 na branch `refactor/rails-80-upgrade`, mergeada
> (`--no-ff`, `eb59a6f`) e deployada em 2026-08-13 — **v53** (Rails 8.0.5.1) e **v54** (fix do
> `pagy_bootstrap_nav`). **`load_defaults 8.0` · suíte 17 runs / 47 assertions / 0 falhas na época ·
> boot sem uma única `DEPRECATION WARNING`.** Detalhamento completo em `RAILS_80_MIGRATION.md`.
>
> **O que falta:** os fluxos de compra completos (carrinho → checkout → webhook) não foram
> percorridos em produção depois do deploy — produção tem 0 pedidos, então o caminho de compra não
> foi exercitado. Ver passo 13. As demais pendências listadas antes já foram fechadas: `cable.yml`
> em 2026-08-13 (passo 8), `friendly_id` continua em aberto como tarefa própria (upgrade 5.5 → 5.7,
> melhoria e não bug).
>
> **O risco real da etapa não foi o previsto.** O plano apontava o Devise como risco central
> (probabilidade "Alta"); na prática o bug foi reproduzido mas **não é alcançado por nenhum teste**, e a
> suíte passou sem contorno. Quem derrubou a suíte inteira foi o **minitest 6** — listado como risco #6
> genérico, de impacto "Baixo". Ver Etapa G.

**Objetivo:** Validar APENAS o upgrade do Rails. Sem Solid Queue, sem Solid Cache — jobs continuam `:async`, cache continua `:memory_store`.

> **Devise fica em 4.9.4 nesta etapa (decidido 2026-08-11).** O Rails 8.0 desenha rotas de forma lazy
> e o Devise 4.9.4 é anterior a isso, o que quebra os test helpers (não afeta produção, que roda
> `eager_load = true`). O contorno é uma linha em `test/test_helper.rb`. O upgrade para Devise 5.0 é
> a **Etapa F**, isolada. Detalhamento em `RAILS_80_MIGRATION.md` §4.1 e §4.2.

1. ✅ **Backup do banco de produção:** `heroku pg:backups:capture --app trscrews-prod`
2. ✅ Branch criada — na prática `refactor/rails-80-upgrade` (não `upgrade/rails-8.0`).
3. ✅ `rails` → `"~> 8.0.5", ">= 8.0.5.1"` no Gemfile.
4. ✅ Remover linha comentada do `gem "redis"` (limpeza) — **feito em 2026-08-13**, junto com a linha
   órfã do `# gem "kredis"`, resíduo do mesmo template. `Gemfile.lock` inalterado (comentários não
   entram na resolução de dependências — verificado por checksum após `bundle install`).
5. ✅ `bundle update rails` — subiu todo o stack para 8.0.5.1.
6. ✅ `app:update` aplicado por template, arquivo a arquivo — 2 aceitos, todo o resto rejeitado (ver §3.2). **Nenhum artefato de Solid entrou.**
7. ✅ `config.load_defaults 8.0` — as 3 flags confirmadas ativas em runtime.
8. ✅ Simplificar `cable.yml` para `adapter: async` — **feito em 2026-08-13**, no bloco `production`.
   O bloco `test` foi mantido em `adapter: test` (desvio deliberado da letra da Decisão 3, que dizia
   "async em todos os ambientes"): `test` é o adapter oficial de teste do Rails, que captura
   broadcasts para `assert_broadcasts`, não resíduo. Confirmado que a config de produção apontava
   para um Redis inexistente — não há addon nem `REDIS_URL` no Heroku, então o `ENV.fetch` caía
   sempre no default `redis://localhost:6379/1`, com a gem `redis` sequer instalada.
9. ✅ Atualizar URL placeholder no `config/initializers/stripe.rb` — **feito em 2026-08-13**, por
   remoção. O bloco `Stripe.set_app_info` inteiro saiu: é recurso para autores de plugin se
   identificarem à Stripe (anexa `name/version (url)` ao User-Agent de cada request), sem função
   para uma loja first-party. Não havia URL correta a colocar no lugar — não existe domínio próprio,
   e um hostname de Heroku ficaria obsoleto no go-live.
10. ⬜ Executar os 9 fluxos manuais localmente — **não feito**. O bloqueio original (banco de
    development vazio) caiu em 2026-08-13: o dev agora tem **22 screws de teste (seed), 0 orders,
    0 users**, então catálogo e página de produto passaram a ser validáveis — e foram, no fix do
    `pagy_bootstrap_nav` e no do overflow. Os fluxos que dependem de pedido e de usuário seguem sem
    execução.
11. ✅ `bin/rails test` — **17 runs, 47 assertions, 0 failures, 0 errors, 0 skips**.
12. ✅ Merge para `master`, deploy para Heroku — **feito em 2026-08-13**. Merge `--no-ff` em
    `eb59a6f`, deploy **v53** (Rails 8.0.5.1); **v54** em seguida, com o fix do `pagy_bootstrap_nav`.
13. 🔶 Verificar os 9 fluxos no Heroku — **PARCIAL**. Endpoints principais validados; fluxos de
    compra completos pendentes de verificação manual em produção.
    - **Validado em produção:** `/up` 200, `/` 200, `/screws` 200 (via `curl`), `Rails.version`
      8.0.5.1, boot limpo, e `assume_ssl = true` sem quebrar roteamento.
    - **Não validado:** os fluxos de compra ponta a ponta (carrinho → checkout → webhook → e-mail)
      não foram percorridos um a um depois do deploy. Produção tem 0 pedidos, então o caminho de
      compra não foi exercitado pós-upgrade. Vale em especial para o Fluxo 5 (webhook — e o endpoint
      test-mode segue **desabilitado** no Dashboard desde 2026-08-10) e o Fluxo 9 (imagens
      Cloudinary).
14. ⬜ Prosseguir para D2 quando confirmar estabilidade.

**Passos extras, não previstos no plano, executados na D1:**

- ✅ `config.assume_ssl = true` em `production.rb` (previsto em §3.2, aplicado à mão).
- ✅ Contorno do Devise em `test/test_helper.rb`, marcado como `WORKAROUND TEMPORÁRIO` — some na Etapa F.
- ✅ **Pin `gem "minitest", "~> 5.27"`** — obrigatório para a suíte carregar. Ver Etapa G.
- ✅ `filter_parameter_logging.rb`: `+:cvv, +:cvc` (do template 8.0 — relevante para LGPD/pagamentos).
- ✅ `development.rb`: `query_log_tags_enabled = true` (única config nova do template 8.0 nesse arquivo).

---

### Etapa D2 — Adoção do Solid Queue (2–3h)

**Objetivo:** Resolver o problema de e-mails perdidos em restart do dyno. Executar somente após confirmar estabilidade do D1.

1. **Backup do banco de produção:** `heroku pg:backups:capture --app trscrews-prod`
2. `git checkout -b feature/solid-queue`
3. Adicionar `gem "solid_queue"` ao Gemfile.
4. `bundle install`.
5. `bin/rails solid_queue:install` — gera migrations e arquivos de configuração.
6. `bin/rails db:migrate`.
7. Configurar `config/environments/production.rb`: `config.active_job.queue_adapter = :solid_queue`.
8. Configurar `puma.rb` para rodar o Solid Queue embutido no processo Puma (via plugin `solid_queue`) — sem dyno extra no Heroku.
9. Verificar localmente que `deliver_later` enfileira e processa jobs corretamente.
10. `bin/rails test` — reportar resultado.
11. Merge para `master`, deploy para Heroku, rodar migrations: `heroku run bin/rails db:migrate --app trscrews-prod`.
12. Verificar Fluxo 4 (e-mail de pedido pendente) e Fluxo 5 (e-mail de pagamento confirmado) no Heroku.
13. Confirmar nos logs do Heroku que o worker Solid Queue está processando jobs.
14. Prosseguir para D3 quando confirmar que e-mails funcionam corretamente.

---

### Etapa D3 — Adoção do Solid Cache (1–2h)

**Objetivo:** Configurar cache persistente no PostgreSQL para uso futuro. Mudança passiva — sem impacto no comportamento atual. Executar somente após confirmar estabilidade do D2.

1. **Backup do banco de produção:** `heroku pg:backups:capture --app trscrews-prod`
2. `git checkout -b feature/solid-cache`
3. Adicionar `gem "solid_cache"` ao Gemfile.
4. `bundle install`.
5. `bin/rails solid_cache:install` — gera migrations e configuração.
6. `bin/rails db:migrate`.
7. Configurar `config/environments/production.rb`: `config.cache_store = :solid_cache_store`.
8. `bin/rails test` — reportar resultado.
9. Merge para `master`, deploy para Heroku, rodar migrations: `heroku run bin/rails db:migrate --app trscrews-prod`.
10. Verificar Fluxos 2 (catálogo) e 8 (admin) no Heroku — confirmar que nada quebrou.
11. Prosseguir para E quando confirmar estabilidade.

---

### Etapa E — Upgrade 8.0 → 8.1.3.1 (3–4h15)

**Objetivo:** Chegar à versão alvo final com janela de suporte ativa. **Nenhuma feature nova do 8.1 é ativada aqui** — apenas o upgrade de versão e correção dos novos defaults.

> **[ATUALIZADO 2026-08-13]** Investigação completa em **`RAILS_81_MIGRATION.md`**, que corrige quatro
> fatos deste plano (defaults do 8.1, data da série, versão alvo e teto do minitest) e traz o plano de
> execução detalhado com pontos de parada. A ordem original mandava executar a E "somente após
> confirmar estabilidade do D3" — mas D2 e D3 não foram executadas, e **a E não depende delas**:
> nada de Solid entra na E, exatamente como não entrou na D1.
>
> **Estimativa revista: 3h–4h15** (original: 2–3h). A diferença é o ritual da D1 — `app:update`
> arquivo a arquivo e verificação de flags em runtime — que foi o que fez a D1 chegar em produção sem
> regressão.

1. **Backup do banco de produção:** `heroku pg:backups:capture --app trscrews-prod`
2. `git checkout -b upgrade/rails-8.1`
3. Atualizar `rails` para `"~> 8.1.3", ">= 8.1.3.1"` no Gemfile — mesmo formato da D1, que fixa a série e garante o patch de segurança. **Não tocar** no pin do minitest, no pagy nem no stripe.
4. `bundle update rails` — **só `rails`**, nunca `bundle update` pelado (ver §6). Esperado: stack Rails para 8.1.3.1, mais `turbo-rails` (2.0.16→2.0.23) e `importmap-rails` (2.2.0→2.2.3). **Solid Queue/Cache não entram** — não estão no Gemfile e não são dependência do `railties`.
   ⏸ **Parada:** revisar o diff do `Gemfile.lock` antes de seguir.
5. `bin/rails app:update` — aplicar **arquivo a arquivo**. **Rejeitar `config/cable.yml`** (o template do 8.1 propõe `adapter: solid_cable` e desfaria o fix da v55), além dos de sempre: `production.rb` (Cloudinary/SMTP/`assume_ssl`), `assets.rb` (`screw.glb`), `robots.txt` (SEO), `puma.rb`, `storage.yml`, `application.rb`, Docker/Kamal/CI/PWA. Ao oferecer `config/ci.rb`: aceitar o arquivo, mas não configurar conteúdo agora — **não confirmado** que o gerador do 8.1 de fato o oferece (`RAILS_81_MIGRATION.md` §0, correção 7).
   ⏸ **Parada:** listar explicitamente o que foi aceito e o que foi rejeitado.
6. Atualizar `config.load_defaults` para `8.1` em `application.rb`.
7. Verificar em runtime os **7 defaults reais** do 8.1 (tabela na §3.3), com `bin/rails runner`.
   Confirmar em especial que `config.yjit` continua `false` e que o `initializer :enable_yjit` segue
   rodando **depois** do `load_config_initializers`.
   *Não há o que verificar sobre ordem de callbacks — ver §3.3.*
8. Executar os fluxos validáveis localmente com os 22 screws do seed: catálogo, paginação (`?page=999`), página de produto (slug friendly_id), home, carrinho. Os fluxos que dependem de pedido e usuário seguem sem dado local.
9. `bin/rails test` — **baseline a bater: 20 runs / 54 assertions / 0 falhas**.
10. Boot em development **e** em production, procurando qualquer `DEPRECATION WARNING`. A D1 terminou com zero; a meta é a mesma.
    ⏸ **Parada:** relatório completo antes de qualquer merge.
11. Merge para `master`, deploy para Heroku — **só com aprovação explícita**.
12. Pós-deploy: `heroku logs` procurando `Regexp::TimeoutError`, `R14` (memória/YJIT) e 500s. Validar `/up`, `/`, `/screws`, `/screws?page=999`, página de produto.
13. Upgrade completo ✅ — Rails 8.1.3.1 em produção, com bug fixes até ~out/2026 e segurança até ~out/2027.

---

### Etapa F — Devise 4.9.4 → 5.0.x (1–2h) · INDEPENDENTE da cadeia Rails

**Objetivo:** eliminar a dívida assumida na D1 — sair de uma gem de abr/2024 rodando sobre Rails 8.x,
combinação não suportada pelo autor, e remover o contorno de `test/test_helper.rb`.

**Quando:** a qualquer momento **depois** da D1 estar estável. Não bloqueia D2, D3 nem E, e não é
bloqueada por elas. Fazer isoladamente é o ponto — foi para isso que ficou de fora da D1.

**Contexto:** o Rails 8.0 passou a desenhar rotas sob demanda (rails/rails#52353). O Devise resolve
`Devise.mappings` durante o carregamento das rotas, então os test helpers falham com
`Could not find a valid mapping`. Não existe `devise 4.9.5` — a série 4 terminou na 4.9.4. A correção
entrou no Devise 5.0.0.rc (heartcombo/devise#5695).

**Breaking changes do Devise 5.0 já conferidos contra o nosso código** (`RAILS_80_MIGRATION.md` §4.1):
derruba Ruby < 2.7 / Rails < 7.0 (ok); `secret_key` passa a vir sempre de `secret_key_base` (o nosso
já está comentado); HTML dos forms muda de `<br>` para `<p>` (não nos afeta — temos views próprias em
`app/views/devise/`); remove métodos de sign-in deprecados (usamos só `devise_parameter_sanitizer`,
que não é deprecado).

1. **Backup do banco:** `heroku pg:backups:capture --app trscrews-prod`
2. `git checkout -b upgrade/devise-5`
3. Gemfile: `gem "devise"` → `gem "devise", "~> 5.0"`; `bundle update devise`
4. **Remover** a linha `Rails.application.routes_reloader.try(:execute_unless_loaded)` de
   `test/test_helper.rb` — o Devise 5 faz isso internamente. A suíte deve continuar verde **sem** ela.
5. Revisar `config/initializers/devise.rb` contra o template da 5.0 (opções renomeadas/removidas).
6. `bin/rails test` — reportar resultado.
7. Executar o **Fluxo 1 inteiro** (cadastro, confirmação por e-mail, login, edição de perfil, logout,
   reset de senha, acesso negado a `/orders/mine` sem login) localmente.
8. Merge para `master`, deploy para Heroku.
9. **Repetir o Fluxo 1 inteiro no Heroku** — autenticação é o caminho crítico desta etapa.

**Rollback:** sem migrations. `git checkout` do `Gemfile`/`Gemfile.lock`, ou
`git push heroku <sha-anterior>:master`. Se usuários existentes não autenticarem após o deploy,
reverter imediatamente e investigar serialização de sessão / `secret_key_base`.

---

### Etapa G — minitest 5.27 → 6.x (1–2h) · INDEPENDENTE da cadeia Rails

**Objetivo:** pagar a dívida assumida na D1 — sair do pin `~> 5.27` e voltar a acompanhar o minitest.

**Origem (2026-08-12).** O `activesupport` 7.2.3.1 declarava `minitest (>= 5.1, < 6)`. O 8.0.5.1 **removeu
esse teto** (`minitest (>= 5.1)`), então o `bundle update rails` da D1 puxou o **minitest 6.0.6** — que
**derrubou a suíte inteira**, não por falha de teste, mas por `LoadError` no carregamento:

```
cannot load such file -- minitest/mock (LoadError)
  from test/controllers/stripe_webhooks_controller_test.rb:2
```

O minitest 6.0.0 (dez/2025) *"Dropped minitest/mock.rb. This has been extracted to the minitest-mock
gem"*, e o nosso teste do webhook do Stripe usa `Stripe::Webhook.stub(...)`. **Zero testes rodavam.**
Resolvido com o pin `gem "minitest", "~> 5.27"` no grupo `:test`, para manter a D1 restrita ao Rails.

**Superfície verificada na nossa suíte** (as outras 7 rupturas do 6.0.0 **não** nos atingem):

| Ruptura do minitest 6 | Nossa suíte |
|---|---|
| `minitest/mock` extraído | ⚠️ **1 arquivo** — `stripe_webhooks_controller_test.rb:2,21` |
| `assert_equal(nil, ...)` proibido | ✅ nenhum |
| `assert_send` removido | ✅ nenhum |
| namespace `MiniTest` deletado | ✅ nenhum |
| expectations `must_`/`wont_` no Object | ✅ nenhum |
| `assert_same(nil, ...)` proibido | ✅ nenhum |
| plugin loading passa a ser opt-in | ⚠️ verificar plugins do Rails ao migrar |

1. `git checkout -b upgrade/minitest-6`
2. Remover o pin `gem "minitest", "~> 5.27"` do Gemfile; `bundle update minitest`.
3. Adicionar `gem "minitest-mock"` no grupo `:test` **ou** reescrever `deliver_webhook` sem `Object#stub`.
4. Conferir o item "plugin loading opt-in" — pode exigir `require` explícito no `test_helper.rb`.
5. `bin/rails test` — baseline atual a bater: **17 runs / 47 assertions / 0 falhas**.

**Sem impacto em produção:** o minitest não é carregado fora do ambiente de teste. Esta etapa não
precisa de backup de banco nem de deploy.

---

### Resumo visual

```
Hoje  [Rails 7.1 EOL — sem suporte de segurança]
 │    Sem usuários reais · dados de teste · Heroku = ambiente de validação
 │
 ├─ Etapa A: Preparação (1–2h)
 │    Backup BD · [passo activestorage-cloudinary CANCELADO — gem saiu do projeto]
 │    · limpar branches locais mergeadas
 │
 ├─ Etapa B: sassc → dartsass (1–2h)
 │    Backup BD · migrar SCSS · validar local · deploy Heroku · validar Heroku
 │
 ├─ Etapa C: Rails 7.1 → 7.2 (3–4h)
 │    Backup BD · app:update · coletar deprecations · validar local
 │    · deploy Heroku · validar Heroku · confirmar estável
 │
 ├─ Etapa D1: Rails 7.2 → 8.0 puro (3–4h)  ✅ DEPLOYADA (v53/v54, 2026-08-13)
 │    Backup BD · app:update · SEM Solid Queue/Cache · validar local ✅ (17 runs/47 asserts)
 │    · cable.yml ✅ (2026-08-13) · [PENDENTE] friendly_id 5.5→5.7
 │    · deploy Heroku ✅ v53/v54 · endpoints validados ✅
 │    · [PENDENTE] fluxos de compra completos em produção
 │
 ├─ Etapa D2: Solid Queue (2–3h)
 │    Backup BD · instalar · migrations · validar local
 │    · deploy Heroku + migrations · confirmar e-mails processados
 │
 ├─ Etapa D3: Solid Cache (1–2h)
 │    Backup BD · instalar · migrations · validar local
 │    · deploy Heroku + migrations · confirmar estável
 │
 ├─ Etapa E: Rails 8.0 → 8.1.3.1 (3–4h15)  ← versão alvo final
 │    Backup BD · SÓ `bundle update rails` · app:update (REJEITAR cable.yml)
 │    · load_defaults 8.1 · verificar os 7 flags reais em runtime
 │    · validar local · deploy Heroku · validar Heroku
 │    [bug fixes até ~out/2026 · segurança até ~out/2027] ✅
 │    Investigação completa: RAILS_81_MIGRATION.md
 │
 ├─ Etapa F: Devise 4.9.4 → 5.0.x (1–2h)  ← independente; a qualquer momento pós-D1
 │    Backup BD · bundle update devise · REMOVER contorno de test_helper.rb
 │    · Fluxo 1 completo local · deploy Heroku · Fluxo 1 completo no Heroku
 │
 └─ Etapa G: minitest 5.27 → 6.x (1–2h)  ← independente; sem deploy, sem banco
      Remover pin do Gemfile · minitest-mock (ou reescrever o stub do webhook)
      · conferir plugin loading opt-in · bin/rails test

Total estimado: 14–20h  (12–16h da cadeia Rails + 1–2h da F + 1–2h da G)
(sem prazo fixo entre etapas — prosseguir quando confirmar estabilidade)
```

---

## Apêndice: Flags de risco elevado

Estas são as situações que, se encontradas durante o upgrade, exigem parada e análise antes de continuar:

| Situação | Etapa | O que fazer |
|---|---|---|
| ~~`activestorage-cloudinary-service` não funciona com Rails 8~~ | ~~D1~~ | **Flag removida em 2026-08-12** — a gem não está mais no projeto. A D1 rodou sem nenhum ajuste de Active Storage. |
| Stripe webhook retorna 500 após qualquer upgrade | qualquer | Reverter imediatamente (`git push heroku <branch-anterior>:main --force`). Investigar localmente. |
| Imagens de produtos quebram em produção | qualquer | Reverter o deploy. Investigar Active Storage. |
| Checkout não completa pedido | qualquer | Reverter. Investigar `OrdersController#create`. |
| Devise não autentica usuários existentes | qualquer | Reverter. Checar se mudança de `config.load_defaults` alterou hash de senha ou serialização de sessão. |
| ~~Callbacks de `Order` ou `ShippingAddress` executam em ordem diferente~~ | ~~E~~ | **Flag removida em 2026-08-13** — `run_after_transaction_callbacks_in_order_defined` **não é default do 8.1**: é do 7.1, e já está `true` desde a Etapa C, em produção, sem incidente. Não há mudança de ordem de callbacks na Etapa E. Ver `RAILS_81_MIGRATION.md` §0, correção 4. |
| `config/cable.yml` do template do 8.1 aceito por engano, reintroduzindo `adapter: solid_cable` | **E** | Rejeitar no `app:update`. Preservar o `adapter: async` deployado na v55. `git diff config/cable.yml` antes do commit. |
| `bundle update` sem argumento levando o pagy da série 9 para a 43.x | **E** | Só `bundle update rails`. Se acontecer: `git checkout Gemfile.lock` e refazer. Sintoma: paginação do catálogo quebrada e 3 testes vermelhos. |
| Timestamps em pedidos aparecem com timezone errado | **D1** (não E) | Causado pelo default `to_time_preserves_timezone = :zone`, que é do **8.0**. Verificar exibição de datas nas views e nos e-mails. Reverter com `config.active_support.to_time_preserves_timezone = :offset` (ou `false`). *(Etapa corrigida em 2026-08-12.)* |
| Requisição falha com `Regexp::TimeoutError` | **D1** | Novo default `Regexp.timeout = 1` do Rails 8.0. Nossas regexes são triviais; a causa provável é uma gem de terceiro sob input adversário. Mitigação imediata: `Regexp.timeout = nil` num initializer. Monitorar `heroku logs` após o deploy da D1. |
