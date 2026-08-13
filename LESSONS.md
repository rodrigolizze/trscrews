# LESSONS.md — lições operacionais aprendidas em produção

Registro de erros que já custaram caro uma vez, para não custarem duas. Cada lição descreve o que
aconteceu, por que a intuição falhou, e a regra prática que fica.

---

## Stripe CLI — verificar endpoints ativos ANTES de `stripe trigger`

**Regra:** antes de rodar `stripe trigger`, abrir o Dashboard → Webhooks (test mode) e confirmar que
**nenhum endpoint ativo aponta para produção**. Desabilitar os que apontarem, ou usar um Sandbox
Stripe separado para desenvolvimento local.

**Por quê:** `stripe trigger` **não** cria o evento no `stripe listen` local. Ele cria o evento na
**conta** Stripe, e a Stripe entrega esse evento para **TODOS** os endpoints ativos daquela conta —
inclusive os que apontam para produção. O `stripe listen` é apenas mais um destino, ao lado dos
endpoints configurados no Dashboard; não é um canal privado.

**Alcance maior do que o `trigger`:** vale para **qualquer** evento gerado na conta. Um checkout
real feito no app local também é entregue à produção. E como `metadata.order_id` carrega IDs baixos
em desenvolvimento (1, 2, 3…), a colisão com pedidos reais de produção é provável — não hipotética.

**Incidente de referência (2026-08-10):** um `stripe trigger payment_intent.succeeded
--add payment_intent:metadata.order_id=1` local marcou o `Order#1` de **produção** como `paid`, com
o `payment_reference` do payment intent de teste, e disparou e-mail de confirmação de pagamento. O
pedido atingido era de teste (`admin@teste.com`), então não houve dano a cliente real — sorte, não
projeto. Revertido no mesmo dia via `update_columns`. Relato completo em `STRIPE_AUDIT.md §4.9`.

**Sinal de alerta que foi ignorado:** o audit registrava que `StripeWebhookEvent.count = 0` em
produção. Isso deveria ter provocado a pergunta "existe endpoint apontando para lá?" — a pergunta
não foi feita.

**Mitigação estrutural:** um Sandbox Stripe separado para desenvolvimento local resolve de vez, sem
depender de lembrar de desabilitar e reabilitar endpoints a cada teste.

---

## Commits com mensagem genérica e escopo largo são candidatos a auditoria

**Regra:** commit cuja mensagem é genérica ("Mailer Working", "Cart done", "WIP") **e** cujo
`--stat` mostra arquivos além do que a mensagem promete deve ser tratado como suspeito. Revisar o
diff inteiro antes de confiar nele, e considerá-lo primeiro candidato ao caçar a origem de um bug
latente — `git log --oneline -S "<símbolo>" --all -- app/` aponta o commit em segundos.

**Por quê:** a mensagem é o único índice que sobrevive. Quando ela não descreve o escopo real, o
commit vira ponto cego: ninguém revisa o que não sabe que está lá, e a mudança não-anunciada entra
sem leitura. O dano não aparece no dia — aparece meses depois, quando alguma condição de volume
finalmente alcança o código.

**Incidente de referência (`ae52c30` "Mailer Working", 2025-09-12):** um único commit plantou
**dois** bugs latentes ao mesmo tempo:

1. **`recalc_totals!` somando associação não-persistida.** Introduziu `order_items.sum(:line_total)`
   em `app/models/order.rb` (+41 linhas) — um `SUM()` em SQL sobre associação que ainda não foi
   salva, que devolve 0. Resultado: `subtotal = 0` e `total = frete` em **15 de 15** pedidos de
   produção. Corrigido em `b1f09ed` (2026-08-11), quase 11 meses depois. Ver `RECALC_TOTALS_FIX.md`.
2. **Remoção do `include Pagy::Frontend`** de `app/helpers/application_helper.rb` — linha que o
   próprio autor havia adicionado 10 dias antes em `a770963`. Sem ela, `pagy_bootstrap_nav` levanta
   `NoMethodError` e o catálogo devolve **500**. Descoberto em 2026-08-13, ao popular o banco de
   development com 22 produtos.

**Por que ficaram invisíveis:** os dois dependiam de **condição de volume**, não de caminho de
código. O primeiro só erra quando o pedido tem itens ainda não salvos; o segundo só dispara quando o
catálogo passa de uma página. Enquanto o catálogo coube em 20 produtos, `/screws` respondeu 200 —
sem sintoma, sem log, sem alarme.

**Sinal prático:** bug que "não existia antes" e não tem commit óbvio associado quase sempre é
latente, não novo. Antes de suspeitar do upgrade/deploy mais recente, rodar
`git log -S` no símbolo que quebrou. Nos dois casos acima o culpado estava a ~11 meses de distância,
e em nenhum dos dois o upgrade do Rails teve participação.

**Mitigação estrutural:** teste de regressão que exercita a **condição de volume**, não só o caminho
feliz — no caso do catálogo, um teste que cria registros suficientes para gerar a segunda página. É
o que transforma "invisível por 11 meses" em "vermelho no primeiro `bin/rails test`".
