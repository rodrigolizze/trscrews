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
- [ ] Configurar webhook endpoint no dashboard Stripe modo Live
      apontando para https://<domínio>/webhooks/stripe
- [ ] Confirmar que stripe initializer aceita ambas as chaves sem
      mudança de código

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
