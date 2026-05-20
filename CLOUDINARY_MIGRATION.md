# Migração: activestorage-cloudinary-service → Cloudinary SDK nativo

**Criado em:** 2026-05-19  
**Contexto:** A gem `activestorage-cloudinary-service` está abandonada (último commit: maio 2020, sem CI para nenhuma versão do Rails após 5.2). A migração para o Active Storage adapter nativo do SDK oficial `cloudinary` 2.x é **pré-requisito para a Etapa B** do UPGRADE_PLAN.md.

---

## 1. Estado Atual

### `config/storage.yml` (linhas 36–40)

```yaml
cloudinary:
  service: Cloudinary            # diz ao Active Storage qual classe usar
  cloud_name: <%= ENV.fetch("CLOUDINARY_CLOUD_NAME") %>
  api_key:    <%= ENV.fetch("CLOUDINARY_API_KEY") %>
  api_secret: <%= ENV.fetch("CLOUDINARY_API_SECRET") %>
```

### `config/environments/production.rb:40`

```ruby
config.active_storage.service = :cloudinary
```

### `config/environments/development.rb:37`

```ruby
config.active_storage.service = :local
```

### `Gemfile:78–80`

```ruby
gem "cloudinary"                              # Cloudinary Ruby SDK (v2.4.0)
gem "activestorage-cloudinary-service"        # plugs Cloudinary into Active Storage (v0.2.3)
```

### `app/models/screw.rb:4`

```ruby
has_many_attached :images
```

### `app/helpers/images_helper.rb` — detecção de serviço

```ruby
# images_helper.rb:7–13
def cdn_variant(source, **opts)
  blob = source.respond_to?(:blob) ? source.blob : source
  return unless blob.is_a?(ActiveStorage::Blob)

  if cloudinary_service?
    base = opts.slice(:resize_to_limit, :resize_to_fit, :resize_to_fill)
    blob.variant(base.merge(fetch_format: :auto, quality: "auto"))
  else
    blob   # local: devolve o original
  end
end

# images_helper.rb:23–26
def cloudinary_service?
  ActiveStorage::Blob.service.is_a?(ActiveStorage::Service::CloudinaryService)
rescue NameError
  false
end
```

**Nota importante:** O helper já usa `ActiveStorage::Service::CloudinaryService` — exatamente o nome de classe que o SDK oficial `cloudinary` 2.x registra. Isso sugere que foi escrito prevendo a migração.

### Uso de `.variant()` em views e helpers — mapa completo

| Arquivo | Linha(s) | Uso |
|---|---|---|
| `app/helpers/images_helper.rb` | 9 | `blob.variant(base.merge(fetch_format: :auto, quality: "auto"))` |
| `app/views/screws/show.html.erb` | 29 | `@screw.images.first.variant(resize_to_limit: [800, 800])` |
| `app/views/screws/show.html.erb` | 47, 90 | `img.variant(resize_to_limit: [1000, 1000])` (data-url) |
| `app/views/screws/show.html.erb` | 48, 91 | `img.variant(resize_to_limit: [200, 200])` (thumbnail) |
| `app/views/screws/show.html.erb` | 70 | `primary.variant(resize_to_limit: [1000, 1000])` |
| `app/views/screws/_card.html.erb` | 11 | `primary.variant(resize_to_limit: [600, 600])` |
| `app/views/orders/new.html.erb` | 26 | `screw.images.first.variant(resize_to_limit: [120,120])` |
| `app/views/orders/show.html.erb` | 94 | `item.screw.images.first.variant(resize_to_limit: [120, 120])` |
| `app/views/carts/show.html.erb` | 27 | `screw.images.first.variant(resize_to_limit: [120,120])` |
| `app/views/admin/screws/show.html.erb` | 27 | `img.variant(resize_to_limit: [320, 320])` |
| `app/views/admin/screws/index.html.erb` | 61 | `s.images.first.variant(resize_to_limit: [120,120])` |
| `app/views/admin/screws/_form.html.erb` | 81 | `att.variant(resize_to_limit: [200, 200])` |

**12 pontos de uso de `.variant()` em 8 arquivos.** Este é o aspecto mais crítico da migração — ver §5.

---

## 2. Como Funciona Hoje (Por Baixo dos Panos)

### O que `activestorage-cloudinary-service` faz

Ao subir o Rails, a gem registra `ActiveStorage::Service::CloudinaryService` no registry do Active Storage. O `storage.yml` com `service: Cloudinary` instrui o Active Storage a usar essa classe.

A gem lê `cloud_name`, `api_key`, `api_secret` diretamente do hash de opções do `storage.yml` (passado no constructor) para autenticar chamadas ao Cloudinary. Não há inicializador separado.

### Como as URLs são geradas

Quando `url_for(blob)` ou `image_tag blob.variant(...)` é chamado:
1. Active Storage chama `CloudinaryService#url(key, ...)` da gem
2. A gem constrói uma URL Cloudinary usando o `key` do blob como `public_id`
3. A URL tem formato: `https://res.cloudinary.com/<cloud_name>/image/upload/<key>`
4. Para variants, a gem converte os parâmetros Active Storage (`resize_to_limit` etc.) em transformações Cloudinary na URL

### Estrutura de keys/public_ids no Cloudinary

O Active Storage gera um `key` único por blob (string hexadecimal, ex: `abc123xyz...`). A `activestorage-cloudinary-service` usa esse key diretamente como `public_id` no Cloudinary, **sem prefixo de pasta**. Os blobs ficam no nível raiz da conta Cloudinary.

### Estado do banco (`active_storage_blobs`)

A tabela `active_storage_blobs` no schema tem:
- `key` — o public_id usado no Cloudinary (string única)
- `service_name` — atualmente `"cloudinary"` para todos os blobs de produção
- `filename`, `content_type`, `byte_size` — metadados locais

Não é possível contar os blobs sem executar uma query no banco. O que é certo: qualquer blob existente tem seu `key` como `public_id` no Cloudinary. **Preservar esses keys é crítico para não quebrar URLs existentes.**

---

## 3. Como Funciona o SDK Cloudinary Nativo

### Suporte nativo confirmado

**Sim.** O SDK `cloudinary` gem 2.x inclui um Active Storage adapter nativo. Nenhuma gem adicional é necessária.

- **Fonte oficial:** https://cloudinary.com/documentation/rails_activestorage
- **Repositório:** https://github.com/cloudinary/cloudinary_gem
- **Classe registrada:** `ActiveStorage::Service::CloudinaryService` — **mesmo nome da gem abandonada**

### Compatibilidade de versões

| cloudinary gem | Rails | Ruby |
|---|---|---|
| 2.x (atual: 2.4.5) | 6, 7, 8 ✅ | 3.x ✅ |
| 1.x | 5, 6, 7 | 2.x, 3.x |

O projeto usa `cloudinary` 2.4.0 e Ruby 3.3.5 — compatível.

### Configuração do `storage.yml` com o SDK nativo

A configuração mínima é:

```yaml
cloudinary:
  service: Cloudinary
```

As credenciais são lidas do `Cloudinary.config` global, que por sua vez lê automaticamente as variáveis de ambiente `CLOUDINARY_CLOUD_NAME`, `CLOUDINARY_API_KEY`, `CLOUDINARY_API_SECRET` (já configuradas no `.env` e no Heroku). **As credenciais não precisam estar no `storage.yml`.**

Opções adicionais que o SDK nativo aceita no `storage.yml` (passadas como parâmetros de upload):

```yaml
cloudinary:
  service: Cloudinary
  folder: app_name/uploads    # prefixo de pasta no Cloudinary (CUIDADO — ver §5)
  tags:
    - production
  secure: true
```

### Diferença crítica: `variant()` com o SDK nativo

⚠️ **Este é o ponto mais importante da migração.**

Com `activestorage-cloudinary-service`, chamar `.variant(resize_to_limit: [800, 800])` converte os parâmetros em transformações Cloudinary na URL — sem download ou reprocessamento. É puramente uma string de URL.

Com o SDK oficial `cloudinary` 2.x, o comportamento de `.variant()` pode diferir: em vez de usar Cloudinary URL transformations, pode tentar processar localmente via `image_processing` e re-enviar. Isto precisa ser **verificado e validado** durante o teste local (§6).

A Cloudinary recomenda usar `cloudinary_url(key, transformation_params)` ou `cl_image_tag` para transformações dinâmicas no lado cliente. O helper `cdn_variant` já existe no projeto como ponto de abstração — ele será o pivô da adaptação se necessário.

---

## 4. Estado Alvo

### `Gemfile` — before/after

**Antes:**
```ruby
gem "cloudinary"                              # Cloudinary Ruby SDK
gem "activestorage-cloudinary-service"        # plugs Cloudinary into Active Storage
```

**Depois:**
```ruby
gem "cloudinary"                              # Cloudinary Ruby SDK (inclui Active Storage nativo)
```

Apenas uma linha removida.

### `config/storage.yml` — before/after

**Antes:**
```yaml
cloudinary:
  service: Cloudinary
  cloud_name: <%= ENV.fetch("CLOUDINARY_CLOUD_NAME") %>
  api_key:    <%= ENV.fetch("CLOUDINARY_API_KEY") %>
  api_secret: <%= ENV.fetch("CLOUDINARY_API_SECRET") %>
```

**Depois:**
```yaml
cloudinary:
  service: Cloudinary
```

As credenciais são removidas do `storage.yml` porque o SDK nativo as lê automaticamente das variáveis de ambiente via `Cloudinary.config`. As ENV vars `CLOUDINARY_CLOUD_NAME`, `CLOUDINARY_API_KEY`, `CLOUDINARY_API_SECRET` já estão configuradas — nenhuma mudança de infraestrutura necessária.

### Outros arquivos que precisam mudar

Nenhum, a princípio. Se o comportamento de `.variant()` for diferente (ver §5), os 8 arquivos de view precisarão de ajuste — mas isso será determinado durante os testes (§6), não antes.

### Arquivos que NÃO precisam mudar (e por quê)

| Arquivo | Por quê não muda |
|---|---|
| `config/environments/production.rb` | `config.active_storage.service = :cloudinary` continua correto |
| `config/environments/development.rb` | Usa `:local` em dev — não afetado |
| `app/models/screw.rb` | `has_many_attached :images` é agnóstico ao serviço |
| `app/helpers/images_helper.rb` | Já usa `ActiveStorage::Service::CloudinaryService` — mesmo nome da classe oficial |
| `config/initializers/` | Não há initializer Cloudinary atualmente; o SDK lê de ENV automaticamente |
| `db/schema.rb` | Nenhuma migration necessária |
| `active_storage_blobs` (dados) | Os `key` existentes permanecem válidos como `public_id` no Cloudinary |

---

## 5. Riscos Específicos

### Risco 1 — URLs de imagens já uploadadas ⚠️ MÉDIO

**Pergunta:** URLs de imagens existentes continuarão funcionando?

**Análise:** Ambas as gems usam o `key` do blob como `public_id` no Cloudinary. Enquanto o `key` do blob não mudar no banco, a URL do Cloudinary continua válida — independente de qual gem gerou o upload.

**Condição para funcionar:** O SDK nativo **não pode** usar a opção `folder:` no `storage.yml`. Se `folder` for adicionado, as novas URLs teriam formato `folder/key` enquanto as antigas seriam apenas `key` — quebrando imagens existentes. **Não adicionar `folder:` ao storage.yml.**

**Garantia:** Testar o Fluxo 9a (imagem existente continua visível) durante a validação local antes de qualquer deploy.

### Risco 2 — Comportamento de `.variant()` ⚠️ ALTO (incerto)

**Pergunta:** Os 12 pontos de uso de `.variant(resize_to_limit: [...])` continuarão funcionando?

**Análise:** Este é o maior risco técnico. Com a gem abandonada, `.variant()` provavelmente gera URL transformations Cloudinary sem reprocessamento. Com o SDK nativo, o comportamento pode mudar:
- **Caso A (bom):** O SDK nativo converte `resize_to_limit` em transformações Cloudinary na URL → sem regressão visível
- **Caso B (problema):** O SDK nativo tenta processar localmente via `image_processing` e re-uploadar → cada chamada a `.variant()` cria um upload redundante no Cloudinary + lentidão

**Detecção:** Verificar durante o teste local (§6 cenário c) se, ao acessar uma view com `.variant()`, o log mostra um novo upload para Cloudinary ou apenas uma transformação de URL.

**Mitigação se Caso B ocorrer:** O helper `cdn_variant` em `images_helper.rb` já abstrai as chamadas de variant. Se o SDK nativo processar localmente, substituir as chamadas diretas de `.variant()` nos 8 arquivos de view por chamadas à `cdn_variant` (ou usar `cloudinary_url(blob.key, transformation_params)` para gerar URLs com transformação diretamente).

### Risco 3 — Conflito de classes durante a transição ⚠️ BAIXO (mas presente agora)

**Situação atual (antes da migração):** Ambas as gems estão no Gemfile e **ambas definem `ActiveStorage::Service::CloudinaryService`**. A que for carregada por último "vence". Este conflito está ativo hoje — é outro motivo para remover a gem abandonada.

**Após a migração:** Apenas uma definição existe. O risco desaparece.

### Risco 4 — Autenticação das credenciais ⚠️ BAIXO

**Situação:** O `storage.yml` atual passa `cloud_name`, `api_key`, `api_secret` como opções. O SDK nativo os lê via `Cloudinary.config` (das ENV vars). Ao remover as credenciais do `storage.yml`, o SDK deve continuar autenticando via ENV — mas isto precisa ser confirmado no primeiro teste de upload.

### Risco 5 — `service_name` em blobs antigos ⚠️ NENHUM

O campo `service_name` na tabela `active_storage_blobs` armazena o nome do serviço (`:cloudinary`). Após a migração, o serviço continua se chamando `:cloudinary` (mesmo nome no `storage.yml`). Blobs antigos continuam apontando para o serviço correto sem nenhuma migration de banco.

### O que pode quebrar silenciosamente (sem erro visível)

- **Variants processadas localmente em vez de no Cloudinary:** A imagem carrega, mas de forma ineficiente (cada request processa a imagem)
- **Variações com parâmetros Cloudinary específicos (`fetch_format: :auto, quality: "auto`)** sendo ignoradas silenciosamente — a imagem aparece mas sem otimização

---

## 6. Plano de Teste Local

### Setup

Em desenvolvimento, `config.active_storage.service = :local` — ou seja, uploads locais **não testam Cloudinary**. Para testar Cloudinary localmente, trocar temporariamente em `development.rb`:

```ruby
config.active_storage.service = :cloudinary
```

**Importante:** Usar uma pasta de teste no Cloudinary para não poluir os assets de produção. Adicionar ao `storage.yml` **apenas para o teste** e remover depois:

```yaml
cloudinary_test:
  service: Cloudinary
  folder: migration_test    # pasta isolada para os uploads de teste
  tags:
    - migration_test
```

E apontar o development.rb para `:cloudinary_test` durante a validação.

Após os testes, deletar todos os assets na pasta `migration_test` no Cloudinary dashboard.

### Cenários de Teste

**Cenário 0 — Confirmar que SDK nativo lê credenciais do ENV** ← FAZER PRIMEIRO

Antes de qualquer teste com imagens, abrir o console Rails (`bin/rails c`) e executar:

```ruby
Cloudinary.config.cloud_name   # deve retornar o nome da conta, não nil
Cloudinary.config.api_key      # deve retornar a chave, não nil
ActiveStorage::Blob.service.class
# deve retornar: ActiveStorage::Service::CloudinaryService
```

Se qualquer um retornar `nil` ou a classe não for `CloudinaryService`, parar aqui — o problema é de configuração, não de variants. Não prosseguir para os cenários a–e até resolver.

Causas comuns se falhar:
- ENV vars não carregadas (`.env` não sendo lido, `dotenv-rails` não ativo)
- `development.rb` ainda apontando para `:local` em vez de `:cloudinary` (ou `:cloudinary_test`)
- Conflito de carregamento entre as duas gems (remover `activestorage-cloudinary-service` do Gemfile antes de testar)

**a) Imagem existente continua visível**
- Acessar `/screws/:slug` de um screw com imagem já uploadada
- A imagem deve carregar normalmente — confirmar que a URL é do Cloudinary (`res.cloudinary.com`)
- Nenhum novo upload deve aparecer nos logs ou no Cloudinary dashboard

**b) Upload de imagem nova funciona**
- Em `/admin/screws/:id/edit`, fazer upload de uma nova imagem
- Confirmar que a imagem aparece no Cloudinary dashboard (pasta raiz ou `migration_test`)
- Confirmar que a nova imagem aparece na view do screw

**c) Variant é gerado corretamente** ← CENÁRIO CRÍTICO
- Acessar `/screws/:slug` e inspecionar as URLs das imagens no HTML
- Verificar se as URLs de thumbnail (`resize_to_limit: [200, 200]`) são Cloudinary transformations (ex: `c_limit,w_200,h_200` na URL) ou se são uploads separados
- Verificar nos logs se há chamadas a `Cloudinary::Uploader.upload` durante o carregamento da página — se houver, é o Caso B (problema)
- Verificar que a galeria de imagens em `show.html.erb` funciona com o carousel

**d) Delete de imagem funciona**
- Em `/admin/screws/:id/edit`, remover uma imagem
- Confirmar que o blob é removido do banco (`active_storage_blobs`)
- Confirmar que o asset é deletado do Cloudinary (verificar no dashboard)

**e) Re-upload (substituir imagem) funciona**
- Fazer upload de nova imagem para um screw que já tem imagem
- Confirmar que a imagem antiga é substituída ou adicionada (dependendo da lógica de negócio)
- Confirmar que a URL da nova imagem é válida

---

## 7. Plano de Teste no Heroku Após Deploy

### Mesmos 5 cenários, no Heroku

Executar os cenários a–e no app do Heroku (`trscrews-prod.herokuapp.com`) com o Stripe em modo test.

### Verificação nos logs do Heroku

```bash
heroku logs --tail --app trscrews-prod
```

Ao acessar uma view com imagens, verificar:
- Ausência de erros `ActiveStorage::ServiceNotFound` ou `NameError: CloudinaryService`
- Ausência de uploads inesperados para Cloudinary ao simplesmente carregar uma view
- Presença de respostas HTTP 200 para as URLs das imagens

### Verificação de serviço correto

No console do Heroku:
```bash
heroku run rails runner "puts ActiveStorage::Blob.service.class" --app trscrews-prod
```

Deve retornar `ActiveStorage::Service::CloudinaryService`.

### Confirmação de URLs antigas acessíveis

Para cada screw com imagem existente no banco, a URL gerada deve continuar sendo válida no Cloudinary. A URL deve ter formato:
```
https://res.cloudinary.com/<cloud_name>/image/upload/<key>
```
onde `<key>` é o mesmo valor em `active_storage_blobs.key`.

---

## 8. Rollback

### Se algo quebrar após o deploy

**Reverter código:**
```bash
# Requer aprovação explícita
git push heroku <branch-anterior>:main --force
```

**Reverter banco (se houve migration):** Esta migração não tem migrations de banco — apenas mudanças em Gemfile e storage.yml. O rollback de código é suficiente.

**Restaurar banco do backup (precaução):**
```bash
heroku pg:backups:restore <backup-id> DATABASE_URL --app trscrews-prod --confirm trscrews-prod
```

### O que NÃO é revertível

**Uploads feitos durante o período com o novo SDK:** Se imagens foram uploadadas depois do deploy, elas usam o SDK nativo. Ao reverter para a gem antiga, esses blobs ainda existem no Cloudinary com os mesmos keys — continuarão acessíveis. O rollback não apaga assets do Cloudinary.

**Imagens deletadas durante o teste:** Se um delete foi executado com o novo SDK, o asset é removido do Cloudinary. Não há rollback para isso — é uma ação irreversível no Cloudinary.

---

## 9. Estimativa de Tempo

| Fase | Tarefas | Estimativa |
|---|---|---|
| **Implementação** | Remover gem do Gemfile, `bundle install`, simplificar `storage.yml`, rodar `bin/rails server` para confirmar boot | 30–45 min |
| **Teste local** | Configurar Cloudinary de teste, executar os 5 cenários, investigar comportamento de `.variant()` | 1–2h |
| **Ajuste de views** (se Caso B for confirmado) | Atualizar 8 arquivos de view para usar `cdn_variant` ou `cloudinary_url` | 1–2h adicionais |
| **Deploy + teste Heroku** | Backup, deploy, executar 5 cenários no Heroku, verificar logs | 30–45 min |
| **Total sem ajuste de views** | | **~2–3h** |
| **Total com ajuste de views** | | **~4–5h** |

O tempo do "ajuste de views" depende do resultado do cenário c (test do variant). Se o SDK nativo se comportar corretamente com `.variant()`, essa fase não existe.
