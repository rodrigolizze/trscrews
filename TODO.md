## URGENTE — Auditoria completa do fluxo Stripe (descoberto 2026-05-25)

Durante o deploy da Etapa C do upgrade (Rails 7.2), descobriu-se que
a migration CreateStripeWebhookEvents (timestamp 20250311120000)
nunca havia rodado em produção. Consequências auditadas:

1. **Webhooks Stripe ficaram ~2,5 meses sem ser processados em
   produção** (2026-03-11 → 2026-05-25). O controller
   stripe_webhooks_controller.rb falhava silenciosamente com
   PG::UndefinedTable, retornando HTTP 500. O ano "2025" no nome da
   migration é typo: o commit real (8f1710e) é de 2026-03-11.

2. **Idempotência por tabela foi inoperante nesses ~2,5 meses.**
   StripeWebhookEvent.count em produção = 0 antes do db:migrate de
   2026-05-25. Antes disso o webhook estava **operante**
   (2025-10-08 → 2026-03-11): a 1ª versão do controller marcava paid
   direto, sem depender da tabela — ver STRIPE_AUDIT.md §4.5 e §4.6.

3. **7 pedidos pagos (de 15 no total: 7 paid + 8 pending) — RESOLVIDO**
   (STRIPE_AUDIT.md §4.8). Não há mistério: foram marcados pelo
   **próprio webhook**, operante na época (out/2025 → mar/2026),
   quando a 1ª versão do controller marcava paid direto, sem depender
   da tabela. Evidência de produção: os 7 têm payment_reference no
   formato `pi_...` (payment_intent.succeeded) e paid_at em
   dezembro/2025, dentro da janela do webhook funcionando — marcação
   manual descartada por dados, não por dedução. O redirect de
   sucesso (orders#thank_you) tem corpo vazio e não escreve no banco
   (§2.3), então dupla visita ao success URL não marca nada.

4. **Desde o deploy de 2026-05-25 a tabela existe** e novos webhooks
   devem passar a ser gravados — mas isso **ainda não foi comprovado
   em produção**: StripeWebhookEvent.count continua 0 (nenhum
   pagamento novo desde então). O passado não pode ser reconstruído.

### Ações pendentes (ordem):

- [x] Auditar app/controllers/ procurando por StripeController,
      OrdersController#success, ou similar — Fase 1
      (STRIPE_AUDIT.md §1): existe um caminho único de escrita.
- [x] Identificar o método que marca order.payment_status = "paid"
      — `Order#mark_paid!` (app/models/order.rb:70), chamado apenas
      por StripeWebhooksController#mark_order_paid.
- [x] Adicionar idempotência — hoje em três níveis: por evento
      (stripe_webhook_events + índice único), guard `paid?` por
      pedido, e row lock `with_lock` contra a corrida entre dois
      eventos distintos do mesmo pedido (commit 2b21373).
- [x] Corrigir bug do checkout.session.completed — Stripe::StripeObject
      não implementa #dig, então todo evento desse tipo levantava
      NoMethodError e retornava HTTP 500 (commit 416554f, com os
      primeiros testes do webhook).
- [x] Corrigir o endpoint citado neste TODO — é /stripe/webhooks,
      não /webhooks/stripe (config/routes.rb:63).
- [x] Testar webhook com Stripe CLI localmente para confirmar que
      a tabela está sendo usada agora — **RESOLVIDO (2026-08-10)**.
      O fluxo dependente da tabela foi exercitado ponta a ponta, e há
      prova em **produção**: StripeWebhookEvent tem 2 linhas gravadas
      (evt_3U2xeC... e evt_3U2xzp...) — evento recebido, assinatura
      verificada, pedido marcado, idempotência registrada. A prova veio
      de forma acidental, pelo incidente do `stripe trigger` que atingiu
      produção (STRIPE_AUDIT.md §4.9; lição em LESSONS.md).
- [ ] BLOQUEADOR de go-live em produção real

Esta tarefa BLOQUEIA mudança para Stripe live mode (já listado em
TODO existente "Stripe go-live checklist").

## ~~Investigar recalc_totals! — totais zerados~~ — RESOLVIDO em 2026-08-11

- [x] Confirmado em produção: **15 de 15** pedidos com `subtotal = 0` e
      `total = frete`. `order_items.sum(:line_total)` é um `SUM()` em SQL
      sobre associação ainda não persistida (`recalc_totals!` roda antes
      do `save`) e devolvia 0. Bug presente desde `ae52c30` (2025-09-12);
      a linha nunca havia sido modificada.
- [x] **Fix** (`b1f09ed`, release v52): soma em memória
      `order_items.sum { |i| i.line_total.to_d }`, mesmo critério de
      `items_subtotal`. Teste de regressão pelo fluxo real em
      `test/controllers/orders_controller_test.rb` (nasceu RED).
- [x] **Dados:** os 15 pedidos eram todos sintéticos — deletados em
      produção (`Order.destroy_all`, backup `b005` antes). Backfill
      descartado por não haver dado real a preservar.

Detalhamento completo em `RECALC_TOTALS_FIX.md`.

**Sobra desse trabalho (não bloqueante):** `ShippingAddress` (10) e
`User` (15) de teste seguem em produção, assim como os screws 34
("Produto Teste") e 35 ("Vai seus bundão"). Limpeza de catálogo e
usuários é decisão separada. O estoque decrementado pelos pedidos
apagados (31 unidades em 7 parafusos) não foi restaurado.

## Habilitar pagamentos reais (BLOQUEADOR PARA LANÇAMENTO)

Atualmente Stripe está em test mode. Antes de aceitar pagamentos
reais, executar nesta ordem:

### Requisitos legais/compliance (FAZER ANTES de qualquer mudança de código)
- [ ] Conta Stripe ativada em modo Live (verificação de identidade,
      CNPJ ou CPF habilitado no Stripe Brasil)
- [ ] Política de reembolso publicada no site
- [ ] Termos de uso revisados (consultar advogado)
- [ ] Política de privacidade atualizada (LGPD)
- [ ] Definir suporte ao cliente (email, prazo de resposta)

### Configuração técnica
- [ ] Setar STRIPE_SECRET_KEY no Heroku com chave sk_live_ (não sk_test_)
- [ ] Setar STRIPE_SIGNING_SECRET no Heroku com webhook secret de
      produção (diferente do de teste — gerar no dashboard Stripe modo Live)
- [ ] Criar o webhook endpoint no dashboard Stripe modo LIVE apontando
      para https://<domínio>/stripe/webhooks, com signing secret de Live.
      O endpoint de TEST mode já existe e sempre esteve com a rota
      CORRETA: "Heroku TRScrews (test)" →
      trscrews-prod-4185ac87e394.herokuapp.com/stripe/webhooks,
      escutando 2 eventos (payment_intent.succeeded e
      checkout.session.completed), API 2025-09-30.clover. Use-o como
      molde. Live e Test têm listas de endpoints SEPARADAS no Dashboard;
      a de Live ainda está vazia.
      NOTA: o endpoint test-mode foi DESABILITADO em 2026-08-10 durante
      o desenvolvimento, para que `stripe trigger` local não atinja
      produção (ver STRIPE_AUDIT.md §4.9). Reabilitar quando voltar a
      testar contra produção em test mode, ou recriar em Live no go-live.
- [ ] Confirmar que stripe initializer aceita ambas as chaves sem
      mudança de código
- [ ] Rotacionar a STRIPE_SECRET_KEY de teste (sk_test_) — exposta em
      screenshot em 2026-08-10. Resolvido naturalmente ao migrar para
      sk_live_ no go-live; não exige rotação isolada antes disso, já que
      é chave de test mode e não movimenta dinheiro real.
- [ ] Webhook não valida valor nem moeda: o handler marca paid
      confiando só em metadata.order_id, sem conferir se amount/currency
      do payment_intent batem com o total do pedido. Descoberto no teste
      E2E (2026-08-10): um evento de USD 20,00 marcou pago um pedido de
      R$ 59,80. Com assinatura verificada não é buraco de segurança
      direto, mas metadata errada ou evento de outro fluxo marcaria
      pedido com valor divergente sem alarme. Adicionar verificação
      amount/currency antes do go-live live mode.

### Decisão de arquitetura (futuro, se relevante)
- [ ] Manter Stripe Checkout hospedado (atual — mais simples, menos
      compliance) ou migrar para Stripe Elements (UI customizada,
      requer STRIPE_PUBLISHABLE_KEY no front-end e compliance PCI
      mais rigoroso)

### Validação antes de lançamento
- [ ] Fazer pedido real com cartão de crédito próprio
- [ ] Confirmar que webhook processa e atualiza payment_status
- [ ] Confirmar que email de confirmação chega
- [ ] Testar fluxo de reembolso via dashboard Stripe

## Otimização do modelo 3D do parafuso (PRIORITÁRIO)

**Estado atual:** `app/assets/images/screw.glb` tem 31MB e está em uso
via asset_path no JavaScript (screw_3d.js). Cada visitante baixa 31MB
para ver o parafuso girando na home. Em conexões móveis pode levar
20-60 segundos.

**Ações futuras (NÃO fazer agora):**
1. Comprimir o modelo com Draco compression no glTF — reduz para ~300KB
   sem perda visual perceptível
2. Verificar quantos polígonos o modelo tem hoje — pode ter sido
   exportado em qualidade muito alta sem necessidade
3. Considerar LOD (Level of Detail) — carregar versão menor primeiro
4. Remover `public/screw.glb` (324KB, órfão, sem referências no código)

Essa otimização não bloqueia a migração Cloudinary, mas é trabalho
prioritário antes do site ter qualquer usuário real.

## Otimização de assets binários (futuro)

- Banners PNG (banner-tr-autofix.png 2.6MB, etc.) e cards (1.5-2.6MB)
  devem ser convertidos para WebP ou re-exportados com compressão.
- Avaliar uso de bg_segundasection.png (3.4MB) — pode virar
  gradient CSS?

## CSP desabilitada — risco médio (ver AUDIT.md §4.8)

Sem Content Security Policy, scripts injetados via XSS não são
bloqueados pelo browser. Para um e-commerce com formulários de
pagamento, o risco é real.

**Ação:** Descomentar e configurar `config/initializers/content_security_policy.rb`
com ao menos: `default_src :self`, `script_src :self 'unsafe-inline'`,
`connect_src :self https://js.stripe.com`, `frame_src https://js.stripe.com`.
Fazer antes do lançamento com usuários reais.

## Fat controller: orders_controller.rb (258 linhas — ver AUDIT.md §5)

O controller acumula: montar carrinho, validar estoque, criar pedido,
persistir endereço, calcular frete, autorização customizada.

**Ação:** Extrair lógica de `create` para `OrderCreationService` em
`app/services/`. O controller fica responsável apenas por receber
params, chamar o service e redirecionar. PRÉ-REQUISITO: ter testes
de integração cobrindo o fluxo de pedido atual ANTES de refatorar.
Sem testes, qualquer refator é arriscado. Ordem correta: completar
upgrade Rails → escrever testes → refatorar.

## ~~Paginação do catálogo — dois ajustes de initializer~~ — RESOLVIDO em 2026-08-13

Descobertos em 2026-08-13, ao popular o banco de development com 22
produtos para validar o catálogo sob Rails 8.0. Nenhum dos dois era
regressão do upgrade. O 500 do `pagy_bootstrap_nav` que apareceu na
mesma investigação já havia sido corrigido antes (regressão de
`ae52c30`; lição em `LESSONS.md`); estes dois sobraram porque mexem em
`config/initializers/pagy.rb` e mereciam consideração própria.

Ambos fechados no commit "Cleanup: close D1 loose ends — Stripe
app_info, Redis phantom, pagy overflow".

- [x] **`?page=99` levantava `Pagy::OverflowError` → HTTP 500** —
      **CORRIGIDO.** Página fora do intervalo derrubava a requisição:
      `Pagy::OverflowError: expected :page in 1..2; got 99`. Alcançável
      por qualquer um que editasse a URL, ou por crawler seguindo link
      de paginação obsoleto depois de o catálogo encolher.
      **Fix aplicado:** `require "pagy/extras/overflow"` +
      `Pagy::DEFAULT[:overflow] = :last_page` — página fora do intervalo
      passa a servir a **última página** em vez de levantar.
      **Teste de regressão** em `test/controllers/screws_controller_test.rb`
      ("serves the last page instead of raising when the requested page
      overflows"), nascido RED com o `Pagy::OverflowError` real. A
      asserção em `li.page-item.active` distingue "serviu a última
      página" de apenas "não deu 500" — sem ela o teste passaria também
      com `:empty_page`. Validado local contra os 22 screws do seed:
      `?page=99` e `?page=999` → HTTP 200, página ativa 2, 2 cards.

- [x] **`Pagy::DEFAULT[:items] = 12` era letra morta** — **REMOVIDO,
      sem mudança de comportamento.** O pagy 9 renomeou a variável
      `:items` para `:limit` sem compatibilidade: `Pagy::DEFAULT` trazia
      `{items: 12, limit: 20}` e o valor honrado era o `:limit`. A
      intenção original (12 por página) estava silenciosamente perdida
      desde o salto do pagy para a série 9.
      **Decisão (2026-08-13): manter 20 por página.** Ninguém decidiu
      ativamente por 12 — era resíduo, não escolha. Removida a linha
      morta em vez de "restaurar" um layout que nunca esteve em vigor;
      o catálogo em produção não muda. O initializer ganhou um
      comentário explicando a ausência, para impedir que a linha seja
      re-adicionada por engano.

## Modernizar asset pipeline (futuro, pós Rails 8.1.3)

Migrar Sprockets → Propshaft + dartsass-sprockets → dartsass-rails.
Alinha o projeto com o default do Rails 8. Exige auditar referências
de asset_path/image_tag/stylesheet_link_tag em views e helpers.
Trabalho estimado: 4-6h. NÃO faz parte do upgrade Rails 8 em si.

## Redesign do site (futuro, pós upgrade Rails 8.1.3)

O design atual é funcional mas simples (tipografia padrão Bootstrap,
cores limitadas, hierarquia visual fraca em algumas páginas). Após
conclusão do upgrade Rails 8.1.3, revisar:
- Sistema de design coerente (paleta expandida, tipografia, espaçamentos)
- Hierarquia visual nas páginas de produto e catálogo
- Mobile-first review (testar em telas pequenas)
- Animações e transições sutis para sensação de qualidade

Tarefa independente, fora do escopo do upgrade Rails.

## Habilitar YJIT em produção (pós Rails 7.2 estável)

YJIT foi desabilitado preventivamente no upgrade 7.2 para isolar variáveis.
Após confirmar que Rails 7.2 está estável em produção por ~1 semana:

- [ ] Remover `Rails.application.config.yjit = false` de
      `config/initializers/new_framework_defaults_7_2.rb`
- [ ] Deploy em release separada
- [ ] Monitorar `heroku logs` e `heroku ps` por R14 (memory exceeded)
- [ ] Se R14 aparecer: adicionar `RUBY_YJIT_ENABLE=0` nas config vars do Heroku
      e não reabilitar até upgrade de dyno tier

## `config.responder.error_status` deprecado no Rack 3.2 (descoberto 2026-08-18)

`config/initializers/devise.rb:305` traz
`config.responder.error_status = :unprocessable_entity`. O Rack 3.2 **removeu esse
símbolo** do `SYMBOL_TO_STATUS_CODE` — ele sobrevive apenas por um caminho de
compatibilidade que o próprio Rack anuncia que vai remover:

```
SYMBOL_TO_STATUS_CODE[:unprocessable_entity]   = nil
SYMBOL_TO_STATUS_CODE[:unprocessable_content]  = 422
Rack::Utils.status_code(:unprocessable_entity) = 422
  + warning: Status code :unprocessable_entity is deprecated and will be
             removed in a future version of Rack. Please use :unprocessable_content instead.
```

**Funciona hoje** — não há bug em aberto. O Fluxo 1 do Devise 5.0 devolveu 422 em
todos os pontos esperados (`DEVISE_50_MIGRATION.md` §10.5 e §11.2).

**Origem: Rack 3.2, que entrou com a Etapa E** (Rails 8.1.3.1) — não é do Devise.
Descoberto na revisão do initializer da Etapa F (`DEVISE_50_MIGRATION.md` §12.3) e
deixado de fora daquele commit de propósito, para não misturar assunto de outra
dependência no diff do upgrade.

- [ ] Trocar para `config.responder.error_status = :unprocessable_content`
      (uma linha; `config/initializers/devise.rb:305`)
- [ ] **Escrever o teste que hoje não existe** — `grep -rn "422\|unprocessable" test/`
      não devolve **nada**: a suíte não cobre esse caminho. O 422 foi observado
      só manualmente (Fluxo 1: login inválido e troca de e-mail rejeitada).
      Um teste de sign_in com senha errada asserindo `assert_response
      :unprocessable_entity` fecha o buraco e vira a rede de proteção da troca
- [ ] `bin/rails test` depois da troca (baseline atual: 24 runs / 64 assertions)
- [ ] Conferir que não há outro `:unprocessable_entity` literal no projeto:
      `grep -rn "unprocessable_entity" app/ config/ test/`

## Política de senha fraca em produção (descoberto 2026-08-18)

Ao validar a Etapa F (Devise 5.0.4), um teste de senha por leitura pura
(`valid_password?`, sem escrita) contra os 12 usuários confirmados de produção
mostrou que **`123456` autentica em 5 das 15 contas**. Outras candidatas
triviais (`1234567`) batem em mais.

**Contexto que reduz a urgência hoje:** são todos usuários de **teste** —
produção não tem clientes reais ainda (`Order.count = 0`; ver
`RECALC_TOTALS_FIX.md`). Não há dado de terceiro protegido por essas senhas.

**Fora do escopo da Etapa F** — a F trocou a versão do Devise, não a política
de senha. `config.password_length = 6..128` (`config/initializers/devise.rb`)
aceita `123456` por comprimento; não há validação de senha comum.

- [ ] Quando houver usuários reais: adotar validação contra senhas comuns
      (ex.: gem `zxcvbn` ou lista de bloqueio) e/ou elevar o mínimo de 6
- [ ] Considerar forçar reset das contas de teste antes de abrir para clientes,
      ou deletá-las (são dados de teste remanescentes)

## Heroku tem um commit fora do GitHub — d63f910 (descoberto 2026-08-18)

No deploy da Etapa F (`git push heroku master:main`, v57), o range foi
**`d63f910..7be6d57`**. O `d63f910` era o topo anterior do `main` do Heroku e
**não existe no histórico do GitHub** — lá o topo antes deste deploy era
`a2e95d3`. Em algum momento o Heroku recebeu um push que não passou pelo
`origin`, ou os dois remotes divergiram.

**Não afetou a Etapa F:** o merge `7be6d57` subiu inteiro por cima, e a
validação em produção passou. Mas é uma divergência de histórico que vale
entender antes que cause confusão num rollback futuro (um `git push heroku
<sha>:main` só funciona com SHA que o Heroku conheça).

- [ ] `git fetch heroku` e comparar: `git log --oneline heroku/main` contra
      `origin/master` — achar onde divergiram
- [ ] Descobrir o que é `d63f910` (deploy manual? push direto? release antiga?)
- [ ] Decidir se realinhar os dois remotes ou só documentar a diferença
- [ ] Não urgente — produção está correta (7be6d57); é higiene de histórico
