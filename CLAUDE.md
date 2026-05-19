# TR Screws — Guia de Trabalho para Claude Code

## Sobre o projeto

- **Nome:** TR Screws
- **Tipo:** E-commerce de parafusos aftermarket, com intenção de escalar para B2B futuramente
- **Stack atual:** Ruby 3.3.5, Rails 7.1.5.1, PostgreSQL, Importmap + Sprockets, Hotwire (Turbo + Stimulus), Bootstrap 5, Devise, Stripe (~> 11.0), Cloudinary, friendly_id, pagy
- **Upgrade planejado:** Rails 8.x (em etapa futura — não assumir features de Rails 8 antes do upgrade)
- **Hosting:** Heroku (produção ativa)
- **Storage de imagens:** Cloudinary via Active Storage
- **Idioma:** backend em inglês (código, classes, variáveis, comentários técnicos); frontend em português brasileiro para usuários finais

## Estado de produção

- A aplicação está **EM PRODUÇÃO** no Heroku, com usuários reais
- Existe branch `refactor/audit-fixes` para trabalho de melhoria estrutural — todo trabalho de refator passa por ela
- **NÃO** fazer deploy direto para Heroku sem aprovação explícita do usuário
- Auditoria técnica completa em `AUDIT.md` (raiz do projeto) — consultar antes de propor mudanças estruturais

## Regras de colaboração

**Mudanças "menores" — prosseguir sem aprovação prévia, mas sempre explicar o que foi feito:**
- Ajustes de CSS, HTML, copy de texto em views
- Refator local dentro de um único método/classe sem mudar interface
- Correção de typo
- Adição de comentário explicativo

**Mudanças "maiores" — SEMPRE apresentar 2-3 abordagens com trade-offs e ESPERAR aprovação explícita:**
- Adicionar/remover/atualizar gem no Gemfile
- Qualquer migration de banco
- Mudança em controller que afeta autorização ou autenticação
- Mudança em modelo que adiciona/remove validação ou callback
- Mudança em `config/` ou em qualquer initializer
- Refator que move código entre arquivos
- Criar service object novo
- Qualquer mudança que toque Stripe, Cloudinary, Devise, ou Active Storage

**Sempre, independente do tamanho da mudança:**
- **SEMPRE** rodar a suíte de testes (`bin/rails test`) após mudanças significativas e reportar o resultado.
- **SEMPRE** criar ou atualizar testes quando corrigir um bug — o teste deve falhar antes do fix e passar depois.
- Em caso de dúvida sobre intenção do usuário: **PERGUNTAR**, não assumir.
- Nunca fazer `git push` (especialmente para heroku) sem aprovação explícita.

## Padrões de código

### Backend em inglês (sempre):
- Nomes de classes, módulos, métodos, variáveis
- Nomes de tabelas e colunas em migrations
- Nomes de arquivos
- Comentários técnicos no código
- Mensagens de commit

### Português brasileiro (sempre):
- Texto em views (`.html.erb`) visto pelo usuário
- Strings em `config/locales/pt-BR.yml`
- Mensagens de erro mostradas ao usuário final
- Assunto e corpo de e-mails transacionais
- Texto em flash messages

### Outros padrões:
- Comentários: explicar o "porquê", não o "o quê". Código auto-explicativo é melhor que comentário redundante.
- Controllers magros, modelos com responsabilidade clara, lógica complexa em service objects (`app/services/`).
- Strong parameters sempre.
- N+1 queries: usar `includes` ou `preload` em loops que acessam associações.

## Segurança — não-negociáveis

- Nunca commitar credenciais. Usar ENV vars ou Rails credentials.
- Toda query com input de usuário: parâmetros nomeados ou `sanitize_sql_like`.
- Strong parameters em 100% dos controllers que recebem POST/PATCH/PUT.
- CSRF habilitado por padrão. Endpoint que desabilita (webhooks) deve usar verificação de assinatura como substituto.
- Antes de adicionar gem nova: justificar necessidade, verificar manutenção ativa (último release < 12 meses), checar vulnerabilidades conhecidas (bundler-audit).
- Webhooks externos: **SEMPRE** verificar assinatura + idempotência.
- LGPD: minimizar dados coletados; nunca logar dados pessoais (CPF, endereço completo, dados de cartão) em texto plano.

## Arquivos sensíveis — NUNCA modificar sem aprovação explícita

- `config/credentials.yml.enc`
- `config/master.key`
- `.env` e `.env.*` (exceto `.env.example`)
- `db/schema.rb` (só via migrations)
- `config/initializers/devise.rb` (mudanças de auth são críticas)
- `config/initializers/stripe.rb` (mudanças de pagamento são críticas)
- `config/storage.yml` (mudanças de Cloudinary afetam produção)
- `Procfile` (quando existir)

## Testes

- **Framework:** Minitest (já configurado em `test/`)
- **Nome do teste descreve COMPORTAMENTO em inglês:**
  - ✅ `test "creates order when stock is sufficient"`
  - ✅ `test "rejects checkout when address is invalid"`
  - ❌ `test "test_create"`
  - ❌ `test "should work"`
- **Stripe em testes:** usar webmock ou stripe-ruby-mock (decidir no primeiro teste de Stripe). **NUNCA** chamar API real.
- **Cloudinary em testes:** stub Active Storage uploads. **NUNCA** fazer upload real.
- **Após cada mudança significativa:** rodar `bin/rails test` e reportar no chat: total de testes, falhas, erros, tempo.
- **Bug fix workflow:** escrever teste que reproduz o bug **PRIMEIRO** (deve falhar), depois corrigir (deve passar).
- **Estado atual da cobertura:** 3 testes reais em 16 arquivos (ver `AUDIT.md` §3). Aumentar cobertura é prioridade.

## Workflow de mudança

1. Entender a mudança pedida — perguntar se ambíguo
2. Consultar `AUDIT.md` se a mudança tocar área auditada
3. Classificar como "menor" ou "maior" (ver Regras de colaboração)
4. Se maior: propor 2-3 abordagens com trade-offs e aguardar aprovação
5. Implementar
6. Escrever ou atualizar testes
7. Rodar `bin/rails test` e registrar resultado
8. Reportar no chat: o que mudou, por quê, resultado dos testes

## Quando em dúvida

- **Versão de gem:** rodar `bundle info <gem>` antes de propor mudança
- **Comportamento de código existente:** ler o arquivo inteiro antes de propor refator
- **Schema de banco:** ler `db/schema.rb` antes de propor migration
- **Estado de Stripe:** ler `stripe_webhooks_controller.rb` antes de propor mudança em pagamento
- **Intenção do usuário:** PERGUNTAR. Não assumir.
