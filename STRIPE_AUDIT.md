# STRIPE_AUDIT.md — Auditoria do fluxo Stripe (Fases 1 e 2)

**Data:** 2026-08-10 (revisão 3 — contagem de pedidos corrigida com dados de produção; revisão 2 corrigiu a timeline com git)
**Autor:** investigação assistida (Claude Code)
**Escopo:** Fase 1 (auditoria de código) + Fase 2 (fluxo real que marca `payment_status = "paid"`).
**Status:** investigação apenas — **nenhum código de fix escrito.** Fase 3 (implementação) pendente de aprovação.
**Relacionado:** `TODO.md` (seção URGENTE), `AUDIT.md`.

> ⚠️ **Esta é a revisão 3.** A revisão 1 (2026-07-15) continha duas conclusões erradas
> ("15 pedidos = marcação manual via console" e "webhook quebrado desde março/2025"), refutadas
> com evidência de git na revisão 2. A revisão 3 (2026-08-10) corrigiu ainda a **contagem de pedidos
> pagos (7, não 15)** com dados de produção. Ver seção **"Histórico de correções desta investigação"**
> ao final.

---

## 0. Resumo executivo

- Existe **um único** caminho no código que escreve `payment_status = "paid"`: `Order#mark_paid!`,
  chamado **exclusivamente** pelo `StripeWebhooksController`.
- O redirect de sucesso do Stripe Checkout (`orders#thank_you`) **não escreve nada no banco** —
  a ação tem corpo vazio. O parâmetro `?paid=1` do `success_url` só controla um banner na view.
- Portanto, **revisitar o success URL é inócuo** (nenhuma escrita). A hipótese do TODO §3 de
  "marcação duplicada via dupla visita ao success URL" **está descartada pelo código**.
- **Origem dos 7 pedidos pagos (de 15 pedidos no total):** foram **pagos pelo webhook funcionando** entre
  **2025-10-08 e 2026-03-11**, período em que o webhook marcava `paid` **direto**, sem depender da
  tabela `stripe_webhook_events`. A dependência dessa tabela só foi introduzida em 2026-03-11
  (commit `8f1710e`); a tabela só passou a existir em produção em 2026-05-25. Logo, o webhook
  **estava operante** durante out/2025 → mar/2026 e é a explicação natural dos 7 pedidos pagos —
  **não** houve marcação manual via console. **Confirmado com dados de produção em 2026-08-10** (ver §4.8).
- **Janela real de webhook quebrado:** ~2,5 meses (**2026-03-11 a 2026-05-25**), entre a introdução
  da dependência da tabela e o `db:migrate` que a criou em produção. **Não** os 14+ meses afirmados
  no TODO.
- **Correção factual na premissa do TODO:** a janela "desde março de 2025 / 14+ meses" está errada.
  Ela vem do **ano errado no nome do arquivo de migration** (`20250311...` em vez de `20260311...`);
  a data real do commit é **2026-03-11** (ver §4 e §4.5).

---

## Fase 1 — Mapa do fluxo (auditoria de código)

Pontos de entrada do fluxo Stripe e seu papel:

| Etapa | Arquivo:linha | Papel |
|---|---|---|
| Inicia pagamento | `app/controllers/checkout_sessions_controller.rb:70` | Cria `Stripe::Checkout::Session` (mode `payment`) com `metadata.order_id` (`:85`) e `payment_intent_data.metadata.order_id` (`:87-89`). Só permite se `payment_status == "pending"` (`:14`). |
| `success_url` | `checkout_sessions_controller.rb:67` | `thank_you_order_url(@order, paid: 1, session_id: "{CHECKOUT_SESSION_ID}")` |
| `cancel_url` | `checkout_sessions_controller.rb:68` | `thank_you_order_url(@order, canceled: 1)` |
| Confirmação real | `app/controllers/stripe_webhooks_controller.rb:4` (`receive`) | Verifica assinatura (`:14`), idempotência por evento (`:27`), roteia eventos (`:32`). |
| Redirect de sucesso | `app/controllers/orders_controller.rb:147` (`thank_you`) | **Corpo vazio.** Só renderiza a view. **Não escreve no banco.** |
| View do sucesso | `app/views/orders/thank_you.html.erb` | Lê `@order.paid?` (do banco) para escolher badge. Renderiza `_stripe_pay_button`. |
| Partial do botão | `app/views/orders/_stripe_pay_button.html.erb:4` | `params[:paid]` apenas exibe banner "Pagamento em processamento". Nenhuma escrita. |

**Roteamento (`config/routes.rb`):**
- `POST /checkout_sessions` → `checkout_sessions#create` (`:62`)
- `POST /stripe/webhooks` → `stripe_webhooks#receive` (`:63`)

> ⚠️ **Discrepância de configuração:** a rota real do webhook é `POST /stripe/webhooks`,
> mas o "Stripe go-live checklist" do `TODO.md` instrui configurar o endpoint como
> `https://<domínio>/webhooks/stripe` (invertido). A ser conferido ao configurar o
> webhook em modo Live — não é bug de código, mas causaria 404 no dashboard Stripe.

**Idempotência por evento (infra):**
- Model `app/models/stripe_webhook_event.rb`: valida presença + unicidade de `stripe_event_id`.
- Migration `db/migrate/20250311120000_create_stripe_webhook_events.rb`: índice único em `stripe_event_id`.
  ⚠️ **Atenção:** o `2025` no nome do arquivo é um erro de digitação — o commit real é de **2026-03-11** (ver §4.5).
- `db/schema.rb:124` confirma a tabela `stripe_webhook_events` e o índice único (`:129`).

---

## Fase 2 — O fluxo real que marca `payment_status = "paid"` (com evidência)

### 2.1 Único ponto de escrita

Grep exaustivo em `app/**/*.rb` e `*.erb`, e busca no histórico git completo
(`git log -S "payment_status: :paid"`), confirmam **um único** caminho de escrita:

```
Order#mark_paid!                        app/models/order.rb:70-73
  update!(payment_status: :paid,
          paid_at: Time.current,
          payment_method: method,
          payment_reference: reference)
        ▲
        │ chamado em UM só lugar:
        │
StripeWebhooksController#mark_order_paid  app/controllers/stripe_webhooks_controller.rb:98
```

- Nenhum outro caller de `mark_paid!` em controllers, views, jobs, admin ou seeds.
- `mark_paid!` nasceu no primeiro commit Stripe (`adc63ac`) e **sempre foi webhook-only**
  (verificado com `git log -S "def mark_paid"` e `git log -S "payment_status: :paid"`).

### 2.2 Caminho de execução no webhook (versão atual, pós-2026-03-11)

```
receive (stripe_webhooks_controller.rb:4)
  ├─ construct_event / verificação de assinatura           :11-22
  ├─ processed_event?(event.id)  → StripeWebhookEvent.exists?  :27, :114   ← idempotência por evento
  │     └─ se já processado: head :ok e retorna              :28-30
  ├─ case event["type"]                                      :32
  │     ├─ "checkout.session.completed" → handle_checkout_session_completed  :33-35, :57
  │     └─ "payment_intent.succeeded"   → handle_payment_intent_succeeded    :37-39, :66
  │           └─ ambos chamam mark_order_paid(order_id, ...)  :61, :70
  ├─ mark_event_processed(event.id)  → StripeWebhookEvent.create!  :45, :117
  └─ head :ok                                                :46

mark_order_paid (stripe_webhooks_controller.rb:79)
  ├─ guard: order_id presente?                               :80
  ├─ order = Order.find_by(id: order_id); guard exists       :85
  ├─ guard: if order.paid? → log e return  (idempotência por pedido)  :92-95
  ├─ order.mark_paid!(method: "stripe", reference: ...)      :98
  └─ OrderMailer.payment_confirmed(order).deliver_later      :104
```

> ⚠️ Este é o fluxo **da versão atual**. A 1ª versão do webhook (out/2025 → mar/2026) **não**
> consultava a tabela `stripe_webhook_events` e tinha guard/rescue diferentes — ver §4.5, §4.6 e §4.7.

### 2.3 O redirect de sucesso NÃO marca paid

- `orders#thank_you` (`orders_controller.rb:147-152`) tem corpo vazio — só renderiza.
- `success_url` carrega `?paid=1`, mas isso só alimenta:
  - `thank_you.html.erb`: badge decidido por `@order.paid?` (lê o banco).
  - `_stripe_pay_button.html.erb:4`: banner "Pagamento em processamento" quando `params[:paid].present?`.
- **Nenhuma escrita no banco em nenhum desses pontos.**

### 2.4 Respostas diretas às perguntas do TODO §3

1. **"Existe controller de success redirect do Stripe Checkout?"**
   Sim — `orders#thank_you`. Mas **não marca paid**; não escreve no banco.

2. **"O mecanismo de marcação como paid tem idempotência própria?"**
   Sim, em dois níveis (detalhado em §3): por evento (índice único) e por pedido (guard `paid?`).
   Há um gap residual sob concorrência (e-mail duplicado). **Ressalva histórica:** a idempotência
   por evento só existe **a partir de 2026-03-11**; antes disso o guard era composto e mais fraco (ver §4.6).

3. **"Pode ter ocorrido marcação duplicada via dupla visita ao success URL?"**
   **Não.** O success URL é somente-leitura. Revisitá-lo não altera `payment_status`.

4. **"15 pedidos existem em produção com status 'paid'. Como foram marcados sem o webhook chegar?"**
   **Premissa corrigida:** não são 15 pedidos pagos — são **7 pedidos pagos (de 15 pedidos no total:
   7 `paid` + 8 `pending`)**. O "15" do TODO era o total, não o total de pagos (ver §4.8).
   O webhook **não** esteve quebrado durante todo o período — apenas entre **2026-03-11 e 2026-05-25**
   (~2,5 meses). Entre **2025-10-08 e 2026-03-11** a 1ª versão do webhook marcava `paid` **direto**,
   **sem** depender da tabela `stripe_webhook_events` (essa dependência só foi introduzida em
   `8f1710e`, 2026-03-11). Portanto os 7 pedidos pagos foram **marcados pelo próprio webhook
   funcionando** nesse período — explicação consistente com o histórico git (§4.5) e que **descarta**
   a hipótese anterior de marcação manual via console. **Confirmado com dados de produção em 2026-08-10**:
   os 7 pedidos têm `payment_reference` = `pi_...` e `paid_at` em dez/2025 (ver §4.8).

---

## 3. Diagnóstico de idempotência (prévia da Fase 3 — sem código de fix)

> As linhas abaixo referem-se à **versão atual** do controller (pós-2026-03-11).
> O comportamento histórico (out/2025 → mar/2026) está em §4.6.

| Camada | Estado | Evidência | Observação |
|---|---|---|---|
| Por evento | ✔️ presente | índice único `stripe_event_id`; `processed_event?`/`mark_event_processed` (`:114`,`:117`); `rescue RecordNotUnique` (`:119`) | Robusto contra reentrega do **mesmo** `event.id`. |
| Por pedido | ⚠️ parcial | guard `if order.paid? return` (`:92`) | Protege o caso **sequencial** de dois eventos distintos (`checkout.session.completed` **e** `payment_intent.succeeded`) para o mesmo pedido — cada um tem `event.id` diferente, então a dedup por evento não os une; o guard `paid?` é quem segura. |
| Concorrência | ❌ gap | check-and-act não-transacional entre `paid?` (`:92`) e `mark_paid!` (`:98`) | Sob entrega **concorrente** dos dois eventos, ambos podem ler `paid? == false` e disparar **e-mail de confirmação duplicado**. O `payment_status` final continua `paid` (idempotente no valor), mas o efeito colateral (e-mail) duplica. |

**Candidatos de fix (Fase 3 — NÃO implementados):**
- `order.with_lock { return if order.paid?; order.mark_paid!(...) }` para tornar o check-and-act atômico.
- Alternativa: `update` condicional atômico (ex.: `where(payment_status: :pending).update_all(...)`)
  e só enviar e-mail se alguma linha foi afetada.

---

## 4. Correção factual na premissa do TODO ⚠️

A premissa do TODO — *"webhooks nunca processados desde março de 2025 / idempotência inoperante por
14+ meses"* — **está errada**, e a causa raiz do engano é um **erro no nome do arquivo de migration**:

```
db/migrate/20250311120000_create_stripe_webhook_events.rb
             ^^^^
             ano digitado como 2025, mas o commit real (8f1710e) é de 2026-03-11
```

O timestamp no nome do arquivo (`20250311120000`, meio-dia exato — típico de valor digitado à mão)
sugere **março de 2025**. Isso é ~6 meses **antes** de a própria tabela `orders` existir, o que já
deveria ter sido sinal de inconsistência. A **data real do commit** que criou a migration é
**2026-03-11** (evidência em §4.5). Consequências:

- A tabela `stripe_webhook_events` **não** existe "desde março de 2025"; a dependência dela no
  webhook nasceu em **2026-03-11**.
- A janela de webhook quebrado é de **~2,5 meses** (2026-03-11 → 2026-05-25), **não** 14 meses.
- Os pagamentos existem desde **out/2025**, e o webhook os processava normalmente até mar/2026.

Isso **não altera** o mecanismo do bug de mar/2026 → mai/2026 (tabela ausente em produção → webhook
falha → `mark_paid!` inalcançável), mas **corrige a linha do tempo** e **inverte** a conclusão sobre
a origem dos 7 pedidos pagos, de 15 no total (webhook operante, não marcação manual).

### 4.5 Timeline confirmada por git

Evidência bruta (`git show -s --format="%ci %s" <sha>` e `git show <sha>:<arquivo>`):

| Data (commit) | SHA | O que mudou |
|---|---|---|
| **2025-10-07** | `adc63ac` | Nasce o fluxo de pagamento: `payment_status` + `Order#mark_paid!`. (commit "Devo continuar mais tarde") |
| **2025-10-08** | `7e88f32` | 1ª versão do `StripeWebhooksController` ("Stripe Working"). Guard de duplicação **composto** (`order.paid? && payment_reference == payment_ref`). **Não consulta** `stripe_webhook_events`. Em erro fatal, `rescue => e` → `head :ok`. |
| **2026-03-11** | `8f1710e` | "Correções: idempotência Stripe, autorização checkout, fixtures e testes". Introduz **idempotência por evento** e passa a **depender da tabela** `stripe_webhook_events`. Migration criada com **ano errado no nome** (`20250311...` em vez de `20260311...`). |
| **2026-05-25** | (deploy Rails 7.2, release v50) | A migration finalmente **roda em produção**; a tabela passa a existir e o webhook **volta a funcionar**. |

**Leitura:** o webhook esteve **operante** de 2025-10-08 até 2026-03-11 (marcava `paid` direto),
**quebrou** de 2026-03-11 a 2026-05-25 (dependia de uma tabela inexistente em produção) e **voltou**
em 2026-05-25.

### 4.6 Risco histórico de duplicação (out/2025 → mar/2026)

Na 1ª versão do webhook (`7e88f32`), o guard de idempotência em `mark_paid_and_email` era **composto**:

```ruby
if order.paid? && order.payment_reference == payment_ref
  Rails.logger.info("[Stripe] Already paid; idempotent skip")
  return
end
```

Implicações desse período:

- O skip só ocorria se o pedido **já estava pago E com a mesma `payment_reference`**.
- Dois eventos **distintos** do mesmo pedido têm referências diferentes
  (`cs_...` de `checkout.session.completed` vs. `pi_...` de `payment_intent.succeeded`). Nesse caso
  o guard **não** protegia: o segundo evento reprocessava e podia **duplicar o e-mail** de confirmação.
- Não havia idempotência por evento (sem tabela `stripe_webhook_events` em uso), então a única
  proteção era esse guard composto.
- O impacto real depende de **quais eventos o endpoint estava inscrito** no Stripe Dashboard nesse
  período (ex.: só `checkout.session.completed`, ou também `payment_intent.succeeded`/`charge.succeeded`).
  Isso **não é determinável a partir do código** — requer inspeção da configuração do webhook no Dashboard.

### 4.7 Mudança de comportamento do `rescue`

O tratamento de erro fatal do webhook **mudou** entre as versões, com efeito direto na política de
retry do Stripe:

- **out/2025 (`7e88f32`):** `rescue => e` (catch-all) → **`head :ok`**. Comentário no próprio código:
  *"catch-all so we DON'T return 500 to Stripe"*. Em erro fatal, o Stripe recebia 200 e **não
  retentava** — falhas eram silenciosas (evento perdido, sem reentrega).
- **pós-2026-03-11:** erro fatal → **`head :internal_server_error`** (HTTP 500). O Stripe **retenta**
  a entrega segundo sua política de backoff. Foi essa mudança que tornou o bug de tabela-ausente
  **visível** (webhooks acumulando 500 no Dashboard) durante mar/2026 → mai/2026.

### 4.8 Confirmação com dados de produção (2026-08-10)

Queries **read-only** em produção (`heroku run rails runner ...`, sem modificar dados) fecham a
última incerteza da Fase 2 e **corrigem a premissa numérica do TODO**:

- **São 7 pedidos pagos, não 15.** A contagem por status em produção é `{"paid"=>7, "pending"=>8}` —
  15 pedidos **no total**, dos quais só 7 estão `paid`. O "15 pedidos paid" do TODO confundiu o total
  de pedidos com o total de pagos.
- **Todos os 7 pedidos pagos têm `payment_reference` no formato `pi_...`** (`payment_intent.succeeded`),
  nenhum `nil` nem formato estranho. **Marcação manual DEFINITIVAMENTE descartada** — agora por
  **evidência de dados**, não por dedução.
- **Todos foram pagos em dezembro/2025**, dentro da janela do webhook funcionando (out/2025 → mar/2026).
  Saída bruta (id | method | reference | paid_at):

  ```
  36  | stripe | pi_3SZcr | 2025-12-01
  100 | stripe | pi_3Sc7C | 2025-12-08
  133 | stripe | pi_3SdC6 | 2025-12-11
  166 | stripe | pi_3SdX7 | 2025-12-12
  167 | stripe | pi_3SdX8 | 2025-12-12
  169 | stripe | pi_3SdXQ | 2025-12-12
  170 | stripe | pi_3SdXf | 2025-12-12
  ```

- **Pedidos `166/167/169/170` foram pagos no mesmo dia (2025-12-12)** com references `pi_` **sequenciais
  mas distintas** — pagamentos reais distintos, **não** duplicação.
- **`StripeWebhookEvent.count = 0`.** A tabela existe em produção desde 2026-05-25, mas **nunca
  registrou um único evento**. Consequência: o fluxo **atual** do webhook (pós-mar/2026, que depende da
  tabela) **nunca foi exercitado em produção** — **não há prova de funcionamento ponta a ponta pós-mar/2026**.
  Consistente com o fato de que os 7 pagamentos são todos de dez/2025 (antes da tabela) e não houve
  novo pagamento desde o deploy de 2026-05-25. **Item aberto para a Fase 3:** testar o webhook com
  Stripe CLI para exercitar o caminho da tabela antes do go-live.

---

## 5. Próximos passos sugeridos (para a Fase 3, mediante aprovação)

1. **Confirmar a hipótese da §2.4/§4.5** com dados de produção (read-only), ex.:
   - `Order.where(payment_status: :paid).pluck(:id, :payment_method, :payment_reference, :paid_at)`
     — se `payment_reference` for `cs_...`/`pi_...` e `paid_at` cair entre out/2025 e mar/2026,
     confirma origem no webhook (não marcação manual).
   - `StripeWebhookEvent.count` e datas de `processed_at` após o `db:migrate` de 2026-05-25.
2. **Fechar o gap de concorrência** (§3) — e-mail duplicado.
3. **Conferir a rota do webhook** (`/stripe/webhooks`) vs. o endpoint no checklist (`/webhooks/stripe`).
4. **Testar o webhook localmente** com Stripe CLI para confirmar que a tabela é usada agora.
5. **Escrever testes** que reproduzam: (a) webhook marca paid uma vez; (b) evento duplicado não
   reenvia e-mail; (c) success URL revisitado não altera status.
6. **Renomear a migration** (`20250311120000` → data correta) — avaliar risco: renomear migration já
   aplicada em produção exige cuidado com `schema_migrations`; provavelmente melhor deixar como está e
   apenas documentar. **Decisão pendente.**

> Todos os itens acima são **pré-requisito de go-live em modo Live** (bloqueador já registrado no TODO).

---

## Histórico de correções desta investigação

- **Revisão 1 — 2026-07-15:** primeira versão deste audit. Concluiu, erroneamente, que:
  1. os 15 pedidos "paid" teriam sido marcados **manualmente via `rails console`**; e
  2. o webhook estaria quebrado **"desde março de 2025 / por 14+ meses"**.
- **Revisão 2 — 2026-08-10:** ambas as conclusões **refutadas com evidência de git**
  (commits `adc63ac` de 2025-10-07, `7e88f32` de 2025-10-08, `8f1710e` de 2026-03-11):
  1. o webhook **funcionava** entre 2025-10-08 e 2026-03-11, marcando `paid` **sem** depender da
     tabela `stripe_webhook_events` — logo os 15 pedidos [nota: número corrigido para 7 na Revisão 3]
     vieram do **webhook operante**, não de marcação manual;
  2. a janela real de webhook quebrado é de **~2,5 meses** (2026-03-11 → 2026-05-25).
- **Revisão 3 — 2026-08-10:** corrigido **"15 pedidos paid" → "7 pedidos pagos (de 15 no total)"**,
  após queries read-only em produção (`{"paid"=>7, "pending"=>8}`; ver §4.8). O erro numérico
  originou-se no **TODO**, que confundiu o **total de pedidos** (15) com o **total de pedidos pagos**
  (7); a confusão propagou-se para as revisões 1 e 2 deste audit.
- **Causa raiz do engano:** o **ano errado no nome do arquivo de migration**
  (`20250311120000` em vez de `20260311...`) sugeria março de **2025**. A revisão 1 tomou o nome do
  arquivo como data real, em vez de checar a data do **commit** (2026-03-11). 
- **Lição:** nome de arquivo de migration **não é fonte confiável de data** — pode ser digitado à mão
  e conter erro de ano. Confirmar timeline sempre pela data do **commit** (`git show -s --format=%ci`),
  não pelo timestamp no nome do arquivo.
