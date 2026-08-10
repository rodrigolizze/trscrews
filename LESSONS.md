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
