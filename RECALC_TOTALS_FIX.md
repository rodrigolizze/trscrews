# RECALC_TOTALS_FIX.md — Plano de correção do `recalc_totals!` + backfill

**Data:** 2026-08-11
**Autor:** investigação assistida (Claude Code)
**Status:** **EXECUTADO em 2026-08-11.** O plano original está preservado abaixo; o que de fato
aconteceu está na **§9 — Resultado da execução**. A estratégia mudou no meio do caminho: o **backfill
da §4 foi descartado** e substituído pelo **delete dos 15 pedidos**, ao se confirmar que nenhum dado
era real. As seções superadas estão marcadas.
**Relacionado:** `TODO.md` (seção "Investigar recalc_totals!"), `STRIPE_FIX_PLAN.md §9.4` (achado nº 1),
`AUDIT.md §5` (fat controller), `LESSONS.md`.

> **Diagnóstico já fechado (2026-08-11), com dados de produção:** os **15** pedidos existentes têm
> `subtotal = 0`; o `total` gravado é igual ao frete em todos os 15. O bug nasceu em `ae52c30`
> (2025-09-12) e a linha responsável **nunca foi modificada desde então**. Os `order_items` estão
> íntegros (16/16 com `line_total = unit_price × quantity`, zero órfãos), então o backfill tem fonte
> de verdade confiável. Ninguém foi cobrado a menos — o Stripe fatura a partir dos `order_items`,
> não das colunas.

---

## 1. O bug

### 1.1 Código atual

**`app/models/order.rb:32-41`**

```ruby
32  def recalc_totals!
33    # soma dos itens
34    self.subtotal = order_items.sum(:line_total)     # ← BUG
35
36    # mantém `shipping` em sincronia com `shipping_fee`
37    self.shipping = (shipping_fee || shipping || 0).to_d
38
39    # total = subtotal + frete
40    self.total = subtotal.to_d + shipping            # ← herda o 0 da linha 34
41  end
```

**`app/controllers/orders_controller.rb:76-116`** — o **único** call site do repositório
(`grep -rn "recalc_totals!"` devolve apenas a definição em `order.rb:32` e esta chamada):

```ruby
 76    ActiveRecord::Base.transaction do
 ...
 95            @order.add_item!(screw, qty)      # build em memória — NÃO persiste
 ...
107      @order.shipping_fee = shipping_for(@order.order_items.sum(&:line_total), uf: @order.state)
                                                                   # ↑ sum com BLOCO = memória → correto
110      @order.recalc_totals!                   # ← @order ainda é new_record?
113      unless @order.save                      # ← só aqui os itens vão para o banco
```

E `add_item!` (`app/models/order.rb:50-58`), que constrói sem persistir:

```ruby
57    order_items.build(screw: screw, quantity: qty, unit_price: unit_price, line_total: line_total)
```

### 1.2 Por que `sum(:line_total)` devolve 0

`order_items.sum(:line_total)` — com **símbolo** — é uma agregação delegada ao banco: o Active Record
emite `SELECT SUM("order_items"."line_total") FROM "order_items" WHERE "order_items"."order_id" = $1`.

Quando `recalc_totals!` roda na linha 110, o `@order` ainda é `new_record?` — o `save` só acontece na
linha 113. Um registro não persistido não tem `id`, então a associação `order_items` é uma
**null relation**: o Active Record sabe que não há chave estrangeira para consultar e devolve o
elemento neutro da agregação, **0**, sem sequer ir ao banco. Os itens existem, mas apenas **em
memória**, como objetos construídos por `build` — invisíveis para qualquer `SUM()` em SQL, porque as
linhas ainda não foram inseridas na tabela `order_items`.

A linha 107 escapa porque usa `sum(&:line_total)` — a forma de **bloco**, que é
`Enumerable#sum` sobre os objetos carregados em memória, não `ActiveRecord::Calculations#sum`. Duas
somas com nomes quase idênticos e semânticas opostas, a quatro linhas de distância: é isso que faz o
**frete sair certo** e o **subtotal sair zerado** no mesmo método.

### 1.3 Manifestação

| Onde | Lê o quê | Resultado |
|---|---|---|
| `app/views/orders/show.html.erb:116,124` | colunas `subtotal`/`total` | **errado** — cliente vê "Subtotal R$ 0,00 / Total R$ 20,00" |
| `app/views/orders/mine.html.erb:50-51` | coluna `total` | **errado** — lista de pedidos mostra R$ 20,00 |
| `app/views/admin/orders/index.html.erb:42` | coluna `total` | **errado** |
| `app/views/admin/orders/show.html.erb:82,90` | colunas `subtotal`/`total` | **errado** |
| `app/views/order_mailer/*` (4 arquivos) | `items_subtotal`/`total_amount` | **certo** — soma em memória |
| `app/controllers/checkout_sessions_controller.rb:27-42,45-52` | `order_items` + `shipping_fee` | **certo** — Stripe cobrou o valor correto |

O cliente recebe e-mail com R$ 43,30, paga R$ 43,30 no Stripe, e ao abrir o pedido no site lê
**R$ 20,00**. Foi essa assimetria (e-mails certos, telas erradas) que manteve o bug invisível por
~11 meses.

---

## 2. O fix de código — três opções

### (a) Somar em memória — `order_items.sum { |i| i.line_total.to_d }`

```ruby
def recalc_totals!
  self.subtotal = order_items.sum { |i| i.line_total.to_d }   # ← única linha alterada
  self.shipping = (shipping_fee || shipping || 0).to_d
  self.total    = subtotal.to_d + shipping
end
```

| Critério | Avaliação |
|---|---|
| **Risco** | **Baixo.** Uma linha. Funciona em registro novo (soma os `build`) **e** em persistido (carrega a associação e soma). |
| **Efeito colateral** | Carrega os `order_items` em memória quando o pedido já existe — irrelevante nesta escala (16 itens em 15 pedidos; máximo de 2 por pedido). |
| **Mantém `recalc_totals!` como método único?** | **Sim.** Corrige na origem: todo caller presente e futuro passa a receber o valor certo. |
| **Precedente no projeto** | É exatamente a lógica de `items_subtotal` (`order.rb:83-86`), em produção desde 2025-12-16 e comprovadamente correta — os e-mails a usam. |

### (b) Mover `recalc_totals!` para depois do `save` (reordenar o controller)

| Critério | Avaliação |
|---|---|
| **Risco** | **Alto.** Exige **dois** writes: salvar o pedido (com `subtotal = 0`), recalcular, salvar de novo. Mexe na sequência de uma transação que também controla estoque com `with_lock` (`orders_controller.rb:90-98`). |
| **Efeito colateral** | Existe uma janela em que a linha está gravada com valor errado. Aumenta o `orders_controller#create`, já apontado como fat controller em `AUDIT.md §5` — anda na direção oposta da dívida registrada. |
| **Mantém `recalc_totals!` como método único?** | **Não resolve nada no método.** Ele continua devolvendo 0 para qualquer chamada pré-save. O próximo caller cai na mesma armadilha. |

### (c) Callback `after_save`

| Critério | Avaliação |
|---|---|
| **Risco** | **Médio-alto.** Escrever dentro de `after_save` exige `update_columns` para não recursar. Adicionar callback a modelo é mudança classificada como **"maior"** no `CLAUDE.md`. |
| **Efeito colateral** | Dispara em **todo** save do pedido — inclusive `mark_paid!` (`order.rb:70-73`), chamado pelo webhook dentro do `with_lock` (`stripe_webhooks_controller.rb`). Passaria a haver recálculo de totais dentro do caminho crítico de pagamento, que hoje é enxuto e auditado. Fluxo implícito, difícil de rastrear. |
| **Mantém `recalc_totals!` como método único?** | Formalmente sim, mas **o método continua quebrado** para chamada direta pré-save; o callback só mascara o sintoma no caminho feliz. |

### Recomendação: **(a)**

Justificativa:

1. **Corrige a causa, não o sintoma.** O defeito está em `order.rb:34`, não na ordem do controller.
   (a) conserta lá; (b) e (c) deixam o método defeituoso e contornam por fora.
2. **Superfície mínima.** Uma linha, num método de 10. (b) reescreve o miolo de uma transação com
   controle de estoque; (c) adiciona callback ao modelo central do sistema.
3. **Não toca no caminho de pagamento.** (c) colocaria recálculo dentro do `mark_paid!` do webhook,
   que acabou de ser estabilizado na Fase 3 do Stripe. Não misturar.
4. **Lógica já validada em produção.** É a mesma soma de `items_subtotal`, correta desde 2025-12-16.
5. **Prepara a consolidação da §3** sem a exigir: depois de (a), coluna e método calculam por
   caminhos idênticos.

---

## 3. Consolidação com `items_subtotal`/`total_amount` — **fase separada**

### Situação

`order.rb:83-96` define três métodos paralelos às colunas:

```ruby
83  def items_subtotal;  order_items.sum { |item| item.line_total.to_d }; end
88  def shipping_amount; (shipping_fee || shipping || 0).to_d;            end
93  def total_amount;    items_subtotal + shipping_amount;               end
```

Eles nasceram em `1a5046c` (2025-12-16), com o comentário revelador *"Soma garantida dos itens,
**sem depender do campo subtotal estar salvo**"* — ou seja, foram um **contorno** do bug, não uma
funcionalidade. Views e e-mails migraram para eles; as telas de pedido e o admin ficaram nas colunas.

### O problema real não é a duplicação, é a divergência silenciosa

Ter duas fontes de verdade não teria sido grave se elas discordassem **em voz alta**. O que aconteceu
foi o oposto: os e-mails ficaram certos, as telas ficaram erradas, e ninguém comparou. A duplicação
foi o mecanismo de camuflagem do bug por ~11 meses.

### Recomendação

**Consolidar, mas em fase separada — não misturar com o fix urgente.** Motivo operacional: se as
views mudarem no mesmo commit do fix, um número errado numa tela deixa de ter causa identificável
(veio do fix? da mudança de view?). O fix precisa ser isolado para que a validação seja conclusiva.

Direção proposta para a fase 2 (a decidir depois, com plano próprio):

- Views e admin voltam a ler as **colunas** — elas passam a ser a fonte única, e são o registro
  histórico correto (snapshot do que foi cobrado, imune a mudança futura na tabela de fretes).
- `items_subtotal`/`total_amount` deixam de ser usados para exibição e passam a ser **helpers de
  verificação de consistência** — usados num teste que assere `order.subtotal == order.items_subtotal`
  para todo pedido, transformando qualquer regressão futura em teste vermelho em vez de tela errada.
- Alternativa mais radical (remover os métodos) **não é recomendada**: eles são o que permite detectar
  a divergência.

**Ordem obrigatória:** fase 2 só depois do fix **e** do backfill. Antes disso, apontar as views para
as colunas pioraria a exibição dos 15 pedidos existentes.

---

## 4. Backfill dos 15 pedidos — ⚠️ SEÇÃO SUPERADA, NÃO EXECUTADA

> **Esta seção inteira foi descartada.** Depois de escrita, confirmou-se que os 15 pedidos e seus
> itens eram **dados de teste sintéticos** — sem cliente, sem venda real, sem histórico a preservar
> (o pedido 168, de R$ 1.000.000,00, é a evidência mais óbvia). Corrigir colunas de dados
> descartáveis não tinha valor, então a estratégia virou **deletar** os 15 pedidos. Ver §9.3.
>
> O conteúdo abaixo fica registrado porque a investigação da §4.2 (qual coluna de frete é confiável,
> e por quê) continua sendo o registro de como `shipping` e `shipping_fee` se comportam — informação
> válida independentemente do backfill ter acontecido.

### 4.1 Fórmula

Para cada pedido:

```
subtotal = Σ order_items.line_total     (soma em memória, itens já persistidos)
shipping = shipping_fee                 (ver 4.2 — decisão justificada)
total    = subtotal + shipping
```

### 4.2 Qual `shipping` usar — decisão: **`shipping_fee`**

As três candidatas foram avaliadas com dados de produção:

| Candidata | Veredito |
|---|---|
| **Coluna `shipping`** | ❌ **Descartada.** Está errada em 3 dos 15 (ids 1, 34, 35: valor `0,00` com `shipping_fee = 20,00`), porque foram criados antes de `5d3d967` (2025-12-01 15:13), commit que introduziu a sincronização. Usá-la propagaria o erro. |
| **Recalcular via `shipping_for`** | ❌ **Descartada.** `application_controller.rb:32-38` calcula por região a partir de `Rails.configuration.x.shipping`, que é **override-able por ENV** (`SHIPPING_FEE_SUDESTE`, `SHIPPING_FREE_LIMIT`). Recalcular hoje amarra o registro histórico à configuração de hoje: mudar a tabela de fretes reescreveria o passado. Além disso o método vive num **controller**, indisponível a um script de modelo sem duplicar a lógica. |
| **Coluna `shipping_fee`** | ✅ **Escolhida.** É o snapshot histórico do frete no momento do pedido, e é **o valor que o Stripe efetivamente cobrou** — `checkout_sessions_controller.rb:45-52` monta a linha "Frete" preferindo `shipping_fee`. Alinhar a coluna com o que foi faturado é a definição de correto aqui. |

**Verificação executada em produção (read-only)** — comparando `shipping_fee` com o que uma
recalculação daria hoje:

```
free_limit=150.0  tabela={:sudeste=>20.0, :sul=>25.0, :centro_oeste=>30.0, :nordeste=>35.0, :norte=>40.0}
id | uf | regiao | items_sum | shipping_fee | frete_recalculado | veredito
1 | SP | sudeste | 23.3 | 20.0 | 20.0 | OK
34 | SP | sudeste | 144.1 | 20.0 | 20.0 | OK
35 | SP | sudeste | 19.5 | 20.0 | 20.0 | OK
36 | SP | sudeste | 23.3 | 20.0 | 20.0 | OK
37 | SP | sudeste | 19.5 | 20.0 | 20.0 | OK
67 | SP | sudeste | 99.5 | 20.0 | 20.0 | OK
68 | SP | sudeste | 97.5 | 20.0 | 20.0 | OK
100 | SP | sudeste | 22.75 | 20.0 | 20.0 | OK
133 | SP | sudeste | 200.0 | 0.0 | 0.0 | OK
166 | SP | sudeste | 100.0 | 20.0 | 20.0 | OK
167 | SP | sudeste | 100.0 | 20.0 | 20.0 | OK
168 | SP | sudeste | 1000000.0 | 0.0 | 0.0 | OK
169 | SP | sudeste | 20.9 | 20.0 | 20.0 | OK
170 | SP | sudeste | 39.0 | 20.0 | 20.0 | OK
171 | SP | sudeste | 100.0 | 20.0 | 20.0 | OK
```

**As duas convergem em 15/15 hoje** (todos os pedidos são de SP/sudeste). A escolha por `shipping_fee`
não muda nenhum número — muda a **justificativa**: usamos o dado histórico, não uma reconstrução que
depende de configuração mutável. Se amanhã o frete do sudeste virar R$ 25, o backfill continua certo.

### 4.3 Casos 133 e 168 — tratamento **uniforme**, sem exceção

| Pedido | Hoje | Depois do backfill | Observação |
|---|---|---|---|
| **133** | `subtotal=0, shipping=0, total=0`, items=200,00, **paid** | `subtotal=200,00, shipping=0, total=200,00` | `shipping_fee = 0` está **correto**: 200,00 ≥ R$ 150 aciona o frete grátis. Não é anomalia. |
| **168** | `subtotal=0, shipping=0, total=0`, items=1.000.000,00, pending | `subtotal=1.000.000,00, shipping=0, total=1.000.000,00` | Frete 0 pelo mesmo motivo. O valor absurdo é **dado de teste**, não corrupção. |

**Uniformemente.** A fórmula é a mesma para os 15. O trabalho do backfill é tornar as colunas
consistentes com os itens, **não julgar se o dado de negócio faz sentido**. Criar exceção para o 168
significaria embutir uma regra arbitrária ("acima de X, não corrigir") num script de reparo — pior que
o problema.

O que fazer com o pedido 168 é **decisão separada**, fora deste plano: ele está `pending`, nunca foi
pago, e é claramente lixo de teste. Apagá-lo ou não é uma limpeza de dados a discutir depois — se for
apagado antes do backfill, o backfill simplesmente processa 14 em vez de 15.

### 4.4 Efeito esperado, pedido a pedido

| id | subtotal: 0 → | shipping: atual → | total: atual → | pago? |
|---|---|---|---|---|
| 1 | 23,30 | 0,00 → 20,00 | 20,00 → 43,30 | |
| 34 | 144,10 | 0,00 → 20,00 | 20,00 → 164,10 | |
| 35 | 19,50 | 0,00 → 20,00 | 20,00 → 39,50 | |
| 36 | 23,30 | 20,00 (=) | 20,00 → 43,30 | **paid** |
| 37 | 19,50 | 20,00 (=) | 20,00 → 39,50 | |
| 67 | 99,50 | 20,00 (=) | 20,00 → 119,50 | |
| 68 | 97,50 | 20,00 (=) | 20,00 → 117,50 | |
| 100 | 22,75 | 20,00 (=) | 20,00 → 42,75 | **paid** |
| 133 | 200,00 | 0,00 (=) | 0,00 → 200,00 | **paid** |
| 166 | 100,00 | 20,00 (=) | 20,00 → 120,00 | **paid** |
| 167 | 100,00 | 20,00 (=) | 20,00 → 120,00 | **paid** |
| 168 | 1.000.000,00 | 0,00 (=) | 0,00 → 1.000.000,00 | |
| 169 | 20,90 | 20,00 (=) | 20,00 → 40,90 | **paid** |
| 170 | 39,00 | 20,00 (=) | 20,00 → 59,00 | **paid** |
| 171 | 100,00 | 20,00 (=) | 20,00 → 120,00 | |

15 pedidos com `subtotal` e `total` alterados; 3 deles (1, 34, 35) também com `shipping` corrigido.

### 4.5 Por que `update_columns`

- **Pula validações.** Um pedido antigo que não passe nas validações atuais (`state` na lista de UFs,
  formato de CEP, presença de campos) abortaria o backfill no meio. Reparo de dado não deve depender
  de validação de formulário.
- **Pula callbacks.** Evita disparar `after_create_commit :assign_order_number!` e qualquer efeito
  colateral futuro.
- **Precedente do projeto:** é exatamente o mecanismo usado para reverter o `Order#1` no incidente de
  2026-08-10 (`STRIPE_AUDIT.md §4.9`), pelo mesmo motivo — "é reparo de dado, não transição de
  negócio".
- **Ressalva registrada:** `update_columns` **não** atualiza `updated_at`. O reparo fica invisível na
  linha do registro. É desejável (não falseia a data da última mudança de negócio), mas significa que
  a trilha de auditoria é **este documento + o dump antes/depois**, não o banco. Se preferir rastro no
  banco, basta incluir `updated_at: Time.current` no hash — decisão sua.

### 4.6 Idempotência e reversibilidade

- **Idempotente por construção:** o script calcula os valores corretos e **compara com o que já está
  gravado**; se forem iguais, pula o registro sem escrever. Rodar duas vezes: a segunda não altera
  nada e reporta "0 atualizados". Rodar depois do fix de código também é seguro — pedidos novos já
  nascem certos e são pulados.
- **`DRY_RUN` por padrão:** sem `APPLY=1`, o script apenas **imprime** o que faria. A primeira execução
  em produção é obrigatoriamente dry-run.
- **Dump antes/depois:** o script imprime o estado dos 15 pedidos antes de qualquer escrita e depois
  dela. Essa saída vai colada neste documento — é a evidência de reversão.
- **Backup do banco antes:** `heroku pg:backups:capture --app trscrews-prod`, como manda o
  `UPGRADE_PLAN.md §6`.
- **Reversão pontual:** com o dump "antes" em mãos, reverter é um `update_columns` com os valores
  originais — os mesmos para todos: `subtotal: 0, total: <frete>` (e `shipping: 0` para 1, 34, 35).

### 4.7 Forma do script

Rake task nova em `lib/tasks/backfill_order_totals.rake` (arquivo novo — requer aprovação):

```ruby
# ESBOÇO — não implementado
namespace :orders do
  desc "Backfill subtotal/shipping/total. Dry-run por padrão; APPLY=1 para gravar."
  task backfill_totals: :environment do
    apply = ENV["APPLY"] == "1"
    changed = 0

    Order.includes(:order_items).order(:id).each do |o|
      subtotal = o.order_items.sum { |i| i.line_total.to_d }
      shipping = o.shipping_fee.to_d
      total    = subtotal + shipping

      if o.subtotal.to_d == subtotal && o.shipping.to_d == shipping && o.total.to_d == total
        puts "#{o.id} | OK, sem mudanca"
        next
      end

      puts "#{o.id} | #{o.subtotal}->#{subtotal} | #{o.shipping}->#{shipping} | #{o.total}->#{total}"
      o.update_columns(subtotal: subtotal, shipping: shipping, total: total) if apply
      changed += 1
    end

    puts apply ? "APLICADO em #{changed} pedidos" : "DRY-RUN: #{changed} seriam alterados"
  end
end
```

Rodar em produção: `heroku run rake orders:backfill_totals --app trscrews-prod` (dry-run) e depois
`heroku run rake orders:backfill_totals APPLY=1 --app trscrews-prod`.

---

## 5. Testes

Workflow do `CLAUDE.md`: **teste vermelho primeiro**, depois o fix.

### 5.1 Armadilha das fixtures — ler antes de escrever teste

`test/fixtures/orders.yml` declara `one` com `subtotal: 100.00 / total: 120.00`, mas
`test/fixtures/order_items.yml` dá a ela dois itens somando **52,00** (30,00 + 22,00). **A fixture é
internamente inconsistente.** Qualquer teste que trate as colunas da fixture como verdade vai
comparar contra números inventados. Os testes abaixo **não** dependem delas — constroem o cenário.

### 5.2 Teste (a) — RED antes do fix: `recalc_totals!` em pedido não persistido

`test/models/order_test.rb` (hoje só o esqueleto de 119 bytes).

- **Cenário:** `Order.new(...)` com atributos válidos, `add_item!(screws(:one), 2)` — sem salvar.
- **Ação:** `order.recalc_totals!`
- **Asserções:** `order.subtotal == unit_price * 2`; `order.total == subtotal + shipping`.
- **Estado esperado hoje:** **FALHA** (`subtotal` vem 0). É a prova direta do bug, no nível do método.

### 5.3 Teste (b) — regressão: `recalc_totals!` em pedido já persistido

- **Cenário:** pedido salvo com itens salvos.
- **Ação:** `recalc_totals!`
- **Asserção:** continua correto.
- **Objetivo:** garantir que o fix não quebra o caminho que hoje funciona (a soma em SQL acerta quando
  o registro existe). Passa antes e depois — é rede de segurança, não prova do fix.

### 5.4 Teste (c) — integração: `POST /orders` grava totais corretos

`test/controllers/orders_controller_test.rb` (hoje vazio).

- **Cenário:** sessão com carrinho preenchido (`session[:cart]`), estoque suficiente.
- **Ação:** `post orders_path` com params de endereço válidos.
- **Asserções:** o pedido criado tem `subtotal == Σ line_total` **no banco** (após `reload`), e
  `total == subtotal + shipping_fee`.
- **Estado esperado hoje:** **FALHA**. É o teste que prova o bug ponta a ponta, no fluxo real.
- **Ressalva:** exige montar sessão de carrinho — verificar como `cart_controller_test.rb` já faz isso
  antes de escrever, para reaproveitar o padrão.

### 5.5 Teste (d) — opcional: idempotência do backfill

- **Cenário:** pedido com colunas zeradas + itens corretos.
- **Ação:** rodar a task duas vezes.
- **Asserções:** 1ª corrige; 2ª não altera nada (`updated_at` e colunas intactos).

### 5.6 Baseline

Suíte hoje: **16 runs, 42 assertions, 0 failures, 0 errors, 0 skips**. Registrar antes e depois.

---

## 6. Ordem de execução + pontos de parada — ⚠️ SUPERADA pela §9

> Os passos 10 a 16 (rake task, dry-run, apply, idempotência) **não aconteceram** — foram
> substituídos por um único `Order.destroy_all`. A ordem realmente executada está na §9.

| # | Passo | Tipo (`CLAUDE.md`) | Aprovação? |
|---|---|---|---|
| 0 | Revisão e aprovação deste documento | — | **Sim** |
| 1 | Escrever testes (a), (b), (c) — **antes** do fix | testes (arquivos novos) | **Sim** |
| 2 | `bin/rails test` → registrar baseline **RED** em (a) e (c) | testes | Não |
| 3 | Aplicar o fix (a) em `order.rb:34` — uma linha | **maior** (modelo, toca cálculo de valores) | **Sim, explícita** |
| 4 | `bin/rails test` → tudo verde | testes | Não |
| 5 | Validar manualmente em dev: criar pedido pelo site, conferir colunas + telas `orders/show` e `admin` | validação local | Não |
| 6 | Commit do fix + testes | git | **Sim, por operação** |
| 7 | Deploy para Heroku | deploy produção | **Sim, explícita** |
| 8 | Confirmar em produção que **pedido novo** nasce certo (criar um pedido de teste e conferir) | validação | Não |
| 9 | `heroku pg:backups:capture --app trscrews-prod` | backup | **Sim** |
| 10 | Criar a rake task de backfill | **maior** (arquivo novo em `lib/tasks/`) | **Sim** |
| 11 | Rodar backfill em **dev** primeiro (dry-run e depois apply) | validação local | Não |
| 12 | Rodar backfill em produção em **DRY-RUN** — colar a saída aqui | leitura em produção | **Sim** |
| 13 | Conferir linha a linha contra a tabela §4.4 | revisão | **Sim — parada obrigatória** |
| 14 | Rodar backfill em produção com `APPLY=1` | **escrita em produção** | **Sim, explícita** |
| 15 | Re-rodar a query de diagnóstico → confirmar 15/15 corretos | leitura | Não |
| 16 | Re-rodar o backfill (deve reportar "0 alterados" — prova de idempotência) | leitura | Não |
| 17 | Commit da task + atualização deste doc com as saídas reais | git | **Sim, por operação** |
| 18 | Atualizar `TODO.md` (fechar o item) e `AUDIT.md` se aplicável | doc | Não |

**Pontos de parada obrigatórios (não prosseguir sem "ok"):** 0, 1, 3, 6, 7, 9, 10, 12, 13, 14, 17.

**Ordem inegociável: fix e deploy (passos 3-8) ANTES do backfill (10-16).** Se o backfill rodar
primeiro, os 15 pedidos ficam corretos e qualquer pedido novo criado no intervalo nasce errado — a
inconsistência volta, e pior, agora misturada.

A consolidação da §3 é **fase 3**, com plano próprio, depois de tudo isto estável.

---

## 7. Riscos e mitigação

| Risco | Probabilidade | Mitigação |
|---|---|---|
| **Backfill grava valor errado por bug no próprio script** | Baixa | Dry-run obrigatório (passo 12) + conferência linha a linha contra a tabela §4.4, que foi calculada de forma independente (passo 13). Nenhum `APPLY=1` sem os dois. |
| **Script roda parcialmente e aborta no meio** | Baixa | `update_columns` não valida, então a causa clássica de aborto some. Se abortar mesmo assim, o script é **idempotente**: re-rodar continua de onde parou, pulando os já corrigidos. |
| **Alguém cria um pedido durante o backfill** | Muito baixa | O fix já estará deployado (ordem do §6), então o pedido novo nasce correto e o script o pula. Volume real: 15 pedidos em 10 meses. |
| **`shipping_fee` estar errado em algum pedido** | Baixa | Verificado: bate com a recalculação em **15/15** (§4.2). É também o valor que o Stripe cobrou. |
| **Fix (a) mudar comportamento em pedido persistido** | Muito baixa | Coberto pelo teste (b) (§5.3). A soma em memória e a soma em SQL dão o mesmo resultado quando as linhas existem. |
| **Divergência entre colunas e o que o cliente já pagou** | **Nenhuma** | O Stripe fatura de `order_items` + `shipping_fee` (`checkout_sessions_controller.rb:27-52`). O backfill alinha as colunas **com** o que foi cobrado — reduz a divergência, não cria. |
| **Cliente notar o valor do pedido "mudando" na tela** | Baixa | É correção: a tela passa de R$ 20,00 para o valor real que ele pagou e que consta no e-mail dele. O incômodo é a divergência atual, não a correção. Nenhum dos 7 pedidos pagos é de cliente final — todos de dez/2025 em test mode. |
| **`updated_at` não muda, sem rastro no banco** | Certa (por escolha) | Trilha de auditoria = este documento + dumps antes/depois. Reversível para incluir `updated_at` se preferir (§4.5). |

### Rollback

**Do fix de código (passos 3-7):**
```bash
git revert <sha-do-fix>      # requer aprovação
# ou, se já deployado:
git push heroku <commit-anterior>:main --force   # requer aprovação explícita
```
Sem migration envolvida — nada de schema para reverter.

**Do backfill (passo 14):**

1. **Reversão pontual (preferida)** — com o dump "antes" (passo 12), os valores originais são
   uniformes e conhecidos: `subtotal: 0`, `total: <shipping_fee>`, e `shipping: 0` para os ids 1, 34 e
   35. Um `update_columns` por pedido restaura o estado exato. Mesmo mecanismo usado no incidente de
   2026-08-10 (`STRIPE_AUDIT.md §4.9`).
2. **Restauração de backup (último recurso)** —
   `heroku pg:backups:restore <backup-id> DATABASE_URL --app trscrews-prod --confirm trscrews-prod`,
   usando o backup do passo 9. **Descarta qualquer dado criado depois do backup** — só se a reversão
   pontual falhar.

**O que não precisa de rollback:** os testes (passo 1) e a rake task (passo 10) — código novo, sem
efeito até ser invocado.

---

## 8. Resumo da recomendação

1. **Fix:** opção **(a)** — trocar `sum(:line_total)` por `sum { |i| i.line_total.to_d }` em
   `order.rb:34`. Uma linha, corrige a causa, não toca no caminho de pagamento.
2. **Consolidação com `items_subtotal`/`total_amount`:** **fase separada**, depois do backfill. Direção
   sugerida: colunas viram fonte única nas views; os métodos viram verificação de consistência em teste.
3. **Backfill:** os **15** pedidos, uniformemente, com `shipping = shipping_fee`, via `update_columns`,
   em rake task idempotente com dry-run obrigatório.
4. **Ordem:** testes RED → fix → deploy → **confirmar pedido novo correto** → backup → backfill dry-run
   → conferência → apply.

---

## 9. Resultado da execução (2026-08-11)

### 9.1 O que mudou em relação ao plano

A recomendação da §2 (fix por soma em memória) e a da §3 (consolidação em fase separada) foram
**mantidas**. A da §4 (backfill) foi **substituída**: confirmou-se que os 15 pedidos eram sintéticos,
e dado de teste não se conserta — se apaga.

### 9.2 Fix de código — `b1f09ed`, release **v52**

```diff
-    self.subtotal = order_items.sum(:line_total)
+    # // Soma em memória: recalc_totals! roda antes do save, e um SUM() em SQL
+    # // sobre associação não persistida devolve 0. Mesmo critério de items_subtotal.
+    self.subtotal = order_items.sum { |i| i.line_total.to_d }
```

**Teste de regressão** em `test/controllers/orders_controller_test.rb` (arquivo estava vazio): monta o
carrinho via `POST /cart/add/:screw_id` e cria o pedido via `POST /orders` — o fluxo real do site.

Nasceu **RED**, no ponto exato previsto pela §5.2:

```
subtotal gravado deveria refletir a soma dos itens, nao 0.
Expected: 0.3e2
  Actual: 0.0
```

A primeira asserção (itens somam R$ 30,00) já passava — o defeito estava isolado na gravação, como o
diagnóstico afirmava.

Depois do fix: **17 runs, 47 assertions, 0 failures, 0 errors, 0 skips** (era 16/42).

**Verificação em produção pós-deploy** (objeto só em memória, nada gravado):

```
preco_unitario=19.9  qty=3
subtotal=59.7  shipping=20.0  total=79.7
persistido? false
```

R$ 59,70 onde antes viria `0.0`, e `total` deixou de ser só o frete.

### 9.3 Delete dos 15 pedidos (no lugar do backfill)

Backup **b005** capturado e confirmado `Completed` (53,21 KB) antes de qualquer escrita.
Comando: `Order.destroy_all` — **não** `delete_all`, porque a FK `order_items → orders` não tem
`on_delete: :cascade` (§1 da investigação de dependências); o `dependent: :destroy` do modelo é quem
apaga os itens.

| Modelo | Antes | Depois | |
|---|---|---|---|
| Order | 15 | **0** | apagado |
| OrderItem | 16 | **0** | apagado em cascata |
| Screw | 10 | **10** | intacto |
| User | 15 | **15** | intacto |
| StripeWebhookEvent | 2 | **2** | intacto — as 2 provas do incidente de 2026-08-10 preservadas |
| ShippingAddress | 10 | **10** | **não zerou — e está correto** |

**Por que `ShippingAddress` não zerou:** pertence a `User` (`shipping_address.rb:2`,
`belongs_to :user`), sem nenhuma FK para `orders`. `Order.destroy_all` não a alcança — exatamente o
que a investigação de dependências previu. Apagá-la é decisão separada.

### 9.4 Pendências deixadas de propósito

1. **Estoque não restaurado.** Os pedidos apagados haviam decrementado **31 unidades** em 7 parafusos
   (`orders_controller.rb:96`), e não existe lógica compensatória. Como os números de estoque também
   são de teste, ficou como está.
2. **Dados de teste remanescentes:** 15 users, 10 shipping_addresses, e os screws 34 ("Produto Teste")
   e 35 ("Vai seus bundão"). Limpeza de catálogo e usuários é outra tarefa.
3. **§3 (consolidação com `items_subtotal`/`total_amount`) segue pendente**, como planejado — fase
   separada, agora sem a dependência do backfill.

### 9.5 Nota metodológica

O bug sobreviveu ~11 meses porque as duas fontes de verdade **discordavam em silêncio**: os e-mails
usavam `items_subtotal` (soma em memória, correta) e as telas usavam a coluna `subtotal` (zerada).
Ninguém comparou. É o argumento central da §3 — quando houver duplicação, ela precisa falhar alto,
via teste, e não convergir para "uma das duas está certa".
