# STRIPE_FIX_PLAN.md — Plano da Fase 3 (fixes do fluxo Stripe)

**Data:** 2026-08-10
**Autor:** investigação assistida (Claude Code)
**Status:** **EXECUTADO em 2026-08-10.** O plano original está preservado abaixo; o que de fato
aconteceu (incluindo um fix não previsto e quatro achados laterais) está na **§9 — Resultado da
execução**. Onde a execução contradisse o plano, o texto foi corrigido no lugar e a correção
está marcada com **[CORRIGIDO na execução]**.
**Relacionado:** `STRIPE_AUDIT.md` (Fases 1 e 2), `TODO.md` (seção URGENTE).

> **Pré-condição confirmada na Fase 2:** os 7 pedidos pagos vieram do webhook operante (out/2025 →
> mar/2026); `StripeWebhookEvent.count = 0` em produção → o fluxo **atual** (dependente da tabela,
> pós-mar/2026) **nunca foi exercitado em produção**. Validar esse caminho ponta a ponta é o objetivo
> central desta fase, antes do go-live em modo Live.

---

## 1. Instalação do Stripe CLI

✅ **Instalado em 2026-08-10** — `stripe 1.45.1`, em `~/.local/bin/stripe` (WSL Ubuntu). Era
pré-requisito do teste manual (§5), hoje concluído. O texto abaixo descreve como foi instalado.

### 1.1 Instalar no WSL Ubuntu — **[CORRIGIDO na execução]**

O plano original recomendava o repositório APT (`sudo apt install stripe`). **Isso não funcionou:**
`sudo` exige senha num terminal interativo, que não existe numa sessão não-interativa, e o APT
ainda precisaria escrever em `/etc/apt/sources.list.d/` e `/usr/share/keyrings/` — ambos root-only.

**Método que funcionou** — binário versionado do GitHub, verificado por checksum, instalado no
diretório do usuário (sem sudo):

```bash
# 1) Descobre a última release pela API do GitHub (asset VERSIONADO, não o "latest" redirecionado)
VER=$(curl -s https://api.github.com/repos/stripe/stripe-cli/releases/latest \
      | grep -oP '"tag_name": "v\K[^"]+')

# 2) Baixa o tarball e o arquivo de checksums da MESMA release
curl -sL -o /tmp/stripe.tar.gz \
  "https://github.com/stripe/stripe-cli/releases/download/v${VER}/stripe_${VER}_linux_x86_64.tar.gz"
curl -sL -o /tmp/stripe_checksums.txt \
  "https://github.com/stripe/stripe-cli/releases/download/v${VER}/stripe_${VER}_checksums.txt"

# 3) Confere o SHA-256 ANTES de extrair (falhou o check => não extrai)
cd /tmp && grep "linux_x86_64.tar.gz" stripe_checksums.txt | sha256sum -c -

# 4) Instala em ~/.local/bin (já no PATH, escopo de usuário, sem sudo)
mkdir -p ~/.local/bin
tar -xzf /tmp/stripe.tar.gz -C ~/.local/bin stripe
stripe version   # => 1.45.1 (versão instalada em 2026-08-10)
```

Vantagens do método: nada de root, remoção trivial (`rm ~/.local/bin/stripe`), e a origem do
binário é verificada por checksum em vez de confiada cegamente.

> ⚠️ **Procedimento reconstruído a partir do resultado observado** (binário confirmado em
> `~/.local/bin`, `stripe 1.45.1`); comandos funcionais mas **não são cópia literal** da sessão de
> instalação.

> **Nota WSL:** o CLI abre o navegador para o `stripe login`. No WSL isso normalmente funciona via
> `wslview`/browser padrão do Windows; se não abrir, o `stripe login` também imprime uma URL para
> colar manualmente no navegador.

### 1.2 Autenticar

```bash
stripe login
# Abre o navegador → autorizar o pareamento → o CLI grava as credenciais em ~/.config/stripe/
```

### 1.3 Parear com a conta de teste do projeto

- ✅ **Executado:** conta pareada `acct_1SFyTm...` ("Área restrita de New business"), em **test mode**
  (`test_mode_key_expires_at = 2026-11-08`). Confirmado com `stripe config --list`.
- O `stripe login` pareia com **uma conta**; selecionar a conta de **teste** do projeto TR Screws no
  fluxo de autorização.
- Como o projeto está em **test mode**, todos os `stripe trigger`/`stripe listen` operam com chaves
  `sk_test_`/`whsec_...` de teste — nenhum dado real é tocado.
- Confirmar a conta ativa: `stripe config --list` (mostra `account_id` pareado).
- **Não** usar credenciais Live nesta fase.

---

## 2. Fix do gap de concorrência (e-mail duplicado)

### 2.1 Código atual — `mark_order_paid` (`app/controllers/stripe_webhooks_controller.rb:79-109`)

```ruby
 79  def mark_order_paid(order_id, payment_reference:, source:)
 80    unless order_id.present?
 81      Rails.logger.warn "[Stripe] #{source}: missing order_id metadata"
 82      return
 83    end
 84
 85    order = Order.find_by(id: order_id)
 86    unless order
 87      Rails.logger.warn "[Stripe] #{source}: Order #{order_id} not found"
 88      return
 89    end
 90
 91    # Se já está pago (usa o helper do modelo, que olha payment_status/paid_at)
 92    if order.paid?
 93      Rails.logger.info "[Stripe] #{source}: Order #{order.id} already paid – skipping"
 94      return
 95    end
 96
 97    # Usa o helper do modelo Order (já existe em app/models/order.rb)
 98    order.mark_paid!(method: "stripe", reference: payment_reference)
 99
100    Rails.logger.info "[Stripe] #{source}: Order #{order.id} marcado como PAID, ref=#{payment_reference}"
101
102    # Envia o e-mail de confirmação de pagamento
103    begin
104      OrderMailer.payment_confirmed(order).deliver_later
105      Rails.logger.info "[Stripe] Sent payment confirmation email for order #{order.id}"
106    rescue StandardError => e
107      Rails.logger.error "[Stripe] Email error for order #{order.id}: #{e.class} - #{e.message}"
108    end
109  end
```

### 2.2 Código atual — `Order#mark_paid!` (`app/models/order.rb:70-73`)

```ruby
70  def mark_paid!(method:, reference:)
71    update!(payment_status: :paid, paid_at: Time.current,
72            payment_method: method, payment_reference: reference)
73  end
```

E o helper `paid?` (`app/models/order.rb:60-67`), que decide por `payment_status == "paid"`
(fallback: `paid_at.present?`).

### 2.3 A natureza do gap

O check-and-act nas linhas **92 (`if order.paid?`)** e **98 (`mark_paid!`)** não é atômico. A
idempotência **por evento** (`processed_event?`, `:114`) só dedup­lica o **mesmo** `event.id`. Mas o
Stripe emite **eventos distintos** para o mesmo pedido — tipicamente `checkout.session.completed`
**e** `payment_intent.succeeded` — cada um com `event.id` próprio. Sob **entrega concorrente** desses
dois eventos:

1. Handler A lê `order.paid? == false` (linha 92) → segue.
2. Handler B lê `order.paid? == false` (linha 92, antes de A commitar) → segue.
3. Ambos chamam `mark_paid!` (idempotente no **valor** final: `payment_status` continua `paid`).
4. **Ambos enviam `OrderMailer.payment_confirmed`** → **e-mail duplicado** ao cliente.

O efeito colateral (e-mail) é o dano; o estado final do banco permanece correto.

### 2.4 Abordagens propostas (NÃO implementar ainda)

**Abordagem (a) — `with_lock` (row lock pessimista):**

```ruby
# ESBOÇO — não implementado
newly_paid = false
order.with_lock do            # SELECT ... FOR UPDATE — serializa na linha do pedido
  unless order.paid?
    order.mark_paid!(method: "stripe", reference: payment_reference)
    newly_paid = true
  end
end
return unless newly_paid       # e-mail só quando ESTE handler efetivou o pagamento
OrderMailer.payment_confirmed(order).deliver_later
```

**Abordagem (b) — `update` condicional atômico:**

```ruby
# ESBOÇO — não implementado
affected = Order.where(id: order.id, payment_status: :pending)
                .update_all(payment_status: Order.payment_statuses[:paid],
                            paid_at: Time.current,
                            payment_method: "stripe",
                            payment_reference: payment_reference,
                            updated_at: Time.current)
return if affected.zero?       # outro handler já marcou → não reenvia e-mail
OrderMailer.payment_confirmed(order).deliver_later
```

### 2.5 Análise de risco e recomendação

| Critério | (a) `with_lock` | (b) `update_all` condicional |
|---|---|---|
| Atomicidade da corrida | ✔️ row lock serializa os dois handlers | ✔️ 1 statement SQL, garantido pelo WHERE |
| Reusa `Order#mark_paid!` (fonte única) | ✔️ sim | ❌ não — reimplementa a escrita |
| Validações do modelo rodam | ✔️ sim (`update!`) | ❌ não (`update_all` pula validação/callbacks) |
| Precisa setar `paid_at`/`updated_at` na mão | ❌ não | ✔️ sim (risco de esquecer campo) |
| Enum mapeado corretamente | ✔️ (`mark_paid!` já usa símbolo) | ⚠️ exige `Order.payment_statuses[:paid]` (inteiro) |
| Superfície de novo código | Menor (envolve o guard existente) | Maior (segundo caminho de escrita) |
| Custo | 1 lock curto por webhook (transação já existe) | Nenhum lock explícito |

**Recomendação: abordagem (a) `with_lock`.** Justificativa:

- **Mantém `Order#mark_paid!` como único ponto de escrita** de `payment_status = "paid"` — invariante
  que o próprio `STRIPE_AUDIT.md` §2.1 destaca. A abordagem (b) criaria um **segundo** caminho de
  escrita, quebrando essa garantia e exigindo manutenção paralela.
- **Validações e semântica idênticas** às da marcação normal (mesmo `update!`).
- O lock é **curto e local** (uma linha, transação já existente do request), sem contenção prática num
  e-commerce desse volume (7 pagamentos em ~10 meses).
- O e-mail fica **fora** do lock (só o `deliver_later`, que é enfileiramento rápido), enviado apenas
  quando `newly_paid == true`.

> Ressalva de (b): `update_all` **não** dispara callbacks. Hoje `mark_paid!` não tem callbacks
> relevantes, mas se algum `after_update` for adicionado no futuro, (b) o silenciaria. Mais um motivo
> para (a).

---

## 3. Correção da rota no TODO.md

### 3.1 Evidência

- **Rota real** (`config/routes.rb:63`): `post "/stripe/webhooks", to: "stripe_webhooks#receive"`
- **TODO.md linha 57** (go-live checklist) diz o endpoint **invertido**:
  > `apontando para https://<domínio>/webhooks/stripe`

Configurar o webhook no Dashboard Stripe com `/webhooks/stripe` causaria **404** (rota inexistente).

### 3.2 Correção proposta (uma linha, em `TODO.md:57`)

```diff
-      apontando para https://<domínio>/webhooks/stripe
+      apontando para https://<domínio>/stripe/webhooks
```

Mudança "menor" (correção de typo em doc). Aplicar junto com os demais fixes ou isoladamente.

---

## 4. Testes do fluxo de webhook

### 4.0 Estratégia de mock — sem gem nova, sem API real — **[CORRIGIDO na execução]**

**A premissa original do plano estava errada.** O plano dizia que em `test` a env var
`STRIPE_SIGNING_SECRET` **não** estaria setada, e que por isso o controller cairia no branch
`Stripe::Event.construct_from(JSON.parse(payload))` (parsing local, sem verificação de assinatura).

**O que é verdade:** `dotenv-rails` está no grupo `:development, :test` do Gemfile (`Gemfile:50`),
e o `.env` define `STRIPE_SIGNING_SECRET`. Logo, **em `test` o secret ESTÁ presente** e o controller
toma o branch de **verificação de assinatura** (`Stripe::Webhook.construct_event`) — que rejeitaria
qualquer POST de teste, já que os testes não conseguem assinar o payload.

**Solução adotada:** stub de `Stripe::Webhook.construct_event` via `minitest/mock` (biblioteca padrão,
**nenhuma gem nova**). A verificação de assinatura é código da Stripe, não nosso; o stub devolve o
mesmo objeto que ela devolveria (`Stripe::Event.construct_from(payload)`), e o corpo/assinatura do
POST passam a ser irrelevantes:

```ruby
def deliver_webhook(payload)
  event = Stripe::Event.construct_from(payload)
  Stripe::Webhook.stub(:construct_event, event) do
    post WEBHOOK_PATH, params: payload.to_json,
         headers: { "CONTENT_TYPE" => "application/json",
                    "Stripe-Signature" => "t=0,v1=ignored-because-stubbed" }
  end
end
```

- Cumpre o CLAUDE.md ("NUNCA chamar API real"; "decidir mock no primeiro teste de Stripe") **sem
  adicionar gem** — decisão: **não precisamos de gem de mock** para estes cenários.
- Arquivo alvo: `test/controllers/stripe_webhooks_controller_test.rb` (hoje **vazio**, só o esqueleto).
- Fixtures existentes: `orders(:one)` e `orders(:two)`, ambas `payment_status: 0 (pending)` — servem.
- E-mail: assertar com `assert_enqueued_emails` (o controller usa `deliver_later`).
- Rota nos testes: `post "/stripe/webhooks", params: payload_json, headers: { "CONTENT_TYPE" => "application/json" }`
  (ou `as: :json`).

Helper de payload sugerido (a definir no teste, **não implementado**): monta o hash do evento no
formato mínimo que `construct_from` aceita e que os handlers leem (`data.object.metadata.order_id`,
`data.object.id`, `type`, `id`).

### 4.1 (a) Webhook marca pedido como paid uma vez

- **Fixtures/mocks:** `orders(:one)` (pending). Sem mock externo.
- **Payload:** evento `payment_intent.succeeded` com `data.object.id = "pi_test_1"` e
  `data.object.metadata.order_id = orders(:one).id`; `event.id = "evt_1"`.
- **Ação:** `post "/stripe/webhooks"` com o payload.
- **Asserções:**
  - resposta `:ok` (200);
  - `orders(:one).reload.paid?` verdadeiro; `payment_reference == "pi_test_1"`; `payment_method == "stripe"`;
  - `StripeWebhookEvent.exists?(stripe_event_id: "evt_1")` verdadeiro;
  - `assert_enqueued_emails 1`.

### 4.2 (b) Evento duplicado (mesmo `event.id`) não reprocessa

- **Fixtures/mocks:** `orders(:one)` (pending).
- **Payload:** mesmo evento `evt_1` do 4.1, **enviado duas vezes**.
- **Ação:** dois `post` idênticos.
- **Asserções:**
  - ambos retornam `:ok`;
  - `StripeWebhookEvent.where(stripe_event_id: "evt_1").count == 1`;
  - `assert_enqueued_emails 1` no total (o 2º POST cai no `processed_event?` `:27` e retorna sem handler);
  - `orders(:one).reload.paid?` verdadeiro.

### 4.3 (c) Dois eventos DISTINTOS do mesmo pedido não duplicam e-mail

> Este é o cenário do gap da §2. Cobre a correção recomendada (a).

- **Fixtures/mocks:** `orders(:one)` (pending).
- **Payloads:** dois eventos com **`event.id` diferentes** para o **mesmo** pedido:
  - `evt_A` tipo `checkout.session.completed` (`data.object.id = "cs_A"`, `metadata.order_id = one.id`);
  - `evt_B` tipo `payment_intent.succeeded` (`data.object.id = "pi_B"`, `metadata.order_id = one.id`).
- **Ação (versão sequencial — determinística):** `post evt_A` depois `post evt_B`.
- **Asserções:**
  - `orders(:one).reload.paid?` verdadeiro (uma vez);
  - **`assert_enqueued_emails 1`** (o 2º evento vê o pedido já `paid` e não reenvia);
  - ambos os `event.id` registrados em `StripeWebhookEvent` (2 linhas).
- **Observação de honestidade sobre concorrência real:** a corrida **verdadeira** (dois handlers
  lendo `paid? == false` ao mesmo tempo) **não é reproduzível** com o teste transacional padrão
  (single-thread, uma conexão, rollback por teste). Testá-la exigiria `self.use_transactional_tests =
  false` + duas threads com conexões separadas + barreira de sincronização — frágil e lento. **Plano:**
  cobrir o caso **sequencial** (acima) como regressão do comportamento observável, e **confiar no
  `with_lock`** para a corrida real (garantida no nível do banco, não no nível de teste). Documentar
  essa limitação no próprio teste. Um teste de concorrência com threads fica como **opcional/avançado**,
  a decidir depois.

### 4.4 (d) Success URL revisitado não altera status

- **Fixtures/mocks:** `orders(:one)` (pending). Requer um usuário/autorização se `authorize_thank_you!`
  exigir — **verificar** `orders_controller` `set_order`/`authorize_thank_you!` antes de escrever
  (pode precisar de sessão logada ou de um token na fixture).
- **Ação:** `get thank_you_order_path(orders(:one), paid: 1)` (e uma 2ª visita).
- **Asserções:**
  - resposta `:success`;
  - `orders(:one).reload.payment_status` permanece `"pending"` (nenhuma escrita);
  - nenhum e-mail enfileirado (`assert_enqueued_emails 0`).
- **Objetivo:** travar por teste a garantia da §2.3 do audit (thank_you é somente-leitura).

> **Pré-requisito geral (bug-fix workflow do CLAUDE.md):** o teste (c) deve **falhar** contra uma
> versão sem o fix e **passar** depois. Como o código atual já tem o guard sequencial `paid?`, o teste
> (c) na forma **sequencial** pode passar mesmo sem `with_lock`. Para respeitar o workflow "teste
> vermelho primeiro", o teste que realmente exercita o fix é o de **concorrência** (opcional/avançado);
> o teste (c) sequencial é **regressão de comportamento**, não prova do fix de corrida. Isso será dito
> explicitamente no plano de execução (§7).

---

## 5. Teste manual com Stripe CLI (validação ponta a ponta)

Objetivo: exercitar pela **primeira vez** o caminho atual do webhook (que depende da tabela) e provar
que `StripeWebhookEvent` registra evento e que a idempotência funciona.

### 5.1 Passo a passo

```bash
# Terminal 1 — subir a app local
bin/rails server            # localhost:3000

# Terminal 2 — encaminhar eventos do Stripe (test mode) para o webhook local
stripe listen --forward-to localhost:3000/stripe/webhooks
#   → o CLI imprime um "webhook signing secret": whsec_xxx
```

> **Assinatura no teste manual:** para exercitar o caminho **com verificação de assinatura** (o de
> produção), setar o secret impresso pelo `stripe listen` antes de subir o server:
> `export STRIPE_SIGNING_SECRET=whsec_xxx`. Sem ele, o controller cai no branch sem verificação
> (`construct_from`) — útil, mas não valida a assinatura.

```bash
# Terminal 3 — disparar eventos de teste
stripe trigger payment_intent.succeeded
stripe trigger checkout.session.completed
```

> **Atenção ao `order_id`:** os eventos gerados por `stripe trigger` têm `metadata` genérica **sem**
> `order_id` do nosso banco → o handler logará "missing order_id" e não marcará nada. Para um teste
> fim-a-fim real, disparar o evento **com metadata**:
> `stripe trigger payment_intent.succeeded --add payment_intent:metadata.order_id=<ID_de_um_pedido_pending_local>`
> (confirmar a sintaxe `--add` na versão instalada do CLI; alternativa: criar um Checkout de teste real
> pelo próprio app, que já injeta `metadata.order_id`).

### 5.2 Confirmar que `StripeWebhookEvent` registrou

```bash
bin/rails runner 'puts StripeWebhookEvent.order(:created_at).last(3).map { |e| [e.stripe_event_id, e.processed_at].inspect }'
```

Esperado: uma linha nova por evento processado (com `stripe_event_id = evt_...`).

### 5.3 Confirmar idempotência (reenviar o MESMO evento)

```bash
# Pega o id do último evento e reenvia
stripe events resend evt_XXXXXXXX
```

Esperado nos logs da app: `"[Stripe] Duplicate event id=evt_XXXX – skipping"` e **nenhuma** nova linha
em `StripeWebhookEvent` (count inalterado), **nenhum** novo e-mail.

---

## 6. Decisão sobre a migration com ano errado

**Fato:** `db/migrate/20250311120000_create_stripe_webhook_events.rb` — o `2025` no nome é typo; o
commit real é 2026-03-11 (`8f1710e`). A migration **já rodou em produção** em 2026-05-25 → o timestamp
`20250311120000` **já está** em `schema_migrations` (prod e em qualquer ambiente que rodou `db:migrate`).

### Opção A — Renomear (`20250311...` → `20260311...`) + ajustar `schema_migrations` (ARRISCADO)

- Renomear o arquivo muda o "version". O Rails passaria a ver `20250311120000` como **ausente** do
  código e `20260311120000` como **não-executada** → tentaria **re-rodar** a migration (falha:
  tabela já existe) **e** poderia acusar migration "missing" no ambiente.
- Exigiria um `UPDATE schema_migrations SET version='20260311120000' WHERE version='20250311120000'`
  **em todos os ambientes** (produção inclusa) — operação manual em dados de produção, com janela para
  erro e divergência entre ambientes. **Benefício funcional: zero.**

### Opção B — Deixar como está + documentar (SEGURO)

- Não mexe em `schema_migrations` nem em produção.
- Adicionar um **comentário no topo do arquivo de migration** registrando que o nome tem ano incorreto
  (real: 2026-03-11) e apontando para `STRIPE_AUDIT.md §4.5`. Já documentado no audit.

**Recomendação: Opção B.** O nome de arquivo de migration é irrelevante em runtime depois de aplicada;
o único "custo" é cosmético/histórico, e o audit já registra a data correta. Renomear introduz risco
real em produção por ganho nulo. (Comentário no arquivo é mudança "menor", mas toca `db/migrate/` —
apresentar antes de aplicar.)

---

## 7. Ordem de execução proposta (com pontos de parada para aprovação)

| # | Passo | Tipo (CLAUDE.md) | Aprovação? | Status |
|---|---|---|---|---|
| 0 | Instalar + autenticar Stripe CLI (§1) | ambiente local | Sim (roda comandos de sistema) | ✅ **feito** (v1.45.1, conta de teste pareada) |
| 1 | Correção de rota no `TODO.md` (§3) | menor (doc) | Não (só reporto) | ✅ **feito** (commit `416554f`) |
| 2 | **Escrever testes (a),(b),(d)** e o (c) sequencial (§4) — **antes** do fix | testes | Sim (novo arquivo de teste) | ✅ **feito** — 5 testes (4 de webhook + 1 de thank_you), commit `416554f` |
| 3 | Rodar `bin/rails test` → registrar baseline | testes | Não | ✅ **feito** — baseline RED em (c) e (e) por causa do Fix 0 |
| 4 | **Implementar fix `with_lock`** em `mark_order_paid` (§2, abordagem a) | **maior** (controller + fluxo pagamento) | **Sim, explícita** | ✅ **feito** (commit `2b21373`) |
| 5 | Rodar `bin/rails test` → tudo verde | testes | Não | ✅ **feito** — 16 runs, 42 assertions, 0 failures, 0 errors, 0 skips (0,93s) |
| 6 | (Opcional) teste de concorrência real com threads (§4.3) | testes avançados | Sim (decidir se vale) | ⬜ **não feito** — decisão: corrida real fica coberta pelo row lock, não por teste |
| 7 | Teste manual Stripe CLI ponta a ponta (§5) — provar tabela + idempotência | validação local | Sim (roda local) | ✅ **feito** — ver §9.3 |
| 8 | Comentário na migration (§6, Opção B) | menor, mas toca `db/migrate/` | Sim | ✅ **feito** |
| 9 | Commit(s) dos fixes + push | git | **Sim, por operação** | 🔄 **em andamento** — Fix 0 e `with_lock` commitados; docs pendentes |

**Pontos de parada obrigatórios (não prosseguir sem "ok"):** passos 0, 4, 6, 7, 8, 9.
Todos foram respeitados: cada passo acima teve aprovação explícita antes de rodar.

> **Desvio de ordem, registrado:** o Fix 0 (§9.1) **não estava neste plano**. Ele apareceu como
> teste RED no passo 3 e foi corrigido antes do passo 4, invertendo parcialmente a ordem prevista.

> Ordem segue o CLAUDE.md ("completar upgrade → escrever testes → refatorar/fix"): testes **antes** do
> fix (passo 2 antes do 4). Ressalva registrada na §4.4: o fix de corrida real só é provado pelo teste
> de concorrência (passo 6, opcional); os testes do passo 2 são regressão de comportamento observável.

---

## 8. Riscos e mitigação

| Fix / passo | O que pode dar errado | Mitigação |
|---|---|---|
| Stripe CLI no WSL (§1) | `stripe login` não abre navegador; APT inviável sem root | **[CORRIGIDO na execução]** o APT foi descartado (exige `sudo` interativo) e o **binário direto virou o método principal**, não plano B: asset versionado do GitHub + checksum SHA-256 + install em `~/.local/bin` (§1.1). O `stripe login` funcionou; se não abrisse o navegador, ele também imprime a URL para colar à mão |
| `with_lock` (§2a) | Deadlock/contenção se o request já tiver outra transação aberta sobre o mesmo pedido | Escopo do lock é mínimo (só o bloco paid?/mark_paid!); volume real é baixíssimo; e-mail fora do lock |
| `with_lock` (§2a) | `mark_paid!` usa `update!` → se uma **validação** do `Order` falhar (ex.: pedido antigo com dado faltante), levanta e cai no `rescue` → HTTP 500 → Stripe **retenta** | Verificar que pedidos `pending` reais passam nas validações; considerar `save(validate: false)` **somente** se necessário (decidir na implementação, não presumir) |
| Testes sem gem de mock (§4.0) | Se algum handler tocar a rede (não deveria), teste vira flaky/lento | **[CORRIGIDO]** o secret **está** no env de teste (dotenv carrega `.env` em `test`), então o caminho exercitado é o de verificação de assinatura, com `Stripe::Webhook.construct_event` stubado via `minitest/mock`. Nenhuma chamada de rede; nenhuma API stubada além dessa |
| Teste (d) thank_you (§4.4) | `authorize_thank_you!` pode exigir sessão/token → teste falha por auth, não por status | **Ler `orders_controller` antes** e montar a autorização mínima na fixture/sessão |
| Teste (c) sequencial (§4.3) | Passar mesmo sem o fix (guard atual já cobre o caso sequencial) → falsa sensação de proteção | Deixar explícito no teste que a corrida real depende do `with_lock`; teste de threads é o que prova o fix |
| Teste manual CLI (§5) | `stripe trigger` gera evento **sem** `order_id` → nada é marcado | Usar `--add ...metadata.order_id=<id>` ou criar Checkout real pelo app |
| Renomear migration (§6, se escolher A) | Rails tenta re-rodar / divergência `schema_migrations` prod | **Não escolher A** — recomendação é Opção B (documentar) |
| Deploy dos fixes | Alterar o controller de pagamento em produção sem validação prévia | Só após passos 5 e 7 verdes; deploy **nunca** sem aprovação explícita (CLAUDE.md) |

---

## 9. Resultado da execução (2026-08-10)

### 9.1 Correções aplicadas

| Fix | O que era | Commit |
|---|---|---|
| **Fix 0 — `#dig` em `checkout.session.completed`** ⚠️ *não previsto neste plano* | `handle_checkout_session_completed` usava `session.dig("metadata", "order_id")`, mas `Stripe::StripeObject` **não implementa `#dig`** → **todo** evento desse tipo levantava `NoMethodError` e devolvia **HTTP 500**. Só `payment_intent.succeeded` (acesso por colchetes) funcionava — o que explica por que os **7 pedidos pagos em produção têm `payment_reference` no formato `pi_`**. Descoberto porque o teste (e) nasceu RED. | `416554f` |
| **Fix de concorrência — `with_lock`** (§2, abordagem (a)) | check-and-act não-atômico entre `paid?` (`:92`) e `mark_paid!` (`:98`) → e-mail duplicado sob entrega concorrente de dois eventos distintos. Agora o par roda dentro de `order.with_lock`; o e-mail sai **fora** do lock e só quando `newly_paid == true`. `mark_paid!` continua sendo o único caminho de escrita. | `2b21373` |
| **Rota no `TODO.md`** (§3) | `/webhooks/stripe` → `/stripe/webhooks` (o endpoint errado daria 404 no Dashboard). | `416554f` |

### 9.2 Testes — 5 novos, suíte inteira verde

```
16 runs, 42 assertions, 0 failures, 0 errors, 0 skips  (0,93s)
```

- `test/controllers/stripe_webhooks_controller_test.rb` — **4 testes**: (a) marca paid uma vez;
  (b) evento duplicado (mesmo `event.id`) não reprocessa; (c) dois eventos **distintos** do mesmo
  pedido não duplicam e-mail; (e) `checkout.session.completed` marca paid — este nasceu **RED** e
  foi o que revelou o Fix 0.
- `test/controllers/orders_thank_you_test.rb` — **1 teste**: revisitar o thank_you não altera
  `payment_status` (§4.4).
- Passo 6 (concorrência com threads) **não executado**, conforme §4.3: a corrida real fica garantida
  pelo row lock no banco, não por teste.

### 9.3 Teste E2E com Stripe CLI (§5) — **primeira execução ponta a ponta da história do projeto**

Ambiente: `stripe listen --forward-to localhost:3000/stripe/webhooks` + Puma com
`STRIPE_SIGNING_SECRET` do listen → **caminho com verificação de assinatura** (`sig_present=true`),
o mesmo de produção. Pedido sintético `Order#1` (pending, R$ 59,80, 1 item), removido do banco de dev
ao final.

| Cenário | Comando | Resultado |
|---|---|---|
| Pagamento | `stripe trigger payment_intent.succeeded --add payment_intent:metadata.order_id=1` | ✅ `Order 1 marcado como PAID, ref=pi_3U2xeC...`; SQL mostrou o **`SELECT ... FOR UPDATE`** do `with_lock`; `StripeWebhookEvent` **registrou pela primeira vez**; e-mail renderizou e foi entregue (`OrderMailer#payment_confirmed`, 243ms) |
| Idempotência | `stripe events resend evt_3U2xeCRH31OaqHfq1W96JB66` | ✅ `Duplicate event id=... – skipping`; count **não** subiu; `paid_at` e `updated_at` **inalterados**; nenhum e-mail novo. O request fez **1 query só** (o SELECT do guard) |
| Fix 0 em campo | `stripe trigger checkout.session.completed --add checkout_session:metadata.order_id=1` | ✅ **200, não 500** — leu `order_id=1` da metadata (o acesso que antes explodia) e caiu no guard `Order 1 already paid – skipping`; nenhum e-mail duplicado |

Placar do log inteiro: **1** e-mail enviado, **0** ocorrências de `Internal Server Error`/`NoMethodError`.

### 9.4 Quatro achados laterais (nenhum corrigido nesta fase)

1. **`recalc_totals!` grava totais zerados** — `order_items.sum(:line_total)` é soma em **SQL**; num
   pedido ainda não salvo a associação é null-relation e devolve **0**. Como
   `orders_controller.rb:109` chama `recalc_totals!` **antes** do `save`, todo pedido criado pelo site
   grava `subtotal = 0` e `total = apenas o frete`. Confirmado por sonda local: itens de R$ 39,80
   viraram `subtotal=0.0, total=20.0`. Views e e-mail escapam porque usam `items_subtotal`/
   `total_amount` (soma em memória) — por isso passou despercebido. **Anotado no `TODO.md`.**
2. **Webhook não valida valor nem moeda** — o handler marca paid confiando só em `metadata.order_id`.
   No teste E2E um evento de **USD 20,00** marcou pago um pedido de **R$ 59,80**. Com assinatura
   verificada não é buraco de segurança direto, mas metadata errada ou evento de outro fluxo marcaria
   pedido com valor divergente sem nenhum alarme. **Anotado no `TODO.md`** como bloqueador de go-live.
3. **1 trigger ≠ 1 evento** — `stripe trigger payment_intent.succeeded` emite **4** eventos
   (`charge.succeeded`, `payment_intent.succeeded`, `payment_intent.created`, `charge.updated`) e
   `checkout.session.completed` emite **7**. Como `mark_event_processed` grava **todo** evento
   recebido (inclusive os de tipo ignorado), a contagem cresce por **evento recebido**, não por
   pagamento. É o comportamento desejável — um reenvio de evento ignorado nem chega ao dispatch —
   mas invalida a expectativa "1 pagamento = 1 linha".
4. **Metadata ausente é tratada com elegância** — o `payment_intent.succeeded` derivado do trigger de
   checkout veio **sem** `order_id` (o `--add checkout_session:` não propaga para o payment intent).
   O handler logou `missing order_id metadata` e devolveu 200, sem erro. Cobertura acidental desse
   caminho.

---

## 10. Decisões tomadas (registro histórico)

1. **§2 — Fix de concorrência:** aprovada e implementada a **abordagem (a) `with_lock`**.
2. **§3 — Rota no TODO:** corrigida (`/webhooks/stripe` → `/stripe/webhooks`).
3. **§4 — Testes:** escritos **sem gem nova**, com stub de `Stripe::Webhook.construct_event` via
   `minitest/mock` (a premissa original sobre o secret ausente estava errada — ver §4.0).
4. **§6 — Migration:** adotada a **Opção B** — comentário no topo do arquivo documentando o ano
   errado; **sem** renomear, **sem** mexer em `schema_migrations`.
5. **§7 — Ordem:** respeitada, com o desvio do Fix 0 registrado na §7.
