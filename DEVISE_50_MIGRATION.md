# Etapa F — Devise 4.9.4 → 5.0.4: investigação

**Elaborado em:** 2026-08-14 · **Estado:** investigação apenas — **nenhum arquivo do projeto foi
modificado**, nenhum `bundle update` executado.
**Base:** Rails 8.1.3.1 · Ruby 3.3.5 · Devise 4.9.4 em produção (Heroku v56, `88755c7`).

> ## ⚠️ Achado que muda a urgência desta etapa
>
> O `UPGRADE_PLAN.md` §8 classifica a Etapa F como urgência **Média**, justificada por prazo: as 4
> deprecations do Devise viram erro no Rails 8.2. **Essa não é mais a razão principal.**
>
> O Devise **4.9.4 carrega duas CVEs sem correção disponível na série 4**, ambas divulgadas depois do
> último release da série (4.9.4 é de **2024-04-10**; a série 4 terminou ali — não existe 4.9.5):
>
> | CVE | Severidade | Faixa vulnerável (GitHub Advisory DB) | Corrigida em | Nos atinge? |
> |---|---|---|---|---|
> | **CVE-2026-32700** — race condition no `reconfirmable` permite confirmar e-mail de terceiro | Média | `<= 5.0.2` | **5.0.3** | **SIM — confirmado no código** |
> | **CVE-2026-40295** — open redirect no `FailureApp` via `Referer` não validado em requisição não-GET | Média | `<= 5.0.3` | **5.0.4** | **Parcialmente — caminho existe, exploração estreita** |
>
> As faixas `<= 5.0.2` e `<= 5.0.3` incluem toda a série 4 pela ordenação semver, e o mantenedor não
> fez backport. A confirmação da primeira **não é dedução a partir da faixa** — está verificada linha
> a linha contra o código instalado (§3.13).
>
> **Consequência:** a Etapa F deixa de ser "manutenção com prazo" e passa a ser **a última dívida de
> segurança aberta do projeto**, agora que a cadeia do Rails fechou. Isso a coloca acima da F na ordem
> sugerida do §8 do `UPGRADE_PLAN` — recomendação registrada em §8 deste documento.

---

## 1. Versão alvo e compatibilidade

### Versão alvo: **Devise 5.0.4**

Série 5 completa, conforme rubygems.org (consultado em 2026-08-14):

| Versão | Data | Observação |
|---|---|---|
| 5.0.0.rc | 2025-12-31 | Todas as breaking changes da série entraram aqui |
| 5.0.0 | 2026-01-23 | CHANGELOG: *"no changes"* — promoção do rc |
| 5.0.1 | 2026-02-13 | bug fix de tradução (alemão) |
| 5.0.2 | 2026-02-18 | enhancements (`sign_in_after_change_password` por escopo) |
| 5.0.3 | 2026-03-16 | **security** — CVE-2026-32700 |
| **5.0.4** | **2026-05-08** | **security** — CVE-2026-40295 · **é a mais recente** |

A 5.0.4 tem **3 meses** de estrada (maio→agosto de 2026) e é a única da série sem CVE conhecida.

### Requisito de Rails

`railties >= 7.0` — **sem teto**. Confirmado direto no metadado da gem publicada:

```
$ curl -s https://rubygems.org/api/v2/rubygems/devise/versions/5.0.4.json
--- runtime deps ---
bcrypt       ~> 3.0
orm_adapter  ~> 0.1
railties     >= 7.0
responders   >= 0
warden       ~> 1.2.3
```

**Rails 8.1.3.1 satisfaz.** Além disso, o suporte a Rails 8 é uma *enhancement* declarada do 5.0.0.rc
("Add Rails 8 support"), não uma compatibilidade acidental — o lazy route loading do Rails 8.0 foi
tratado explicitamente (§4).

Não há teto em `railties`, o que significa que o Devise 5.0.4 não impede um futuro Rails 8.2. Mas
atenção: **isso não é o mesmo que "pronto para o 8.2"** — o que resolve o 8.2 é a correção das
deprecations (§5), que já está feita no código do 5.x.

### Requisito de Ruby

`required_ruby_version = >= 2.7.0`. Temos **3.3.5** — folga larga. O CHANGELOG do 5.0.0.rc ainda
registra "Add Ruby 3.4 and 4.0 support", então 3.3.5 está dentro da faixa ativamente testada.

### Compatibilidade confirmada — resumo

| Requisito | Exigido pelo 5.0.4 | Temos | Status |
|---|---|---|---|
| Ruby | `>= 2.7.0` | 3.3.5 | ✅ |
| Rails (railties) | `>= 7.0`, sem teto | 8.1.3.1 | ✅ |
| bcrypt | `~> 3.0` | 3.1.20 | ✅ |
| orm_adapter | `~> 0.1` | 0.5.0 | ✅ |
| responders | qualquer | 3.2.0 | ✅ |
| warden | `~> 1.2.3` | 1.2.9 | ✅ |

---

## 2. Nosso uso de Devise — mapa completo

### 2.1 — Model

Um único model: **`User`** (`app/models/user.rb`). Nenhum outro escopo Devise no projeto.

```ruby
devise :database_authenticatable, :registerable,
       :recoverable, :rememberable, :validatable, :confirmable
```

Confirmado em runtime (a ordem difere da declaração porque o Devise reordena internamente):

```
User.devise_modules =>
  [:database_authenticatable, :rememberable, :recoverable,
   :registerable, :validatable, :confirmable]
```

**Seis módulos.** Não usamos `:lockable`, `:timeoutable`, `:trackable` nem `:omniauthable` — os quatro
seguem comentados na linha de documentação do model.

Colunas correspondentes em `db/schema.rb` (tabela `users`):

```ruby
t.string   "email",                  default: "", null: false   # database_authenticatable/validatable
t.string   "encrypted_password",     default: "", null: false   # database_authenticatable
t.string   "reset_password_token"                               # recoverable (índice único)
t.datetime "reset_password_sent_at"                             # recoverable
t.datetime "remember_created_at"                                # rememberable
t.string   "name"                                               # nosso, não-Devise
t.string   "confirmation_token"                                 # confirmable (índice único)
t.datetime "confirmed_at"                                       # confirmable
t.datetime "confirmation_sent_at"                               # confirmable
t.string   "unconfirmed_email"                                  # confirmable + reconfirmable
```

A coluna **`unconfirmed_email` existe e está em uso** — é o que torna a CVE-2026-32700 relevante para
nós, e não teórica (§3.13).

Ausentes, coerentes com os módulos não usados: `failed_attempts`/`locked_at` (lockable),
`sign_in_count`/`current_sign_in_at`/`last_sign_in_ip` (trackable — as linhas estão comentadas na
migration original `20251013163316_devise_create_users.rb`).

### 2.2 — `config/initializers/devise.rb`

313 linhas, quase todas comentadas (é o template do gerador). **As linhas efetivamente ativas são 15:**

| Linha | Config | Valor |
|---|---|---|
| 27 | `config.mailer_sender` | `'TR AutoParts <trautoparts.suporte@gmail.com>'` |
| 39 | `require` | `'devise/orm/active_record'` |
| 61 | `config.case_insensitive_keys` | `[:email]` |
| 66 | `config.strip_whitespace_keys` | `[:email]` |
| 100 | `config.skip_session_storage` | `[:http_auth]` |
| 126 | `config.stretches` | `Rails.env.test? ? 1 : 12` |
| 160 | `config.reconfirmable` | `true` |
| 170 | `config.expire_all_remember_me_on_sign_out` | `true` |
| 181 | `config.password_length` | `6..128` |
| 186 | `config.email_regexp` | `/\A[^@\s]+@[^@\s]+\z/` |
| 227 | `config.reset_password_within` | `6.hours` |
| 269 | `config.sign_out_via` | `:delete` |
| 305 | `config.responder.error_status` | `:unprocessable_entity` |
| 306 | `config.responder.redirect_status` | `:see_other` |

**`config.secret_key` está COMENTADO** (linha 17). Isso importa muito para o breaking change nº 9 —
ver §3.9.

Todos os 14 nomes de config acima existem inalterados no Devise 5.0.4. Nenhum foi renomeado ou
removido pela série 5 (verificado contra o CHANGELOG completo do 5.0.0.rc, §3).

### 2.3 — `app/views/devise/*` — views customizadas

**17 arquivos.** O projeto tem cópia local de praticamente toda a superfície de views do Devise:

```
app/views/devise/confirmations/new.html.erb
app/views/devise/mailer/confirmation_instructions.html.erb
app/views/devise/mailer/confirmation_instructions.text.erb
app/views/devise/mailer/email_changed.html.erb
app/views/devise/mailer/password_change.html.erb
app/views/devise/mailer/reset_password_instructions.html.erb
app/views/devise/mailer/unlock_instructions.html.erb
app/views/devise/passwords/edit.html.erb
app/views/devise/passwords/new.html.erb
app/views/devise/registrations/edit.html.erb
app/views/devise/registrations/new.html.erb
app/views/devise/registrations/new_old.html.erb        ← órfã (sufixo _old)
app/views/devise/sessions/new.html.erb
app/views/devise/sessions/new_old.html.erb             ← órfã (sufixo _old)
app/views/devise/shared/_error_messages.html.erb
app/views/devise/shared/_links.html.erb
app/views/devise/unlocks/new.html.erb
```

**Consequência central:** os três breaking changes de *template* do 5.0 (`<br>` → `<p>`, mudança de
label do botão de reset de senha, `[data-turbo-cache=false]` → `[data-turbo-temporary]`) **não nos
alcançam**, porque as views da gem não são renderizadas — as nossas vencem. Detalhe em §3.10 a §3.12.

Duas observações de higiene, **fora do escopo desta etapa**: `new_old.html.erb` (×2) são órfãs, e
`unlocks/new.html.erb` corresponde a um módulo que não usamos (`:lockable`). Não remover na F —
limpeza de views é assunto próprio e misturar aumenta o ruído do diff de uma etapa de autenticação.

### 2.4 — Controllers customizados

**Um:** `app/controllers/users/registrations_controller.rb` (14 linhas).

```ruby
class Users::RegistrationsController < Devise::RegistrationsController
  protected

  def after_sign_up_path_for(resource)
    new_shipping_address_path(return_to: "checkout")
  end

  def after_inactive_sign_up_path_for(resource)
    root_path
  end
end
```

Sobrescreve apenas dois hooks de path, ambos presentes e inalterados no 5.0.4. **Nenhum override de
`create`, `new`, `update` ou `destroy`** — não há risco de divergência com o corpo dos métodos da gem.

> **Nota sobre o 5.0.2 (não é breaking change, mas é armadilha conhecida):** o CHANGELOG registra que
> a partir do 5.0.2 o `RegistrationsController` passou a depender de uma config do módulo
> `:registerable`, e que apps que subclassificavam o controller **sem declarar `:registerable` no
> model** quebraram. **Nós declaramos `:registerable`** (§2.1) — não nos atinge.

Não há `Users::SessionsController`, `ConfirmationsController` nem `PasswordsController` customizados.

### 2.5 — `config/routes.rb`

Uma única linha de Devise, a **linha 2**:

```ruby
devise_for :users, controllers: { registrations: "users/registrations" }
```

Sem `path:`, sem `path_names:`, sem `skip:`, sem bloco `devise_scope`, sem `as:`. É a forma mais
simples possível — o que reduz bastante a superfície de qualquer mudança em geração de rotas.

Rotas efetivamente desenhadas pelos nossos 6 módulos: `session`, `password`, `confirmation`,
`registration`. **Não** `unlock` (sem `:lockable`) — o `devise_unlock` da gem é guardado por
`if mapping.to.unlock_strategy_enabled?(:email)`.

Nenhuma outra rota do projeto referencia Devise. `authenticate_user!` é aplicado por `before_action`
nos controllers, não por constraint de rota.

### 2.6 — Onde o app usa helpers de Devise (grep completo)

`grep -rn "current_user\|user_signed_in?\|authenticate_user!\|sign_in\|sign_out\|devise_parameter_sanitizer\|devise_controller?\|Devise\.\|Devise::" app/ lib/ config/ test/ db/`

**Controllers (5 arquivos):**

| Arquivo:linha | Uso |
|---|---|
| `application_controller.rb:10` | `before_action :configure_permitted_parameters, if: :devise_controller?` |
| `application_controller.rb:42` | `defined?(user_signed_in?) && user_signed_in?` |
| `application_controller.rb:45` | `respond_to?(:devise_controller?) && devise_controller?` |
| `application_controller.rb:48` | `current_user.shipping_addresses.none?` |
| `application_controller.rb:65,67` | `devise_parameter_sanitizer.permit(:sign_up / :account_update, keys: [:name])` |
| `carts_controller.rb:15,16` | `user_signed_in?`, `current_user.shipping_addresses` |
| `checkout_sessions_controller.rb:108` | `user_signed_in?`, `current_user.id` |
| `orders_controller.rb:3` | **`before_action :authenticate_user!, only: [:show]`** |
| `orders_controller.rb:32,34,35,38,71,72,156,160,186,187,226,231,241,246` | `user_signed_in?` / `current_user` |
| `shipping_addresses_controller.rb:3` | **`before_action :authenticate_user!`** (todas as ações) |
| `shipping_addresses_controller.rb:9,15,20,74` | `current_user.shipping_addresses` |
| `users/registrations_controller.rb:1` | `< Devise::RegistrationsController` |

**Views (4 arquivos):**

| Arquivo:linha | Uso |
|---|---|
| `shared/_navbar.html.erb:35,36` | `user_signed_in?`, `current_user.name / .email` |
| `shared/_navbar.html.erb:48` | `button_to "Sair", destroy_user_session_path, method: :delete` |
| `orders/new.html.erb:65,82` | `user_signed_in?`, `current_user.name` |
| `orders/thank_you.html.erb:79` | `user_signed_in?` |

**Testes (2 arquivos):**

| Arquivo:linha | Uso |
|---|---|
| `orders_thank_you_test.rb:12` | `include Devise::Test::ControllerHelpers` |
| `fixtures/users.yml:6,12` | `Devise::Encryptor.digest(User, 'password123')` |

**Leituras que importam para o risco da etapa:**

1. **`sign_in` e `sign_out` não aparecem em lugar nenhum do código de app nem de teste.** Os únicos
   caminhos de sessão são as rotas do próprio Devise. Três dos breaking changes do 5.0 são sobre
   assinaturas de `sign_in` (§3.3, §3.5) — **superfície zero**.
2. **`authenticate_user!` em exatamente 2 controllers**: `orders#show` e todo o
   `shipping_addresses`. Esses são os pontos que exercitam o `FailureApp` — relevante para a
   CVE-2026-40295 (§3.14).
3. **O padrão `defined?(user_signed_in?) &&` aparece 8 vezes.** É defensivo além do necessário (o
   helper é sempre definido quando o Devise está carregado), mas é inofensivo e não muda no 5.0.
4. **`Devise::Encryptor.digest`** nas fixtures é API interna. Verificado: existe inalterada no 5.0.4.

---

## 3. Breaking changes do Devise 5.0 — um a um, contra o nosso código

Fonte: `CHANGELOG.md` do branch `main` do heartcombo/devise, seção **5.0.0.rc — 2025-12-31**
(as versões 5.0.0 a 5.0.4 não adicionaram nenhuma breaking change; 5.0.0 é literalmente *"no changes"*).

> **Sobre a instrução de reverificar:** o `RAILS_80_MIGRATION.md` §4.1 concluiu que nenhum breaking
> change nos atinge. **Reverificado item a item contra o CHANGELOG real — a conclusão se sustenta**,
> mas com **duas correções e uma nuance** que a análise da D1 não tinha:
> - a D1 listou **4** breaking changes; o CHANGELOG lista **12**;
> - a D1 tratou o `secret_key` como "já está comentado, logo ok" — a conclusão está certa, mas a
>   justificativa estava incompleta e só se fecha com uma verificação de produção (§3.9);
> - a D1 não menciona a mudança do partial `_error_messages` (§3.12).

### 3.1 — Drop de suporte a Ruby < 2.7

**Nos atinge?** ❌ Não. Ruby 3.3.5 (`.ruby-version` e Gemfile).

### 3.2 — Drop de suporte a Rails < 7.0

**Nos atinge?** ❌ Não. Rails 8.1.3.1.

### 3.3 — Remoção da opção `:bypass` do helper `sign_in` (usar `bypass_sign_in`)

```
$ grep -rn "bypass_sign_in\|bypass:" app/ lib/ test/ config/
nenhuma ocorrencia
```

**Nos atinge?** ❌ Não. Não chamamos `sign_in` em lugar nenhum (§2.6).

### 3.4 — Remoção do helper `devise_error_messages!`

```
$ grep -rn "devise_error_messages" app/ lib/
nenhuma ocorrencia
```

**Nos atinge?** ❌ Não. Nosso `app/views/devise/shared/_error_messages.html.erb` já é a forma nova
(partial dedicado), que é exatamente o substituto recomendado pelo CHANGELOG.

### 3.5 — Remoção do 2º argumento posicional `scope` em `sign_in(resource, :admin)` nos test helpers

**Nos atinge?** ❌ Não. Zero chamadas a `sign_in` na suíte (§2.6). **Relevante para o plano de
execução:** quando escrevermos o primeiro teste que autentica (passo 9 do §7), usar já a forma nova
`sign_in(user, scope: :user)` — ou simplesmente `sign_in(user)`, que é o nosso caso, já que só há um
escopo.

### 3.6 — Remoção de `Devise::TestHelpers` (usar `Devise::Test::ControllerHelpers`)

```
$ grep -rn "Devise::TestHelpers" test/
nenhuma ocorrencia

$ grep -rn "Devise::Test::ControllerHelpers" test/
test/controllers/orders_thank_you_test.rb:12
```

**Nos atinge?** ❌ Não — **já usamos a forma nova**, a que sobrevive no 5.0.

### 3.7 — Remoção de `Devise::Models::Authenticatable::BLACKLIST_FOR_SERIALIZATION`

```
$ grep -rn "BLACKLIST_FOR_SERIALIZATION" app/ lib/ test/ config/
nenhuma ocorrencia
```

**Nos atinge?** ❌ Não.

### 3.8 — Remoção de `Devise.activerecord51?`

```
$ grep -rn "activerecord51?" app/ lib/ test/ config/
nenhuma ocorrencia
```

**Nos atinge?** ❌ Não. (É API interna da gem; nunca teríamos motivo para chamar.)

### 3.9 — Remoção do `SecretKeyFinder`: `Devise.secret_key` passa a vir sempre de `application.secret_key_base`

**Este é o único breaking change do 5.0 com potencial de dano real neste projeto**, e o único que
não se resolve com `grep`. O CHANGELOG é explícito:

> Devise previously used the following order to find a secret key:
> `app.credentials.secret_key_base > app.secrets.secret_key_base > application.config.secret_key_base > application.secret_key_base`
> Now, it always uses `application.secret_key_base`. **Make sure you're using the same secret key
> after the upgrade; otherwise, previously generated tokens for `recoverable`, `lockable`, and
> `confirmable` will be invalid.**

Usamos **`recoverable` e `confirmable`** — dois dos três módulos citados. Se a chave mudar, todo token
de reset de senha e de confirmação pendente no banco vira inválido.

**Por que a cadeia antiga e a nova poderiam divergir:** a antiga começa por
`credentials.secret_key_base`; a nova (`Rails.application.secret_key_base`, no Rails 8.1) resolve, em
ambiente não-local, `ENV["SECRET_KEY_BASE"] || credentials.secret_key_base`. **Se produção tivesse um
`SECRET_KEY_BASE` diferente do valor dentro das credentials, as duas chaves seriam diferentes** e o
upgrade invalidaria os tokens silenciosamente.

**Verificado nas duas pontas, sem expor nenhum segredo** (comparação por digest SHA-256 truncado):

*Development:*
```
credentials.secret_key_base present?  true
ENV[SECRET_KEY_BASE] present?         false
credentials digest:                   c31b4c0182b9
application.secret_key_base digest:   c31b4c0182b9
Devise.secret_key digest (4.9.4 hoje): c31b4c0182b9
Devise.secret_key == application.secret_key_base?  true
```

*Produção (Heroku):*
```
$ heroku config --app trscrews-prod   (apenas os NOMES das vars)
ADMIN_PASSWORD  ADMIN_USER  APP_HOST
CLOUDINARY_API_KEY  CLOUDINARY_API_SECRET  CLOUDINARY_CLOUD_NAME  CLOUDINARY_URL
DATABASE_URL  RAILS_MASTER_KEY
SMTP_ADDRESS  SMTP_DOMAIN  SMTP_PASSWORD  SMTP_PORT  SMTP_USERNAME
STRIPE_SECRET_KEY  STRIPE_SIGNING_SECRET

$ heroku config:get SECRET_KEY_BASE --app trscrews-prod | sha256sum
e3b0c44298fc...            ← digest da string VAZIA (conferido: printf '' | sha256sum)
```

**`SECRET_KEY_BASE` não existe nas config vars de produção.** O que existe é `RAILS_MASTER_KEY`, ou
seja, **produção lê `secret_key_base` das credentials** — a mesma origem que o Devise 4.9.4 já usa
como primeira opção da cadeia antiga.

**Nos atinge?** ❌ **Não.** As duas cadeias convergem para o mesmo valor, em dev e em produção.
`config.secret_key` está comentado no initializer, então não há override concorrente. **Nenhum token
de `recoverable` ou `confirmable` será invalidado pelo upgrade.**

> **Condição que precisa ser preservada:** se em algum momento futuro alguém setar `SECRET_KEY_BASE`
> no Heroku com valor diferente do das credentials, isso **por si só** já invalidaria tokens sob o
> Devise 5 — independente desta etapa. Registrar como restrição operacional, não como risco da F.

**Verificação empírica do passo 12 — cortada por decisão (2026-08-18).** O plano previa gerar um token
de reset ainda no 4.9.4, deixá-lo **sem uso**, e conferir depois do upgrade que continuava válido. Esse
token **queimou**: o trabalho perdido no travamento gerou um novo reset para `confirmado@dev.local` já
no 5.0.4 (`reset_password_sent_at = 2026-08-14 17:12 UTC`, contra o `bundle update devise` das 16:37
UTC), e `recoverable` guarda **um único token por usuário** — o anterior, se existiu, foi sobrescrito.

**Não voltamos ao 4.9.4 para refazê-lo.** A conclusão desta seção não depende desse teste: ela está
provada por **digest SHA-256** das duas cadeias, que convergem para o mesmo `secret_key_base` tanto em
dev quanto em produção. Um token sobrevivente seria *consequência observável* dessa igualdade, não
prova independente dela — refazer o baseline custaria um downgrade/upgrade completo para confirmar algo
que o digest já fecha. Registrado como **escopo cortado com justificativa**, não como verificação
pendente.

### 3.10 — Label do botão de reset de senha: `Send me reset password instructions` → `Send me password reset instructions`

**Nos atinge?** ❌ Não, por dois motivos independentes: (a) temos view própria
(`app/views/devise/passwords/new.html.erb`); (b) o texto do projeto é pt-BR e vem do nosso
`config/locales/devise.pt-BR.yml`, não da string em inglês da gem.

### 3.11 — Tags `<br>` separando elementos de formulário passam a `<p>` envolvendo

**Nos atinge?** ❌ Não. Mudança nos templates da gem; renderizamos os nossos (§2.3).

### 3.12 — `[data-turbo-cache=false]` → `[data-turbo-temporary]` no partial `devise/shared/error_messages`

*(Este item não constava da análise da D1.)*

```
$ grep -rn "data-turbo-cache\|data-turbo-temporary" app/
app/views/devise/shared/_error_messages.html.erb:2:  <div id="error_explanation" data-turbo-cache="false">
```

**Nos atinge?** ❌ Não, no sentido de quebra: o arquivo é **nosso**, o Devise não o substitui, e o
comportamento hoje é o que sempre foi. O CHANGELOG só alerta quem usa o template da gem **com Turbo
antigo** — o caso inverso do nosso.

**Nuance registrada:** nossa cópia usa o atributo **deprecado pelo Turbo desde a v7.3.0 (mar/2023)**, e
rodamos `turbo-rails` 2.0.16 (Turbo 8). Não quebra nada hoje, mas é resíduo. **Não corrigir na F** —
é mudança de view sem relação com autenticação; vai para o `TODO.md` como higiene.

### 3.13 — CVE-2026-32700 (corrigida no 5.0.3) — race condition no `reconfirmable`

Não é breaking change, mas é a razão principal desta etapa e precisa da mesma verificação.

**Faixa vulnerável no GitHub Advisory DB (GHSA-57hq-95w6-v4fc):** `<= 5.0.2`, corrigida em `5.0.3`.
Pela ordenação semver, a faixa **inclui 4.9.4**. O advisory declara: *"affects any Devise application
using the `reconfirmable` option (the default when using Confirmable with email changes)"*.

**Nossa configuração:** `:confirmable` ativo (§2.1) + `config.reconfirmable = true`
(`devise.rb:160`, confirmado em runtime: `Devise.reconfirmable => true`) + coluna `unconfirmed_email`
presente no schema. **Os três pré-requisitos estão satisfeitos.**

**Confirmação no código, não por dedução da faixa** — diff do arquivo instalado contra a tag v5.0.4:

```diff
--- devise-4.9.4/lib/devise/models/confirmable.rb
+++ v5.0.4/lib/devise/models/confirmable.rb
@@ -258,9 +258,11 @@
         def postpone_email_change_until_confirmation_and_regenerate_confirmation_token
           @reconfirmation_required = true
+          # Force unconfirmed_email to be updated, even if the value hasn't changed, to prevent a
+          # race condition which could allow an attacker to confirm an email they don't own. See #5783.
+          devise_unconfirmed_email_will_change!
           self.unconfirmed_email = self.email
```

**A correção não existe no 4.9.4 que temos instalado.** O método vulnerável é o callback
`before_update :postpone_email_change_until_confirmation_and_regenerate_confirmation_token`
(`confirmable.rb:58`), disparado em toda troca de e-mail via `/users/edit`.

**Nos atinge?** ✅ **SIM.** Sem correção disponível na série 4 — **só sai subindo para ≥ 5.0.3**.

**Exploração exige** requisições concorrentes de troca de e-mail; o resultado é o e-mail da vítima
ficando confirmado na conta do atacante. Severidade "Média" no advisory. Hoje o risco prático é baixo
(produção sem usuário real), mas isso é circunstância temporária, não mitigação.

### 3.14 — CVE-2026-40295 (corrigida no 5.0.4) — open redirect no `FailureApp`

**Faixa vulnerável (GHSA-jp94-3292-c3xv):** `<= 5.0.3`, corrigida em `5.0.4`. Também inclui 4.9.4.

**Confirmação no código** — diff `failure_app.rb`, método `redirect_url`:

```diff
         path = if request.get?
           attempted_path
         else
-          request.referrer
+          extract_path_from_location(request.referrer)
         end
```

O 4.9.4 redireciona para o `Referer` **sem validar**; o 5.0.4 extrai apenas o path.

**Nos atinge?** 🔶 **Parcialmente — o caminho existe, a exploração é estreita.**

- **O caminho existe:** o branch não-GET é alcançado sempre que uma requisição não-GET falha
  autenticação. Temos ações não-GET atrás de `authenticate_user!`: `shipping_addresses#create`
  (POST), `#update` (PATCH), `#destroy` (DELETE), `#make_default` (PATCH), e o
  `destroy_user_session` (`sign_out_via = :delete`).
- **O que estreita:** não usamos `:timeoutable` (confirmado: ausente do model, `config.timeout_in`
  comentado), que é o cenário nomeado pelo advisory. E a proteção CSRF do Rails está ativa
  (`default_protect_from_forgery = true`, `forgery_protection_origin_check = true`), então um POST
  cross-site sem token válido é barrado **antes** de chegar ao `before_action` do Devise.
- **Avaliação honesta:** não consegui construir um cenário de exploração prático neste app sem uma
  sessão válida. Classifico como **risco baixo aqui**, mas é CVE sem patch disponível na nossa série —
  e o custo de sair dela é o mesmo upgrade que já vamos fazer pela §3.13.

### 3.15 — Mudanças de comportamento (não-breaking) que vale conferir

| Mudança do 5.0 | Nosso caso |
|---|---|
| Validador de `password_length` passa de `within:` para `minimum:`/`maximum:` com procs | `config.password_length = 6..128`. Mesmo resultado e mesmas chaves de erro (`:too_short`/`:too_long`) — nossos textos vêm do `devise.pt-BR.yml`. **Sem impacto** |
| `401 Unauthorized` para requisições **não-navegacionais** ao destruir sessão sem recurso autenticado | Nosso sign out é `button_to ... method: :delete` (`_navbar.html.erb:48`) — requisição navegacional (`Accept: text/html`) via Turbo. **Sem impacto** |
| Correção de gramática: `Invalid Email or password` → `Invalid email or password` | Texto vem do nosso `devise.pt-BR.yml`. **Sem impacto** |
| Apps novos com Rack 3.1+ passam a usar `error_status = :unprocessable_content` | Temos `:unprocessable_entity` e Rack **3.2.7**. O 5.0 converte via `ActionDispatch::Response.rack_status_code` (confirmado disponível no Rails 8.1.3.1) **justamente para não emitir warning**. **Sem impacto** — trocar para `:unprocessable_content` é cosmético e **fica fora da F** |
| `RegistrationsController` passa a depender de config do `:registerable` (5.0.2) | `:registerable` declarado. **Sem impacto** (§2.4) |
| `Devise` funciona sem ActionMailer sob Zeitwerk; `:from`/`:reply_to` como procs | Usamos ActionMailer e `mailer_sender` como string. **Sem impacto** |
| `Devise.secure_compare` passa a usar `ActiveRecord::SecurityUtils.secure_compare` | Interno. **Sem impacto** |
| `OmniAuth.config.allowed_request_methods` como verbos da rota de auth | Não usamos `:omniauthable`. **Sem impacto** |
| Fix ao passar `format` para `devise_for` | Não passamos `format:` (§2.5). **Sem impacto** |

### 3.16 — Placar

**12 breaking changes no CHANGELOG do 5.0.0.rc. Nenhum nos atinge.** Nove por ausência verificada com
`grep`, dois por termos views próprias, e um (`secret_key`) por verificação de configuração nas duas
pontas (dev e produção). **A conclusão da D1 se confirma** — com base mais larga do que ela tinha.

---

## 4. O contorno do `test_helper.rb`

### O que está lá hoje

`test/test_helper.rb:23`, precedido de 18 linhas de comentário marcadas `WORKAROUND TEMPORÁRIO`:

```ruby
Rails.application.routes_reloader.try(:execute_unless_loaded)
```

### O 5.0 corrige na origem? — **Sim, confirmado**

Fonte no branch `main` (5.0.x), `lib/devise.rb:275-283`:

```ruby
  # Store scopes mappings.
  @@mappings = {}
  def self.mappings
    # Starting from Rails 8.0, routes are lazy-loaded by default in test and development environments.
    # However, Devise's mappings are built during the routes loading phase.
    # To ensure it works correctly, we need to load the routes first before accessing @@mappings.
    Rails.application.try(:reload_routes_unless_loaded)
    @@mappings
  end
```

No 4.9.4 instalado, a mesma coisa é apenas `mattr_reader :mappings` (`lib/devise.rb:278`) — leitura
crua da variável, sem garantir que as rotas foram desenhadas. É exatamente o bug.

`Rails.application.reload_routes_unless_loaded` **existe no Rails 8.1.3.1** (verificado em runtime:
`railties-8.1.3.1/lib/rails/application.rb:166`) e é justamente o wrapper que chama
`routes_reloader.execute_unless_loaded`.

### Correção de fato ao nosso próprio comentário

O comentário do `test_helper.rb` afirma:

> *"É a mesma chamada que o Devise 5.0 embutiu em `find_scope!` (heartcombo/devise#5695)."*

**Dois erros:**

1. **Não é em `find_scope!`.** A correção está em `Devise.mappings`, um nível acima. `find_scope!`
   (`mapping.rb:35`) chama `Devise.mappings`, então o efeito chega lá — mas o local é outro. A
   diferença importa porque `Devise.mappings` é chamado por muito mais coisa do que `find_scope!`
   (helpers de rota, mailer, `devise_for`), e é por isso que a correção do 5.0 cobre **mais** caminhos
   do que o nosso contorno cobre.
2. **O PR é o [#5728](https://github.com/heartcombo/devise/pull/5728)**, não o #5695. O CHANGELOG do
   5.0.0.rc credita o #5728 na entrada *"Add Rails 8 support — Routes are lazy-loaded by default in
   test and development environments now so Devise loads them before `Devise.mappings` call."*

   **Confirmado na API do GitHub** — e a origem da confusão fica clara:

   | PR | Título | Estado | Arquivo tocado |
   |---|---|---|---|
   | #5695 | *Rails 8: Make test helpers work with deferred routes* | **fechado, `merged_at: null`** | `lib/devise/mapping.rb` |
   | #5728 | *Make Devise.mappings work with lazy loaded routes* | **mergeado 2024-11-24** | `lib/devise.rb` (+1) |

   O #5695 realmente propunha a correção em `mapping.rb` (onde vive `find_scope!`) — só que **nunca
   foi mergeado**. Nosso comentário descrevia a solução que foi descartada, não a que entrou.

**Nada disso muda a conclusão** — apenas o mecanismo descrito. O contorno segue removível.

### O contorno pode ser removido? — **Sim**

O 5.0.4 garante o carregamento das rotas dentro do próprio `Devise.mappings`, cobrindo os mesmos
caminhos do contorno e mais alguns. A linha do `test_helper.rb` vira redundante.

**Como provar, e não só afirmar** (passos 6 e 7 do §7): a suíte passando **sem** a linha não é prova
suficiente, porque **os 20 testes de hoje passam sem a linha mesmo no 4.9.4** — nenhum deles chama
`sign_in`, que é o único caminho que alcança o bug (registrado no próprio comentário do arquivo:
*"Os 17 testes passam hoje apenas porque nenhum chama sign_in"*). A prova precisa de duas partes:

1. **Prova direta, sem depender da suíte:** com o contorno removido, num processo `RAILS_ENV=test`
   limpo, verificar que `Devise.mappings` sai de `{}` sozinho — isto é, que a gem carrega as rotas.
2. **Prova por exercício:** escrever o primeiro teste que de fato chama `sign_in` — o teste que o
   contorno vinha protegendo por antecipação. Sem ele, a remoção continua sem cobertura de regressão.

### 4.1 — Executado em 2026-08-14: a prova (1) funcionou, a prova (2) **não existe**

**A prova direta passou.** Em processo `RAILS_ENV=test` limpo, sem reload explícito e com o contorno
fora do caminho (`bin/rails runner` não carrega `test_helper.rb`):

```
rotas carregadas ANTES de tocar em Devise.mappings: false
Devise.mappings.keys                              : [:user]
rotas carregadas DEPOIS                           : true
Devise.mappings vem de                            : devise-5.0.4/lib/devise.rb:277
```

Rotas não carregadas antes, `[:user]` mesmo assim, carregadas depois — **só o próprio Devise pode ter
disparado**. E o `source_location` confirma o mecanismo do #5728: `mappings` agora é **método**
(`devise.rb:277`), não mais o `mattr_reader` do 4.9.4.

**A prova (2) se revelou impossível de forma confiável, e essa é a lição desta seção.**

O plano acima supunha que "o primeiro teste que chama `sign_in`" seria automaticamente um guarda de
regressão do bug. **Não é.** Verificado empiricamente: com o Devise fixado de volta em **4.9.4** e o
contorno removido, `test/integration/authentication_test.rb` ficou **VERDE** (4 runs, 10 assertions,
0 falhas). Deveria ter ficado vermelho.

**Causa, isolada com sondas dentro da própria suíte:**

```
no início do teste             -> rotas=false  mappings=[]      ← a condição do bug EXISTE
depois de referenciar `User`   -> rotas=false  mappings=[]      ← não é o autoload do model
depois de `users(:one)`        -> rotas=true   mappings=[:user] ← o ACESSOR DE FIXTURE desenha as rotas
```

**O acessor de fixture desenha as rotas como efeito colateral.** Como todo teste chama `users(:one)`
antes do `sign_in`, o `find_scope!` sempre encontra as mappings populadas e a condição de falha
desaparece antes de ser exercitada.

Que o bug é real e alcançável, isso continua verdade — basta obter o registro sem o acessor:

```
depois de User.order(:id).first -> rotas=false  mappings=[]
sign_in LEVANTOU: RuntimeError: Could not find a valid mapping for #<User id: 298486374, ...>
```

**E é justamente por isso que NÃO se deve escrever o teste assim.** A vermelhidão passaria a depender
de qual expressão devolve o objeto — um acoplamento invisível ao estado de carregamento do processo,
que qualquer mudança futura neutraliza **em silêncio**. Foi exatamente o que aconteceu com a primeira
versão deste teste: ele se dizia guarda, estava verde, e o verde não significava nada. Um guarda que
se desarma sozinho e segue reportando verde é pior do que nenhum, porque simula proteção.

**Conclusão registrada:** o bug do lazy route loading **não é expressável como teste de suíte
confiável**. A suíte não controla o que já foi carregado no processo — e com `parallelize(workers:
:number_of_processors)` e seed aleatório, menos ainda. A prova de que o Devise 5.0 corrige é o
**comando de processo limpo** acima, documentado aqui:

```bash
RAILS_ENV=test bin/rails runner '
  rr = Rails.application.routes_reloader
  puts rr.instance_variable_get(:@loaded).inspect   # deve ser false
  puts Devise.mappings.keys.inspect                 # deve ser [:user]
'
```

`test/integration/authentication_test.rb` fica — mas pelo que ele **de fato** é: a primeira cobertura
de `sign_in`/`sign_out` do projeto (`current_user`, os dois `authenticate_user!`, o ciclo
entrar/sair). O cabeçalho do arquivo registra isso e o porquê de não ser guarda do lazy loading, para
o próximo leitor não recriar a ilusão nem tentar o `User.order(:id).first` frágil.

---

## 5. As 4 deprecations do Rails 8.1

### O que exatamente é emitido — capturado, não repetido de memória

```
$ RAILS_ENV=test bin/rails runner 'Rails.application.reload_routes_unless_loaded'

DEPRECATION WARNING: resource received a hash argument only. Please use a keyword instead.
  Support to hash argument will be removed in Rails 8.2. (called from block in <main> at config/routes.rb:2)
DEPRECATION WARNING: resource received a hash argument path. ...
DEPRECATION WARNING: resource received a hash argument path_names. ...
DEPRECATION WARNING: resource received a hash argument controller. ...
```

### Correção de um detalhe que os nossos docs registram de forma imprecisa

`UPGRADE_PLAN.md` e `RAILS_81_MIGRATION.md` §3.8 tratam isso como "4 deprecations". É verdade na
contagem, mas induz à leitura errada de que seriam 4 chamadas diferentes. **São 4 avisos de uma única
chamada** — um por chave do hash.

A chamada é `devise_registration`, em `devise-4.9.4/lib/devise/rails/routes.rb:416`:

```ruby
        options = {
          only: [:new, :create, :edit, :update, :destroy],
          path: mapping.path_names[:registration],
          path_names: path_names,
          controller: controllers[:registrations]
        }

        resource :registration, options do        # ← hash POSICIONAL: 4 chaves, 4 avisos
          get :cancel
        end
```

As outras chamadas de `resource` no mesmo arquivo (`devise_session:378`, `devise_password:386`,
`devise_confirmation:391`, `devise_unlock:397`) passam as opções **inline**, que o Ruby 3 entrega
como keywords — não emitem. Isso explica por que só o `registration` aparece.

### O 5.0.4 usa keywords? — **Sim, confirmado**

Mesmo método no branch `main` (5.0.x), `lib/devise/rails/routes.rb`:

```ruby
        resource :registration, **options do      # ← duplo splat: keywords
          get :cancel
        end
```

O corpo do método é idêntico ao do 4.9.4 exceto pelo `**`. **A correção é literalmente esses dois
caracteres.**

**Conclusão:** o upgrade elimina as 4 deprecations, e com elas o prazo do Rails 8.2. Nenhuma outra
fonte de deprecation existe hoje — as nossas próprias rotas não emitem (verificado: os 4 avisos
apontam todos para `config/routes.rb:2`, que é a linha do `devise_for`).

**Critério de aceite para a etapa:** `RAILS_ENV=test bin/rails runner 'Rails.application.reload_routes_unless_loaded' 2>&1 | grep -c DEPRECATION` deve retornar **0**.

---

## 6. Gems relacionadas

### Dependências diretas do Devise

| Gem | Requisito do 5.0.4 | Instalada | Última no rubygems | Sobe? |
|---|---|---|---|---|
| `bcrypt` | `~> 3.0` | 3.1.20 | 3.1.22 | **Pode** — 3.1.22 satisfaz `~> 3.0` |
| `orm_adapter` | `~> 0.1` | 0.5.0 | 0.5.0 | Não — já é a última |
| `responders` | qualquer | 3.2.0 | 3.2.0 | Não — já é a última |
| `warden` | `~> 1.2.3` | 1.2.9 | 1.2.9 | Não — já é a última |
| `railties` | `>= 7.0` | 8.1.3.1 | — | Não — requisito já satisfeito |

**Três das quatro dependências já estão na última versão publicada.** O único movimento possível é o
`bcrypt` 3.1.20 → 3.1.22, e mesmo esse **só acontece se o `bundle update devise` decidir mexer nele**
— o bundler não move o que não precisa mover.

**Nada quebra:** o requisito de `warden` é `~> 1.2.3` tanto no 4.9.4 quanto no 5.0.4 (inalterado entre
as séries), e `responders` continua sem constraint.

**Ação para o passo 4 do §7:** revisar o diff do `Gemfile.lock` e aceitar **apenas** `devise` e, se
aparecer, `bcrypt`. Qualquer outra gem no diff é sinal de desvio — mesmo protocolo que salvou a Etapa E
do salto do pagy.

### O que o `bundle update devise` de fato moveu (executado em 2026-08-14)

**Três gems, não duas.** O critério acima funcionou: a terceira era desvio e a execução parou nela.

| Gem | De | Para | Previsto? |
|---|---|---|---|
| `devise` | 4.9.4 | **5.0.4** | ✅ o alvo |
| `bcrypt` | 3.1.20 | **3.1.22** | ✅ dependência declarada (`~> 3.0`) |
| `json` | 2.15.1 | **2.21.2** | ❌ **não previsto** |

**`json` 2.15.1 → 2.21.2 veio a reboque do `bundle update devise`** — é transitiva de `activesupport`
e `faraday` (ambos declaram `json` **sem constraint** no lock), **NÃO** dependência do Devise. O
bundler pegou a mais nova disponível ao re-resolver; a 2.21.2 já estava instalada na máquina
(`gem list json` → `2.21.2, 2.15.1, default: 2.7.1`). É bump de patch da stdlib, série 2.x, **benigno**
— e o projeto já rodava fora do default do Ruby 3.3.5 antes desta etapa. Nossa superfície de uso
(`CepController#lookup` com `render json:`, e o parse do payload do webhook do Stripe) usa API estável.

**Aceito em vez de rodar `--conservative`**, que seguraria a `bcrypt` em 3.1.20 junto — trocaria um
bump benigno e não pedido por travar um bump desejado e previsto. O `--conservative` não distingue os
dois casos.

**Gems críticas conferidas uma a uma, todas intactas:** `rails`/`railties`/`activesupport` 8.1.3.1,
**`minitest` 5.27.0** (o pin segurou), **`pagy` 9.4.0** (não saltou para a série 43.x), `stripe`
11.7.0, `cloudinary` 2.4.0, `friendly_id` 5.5.1, `turbo-rails` 2.0.16, `importmap-rails` 2.2.0,
`sprockets-rails` 3.5.2. As três dependências previstas como imóveis (`warden` 1.2.9, `responders`
3.2.0, `orm_adapter` 0.5.0) não se moveram — já estavam nas últimas versões publicadas.

**Sem conflitos e sem avisos.** `bundle check` → *"The Gemfile's dependencies are satisfied"*.
`git diff --stat Gemfile.lock` → `1 file changed, 5 insertions(+), 5 deletions(-)`.

### O pin do minitest é afetado?

**Não.** `gem "minitest", "~> 5.27"` está no grupo `:test` e não tem relação de dependência com o
Devise (que não depende de minitest). O `bundle update devise` não toca no grupo `:test`.

**Confirmação adicional:** o Devise 5.0.4 não declara dependência de desenvolvimento que chegue ao
nosso lock — o que instalamos é só o runtime.

### O Rails 8.1.3.1 é afetado?

**Não.** `railties >= 7.0` sem teto: o bundler não tem motivo para mover o Rails. Este é o mesmo
princípio que fez a Etapa E funcionar ao contrário (`bundle update rails` sem mover terceiros).

**Precaução do passo 4:** rodar **`bundle update devise`**, nunca `bundle update` sem argumento — o
`Gemfile` traz `gem "pagy"` **sem constraint** e o pagy está na série 43.x lá fora, contra a 9.4.0
que usamos. Um update amplo quebraria a paginação e 3 testes. (Risco herdado da Etapa E; segue
válido.)

### Gemfile — mudança proposta

Linha 79, hoje:
```ruby
gem "devise"
```

Proposta (segue a convenção que o projeto já usa para o `rails` na linha 6):
```ruby
gem "devise", "~> 5.0", ">= 5.0.4"
```

O `>= 5.0.4` **não é cosmético**: é o que impede uma resolução futura de cair numa 5.0.x anterior às
correções das duas CVEs. Sem ele, `~> 5.0` sozinho permitiria 5.0.0 a 5.0.3.

---

## 7. Plano de execução

Cada passo é um ponto de parada: **se o resultado divergir do esperado, parar e reportar antes de
seguir**. Passos que exigem aprovação explícita estão marcados 🔒.

### Preparação

1. 🔒 **Backup do banco de produção:** `heroku pg:backups:capture --app trscrews-prod`.
   Anotar o ID (`b0XX`). A F **não tem migration**, então o backup é hábito de deploy, não
   pré-requisito do trabalho local — pode ser feito só antes do passo 13.
2. 🔒 **Criar a branch:** `git checkout -b upgrade/devise-5` a partir de `master` (`a2e95d3`).
   Snapshot local `cp Gemfile.lock Gemfile.lock.4.9.4-backup` — **não versionar** (`.gitignore` já
   cobre `Gemfile.lock.*-backup`).

### Preparar o dado que hoje não existe

3. **Criar usuário de teste no development.** Hoje `User.count = 0` no dev (o banco tem só os 22
   screws do seed), então **o Fluxo 1 não é executável sem isso** — foi exatamente o que impediu a
   validação na D1 e na E.

   Criar **antes** do upgrade, ainda no Devise 4.9.4, e registrar o comportamento observado. Isso dá
   uma **linha de base**: sem ela, qualquer estranheza depois do upgrade é indistinguível de bug
   pré-existente.

   Dois usuários, cobrindo os dois lados do `ensure_first_address_created`
   (`application_controller.rb:40`), que redireciona para o formulário de endereço quem não tem
   nenhum:

   ```ruby
   # bin/rails console (development)
   a = User.create!(email: "confirmado@dev.local", password: "password123", name: "Dev Confirmado")
   a.confirm                                   # pula o e-mail; simula conta madura
   a.shipping_addresses.create!(...)           # com endereço → navega livre

   b = User.create!(email: "sem-endereco@dev.local", password: "password123", name: "Dev Sem Endereço")
   b.confirm                                   # sem endereço → deve ser barrado pelo before_action
   ```

   **Decisão a tomar antes de rodar:** criar via console é a via mais simples, mas não deixa rastro
   reproduzível. A alternativa é um `db/seeds_users.rb` separado. **Perguntar ao usuário** — o
   `db/seeds.rb` atual é o dos 22 screws e misturar usuários nele muda o significado do arquivo.

4. **Percorrer o Fluxo 1 no Devise 4.9.4 e anotar cada resultado.** É a linha de base do passo 10.
   Servidor real (`bin/rails server`), não `runner`:
   - `/users/sign_up` → cadastro novo → com `:confirmable`, a conta nasce inativa, então o esperado é
     `after_inactive_sign_up_path_for` → **`root_path`** (não o formulário de endereço).
   - E-mail de confirmação em **`/letter_opener`** → clicar no link → conta confirmada.
   - `/users/sign_in` com `confirmado@dev.local` → entra.
   - Navbar mostra o nome (`_navbar.html.erb:36`) → `current_user` funcionando.
   - `/orders/mine` **deslogado** → deve mandar para login (`authenticate_user!`).
   - `/shipping_addresses` logado como `sem-endereco@dev.local` → deve ser empurrado para
     `new_shipping_address_path` pelo `ensure_first_address_created`.
   - "Sair" (`button_to`, DELETE) → desloga.
   - "Esqueci minha senha" → e-mail de reset no letter_opener → trocar a senha → logar com a nova.
   - **Trocar o e-mail em `/users/edit`** → com `reconfirmable = true`, deve gravar em
     `unconfirmed_email` e mandar confirmação para o endereço novo. **É o caminho exato da
     CVE-2026-32700 (§3.13)** — é o que mais importa comparar depois do upgrade.

### Upgrade

5. **Gemfile:** trocar `gem "devise"` por `gem "devise", "~> 5.0", ">= 5.0.4"` (linha 79).
6. **`bundle update devise`** — nunca `bundle update` sem argumento (§6).
   **Ponto de parada:** revisar `git diff Gemfile.lock`. Esperado: `devise 4.9.4 → 5.0.4` e, no
   máximo, `bcrypt 3.1.20 → 3.1.22`. **Qualquer outra gem no diff → parar e reportar.**

### Remover o contorno, com prova

7. **Remover** do `test/test_helper.rb` a linha 23 e o bloco de comentário das linhas 5–22 (o
   comentário só existe para explicar a linha; sem ela vira ruído).
8. **Prova direta de que o 5.0 resolve na origem** — não depende da suíte (§4):
   ```bash
   RAILS_ENV=test bin/rails runner 'puts "mappings: #{Devise.mappings.keys.inspect}"'
   ```
   **Esperado: `[:user]`.** Se vier `[]`, o contorno não pode ser removido — parar e reportar.
9. **Suíte:** `bin/rails test`. Baseline a bater: **20 runs / 54 assertions / 0 failures / 0 errors /
   0 skips**.
   **Ressalva honesta:** verde aqui **não prova** que a remoção foi segura — os 20 testes atuais
   passam sem o contorno mesmo no 4.9.4, porque nenhum chama `sign_in` (§4). O passo 8 é a prova; este
   é só a não-regressão.
10. **Escrever o primeiro teste que autentica** — o que o contorno vinha protegendo por antecipação, e
    que hoje não existe. Fecha o buraco de cobertura em vez de só remover a proteção:
    ```ruby
    # test/controllers/orders_controller_test.rb (ou arquivo novo)
    include Devise::Test::IntegrationHelpers   # forma nova; ver §3.5 e §3.6

    test "redirects to sign in when requesting an order while signed out" do ... end
    test "shows the order to its owner when signed in" do
      sign_in users(:one)                       # forma nova: sem 2º argumento posicional
      ...
    end
    ```
    Usar as fixtures que já existem (`test/fixtures/users.yml` tem `one` e `two`, ambas com
    `confirmed_at` preenchido). **Este teste deve nascer RED se o contorno for removido no 4.9.4** —
    vale confirmar isso antes, para provar que ele de fato exercita o caminho do bug.

### Validação e deprecations

11. **Deprecations:** critério de aceite do §5 —
    ```bash
    RAILS_ENV=test bin/rails runner 'Rails.application.reload_routes_unless_loaded' 2>&1 | grep -c DEPRECATION
    ```
    **Esperado: `0`.**
12. **Repetir o Fluxo 1 inteiro do passo 4**, agora no 5.0.4, comparando com a linha de base anotada.
    Atenção redobrada na troca de e-mail (`reconfirmable`) e no reset de senha — são os dois módulos
    que o §3.9 apontou como sensíveis a mudança de `secret_key`. **Um token de reset gerado ANTES do
    upgrade deve continuar válido DEPOIS** — é a verificação empírica da conclusão do §3.9. Gerar um
    no passo 4 e não usar, para testar aqui.
13. **Revisar `config/initializers/devise.rb` contra o template do 5.0.4** — as 14 configs ativas
    seguem existindo (§2.2), então não é esperada nenhuma mudança obrigatória. Revisar só para
    registrar divergências; **não** adotar o template novo (mesmo precedente da D1/E: arquivo nosso,
    linha a linha).

### Deploy

14. 🔒 **Merge para `master`** (`--no-ff`, mesmo padrão de `eb59a6f` e `88755c7`) e **deploy**.
15. 🔒 **Repetir o Fluxo 1 inteiro no Heroku.** Autenticação é o caminho crítico desta etapa, e
    produção **tem 15 usuários de teste** — diferente do dev. Verificar em especial que **usuário
    existente continua autenticando** (é a linha do Apêndice de riscos do `UPGRADE_PLAN`: *"Devise não
    autentica usuários existentes → reverter"*).
16. **Rollback, se necessário:** sem migration. `git push heroku <sha-anterior>:main` 🔒, ou
    `git checkout` do `Gemfile`/`Gemfile.lock` em local.

---

## 8. Riscos específicos deste projeto

| # | Risco | Probabilidade | Impacto | Mitigação |
|---|---|---|---|---|
| 1 | **Usuário existente não autentica após o deploy** | Baixa | **Alto** | O `encrypted_password` é BCrypt puro, independente de `Devise.secret_key`, e `config.stretches` não muda. O 5.0 não altera o esquema de hash. Ainda assim é o risco de maior impacto: passo 15 existe para pegá-lo, e o rollback é imediato |
| 2 | **Tokens de `recoverable`/`confirmable` invalidados** pela mudança de origem do `secret_key` | **Muito baixa** | Médio | **Descartado por verificação, não por suposição** (§3.9): produção não tem `SECRET_KEY_BASE`, lê das credentials via `RAILS_MASTER_KEY` — mesma origem da cadeia antiga. Verificação empírica no passo 12 |
| 3 | **Fluxo 1 nunca foi validado — nem antes, nem depois** | **Alta** | Médio | É a dívida herdada da D1 e da E (`UPGRADE_PLAN` §8: *"Fluxos de compra nunca validados em produção"*). A F é a primeira etapa que **obriga** a validação, porque mexe justamente em autenticação. Passos 3, 4 e 12 existem por isso |
| 4 | **Remover o contorno sem cobertura que o exercite** | **Alta** se ignorado | Médio | Os 20 testes passam com ou sem o contorno — verde não prova nada (§4). Passos 8 e 10 são a mitigação |
| 5 | `bundle update devise` arrastando outras gems (pagy 9→43) | Baixa | Alto | Argumento explícito no update + revisão obrigatória do diff do lock (passo 6). Mesmo risco da Etapa E |
| 6 | **`ensure_first_address_created` interferindo na leitura do Fluxo 1** | Média | Baixo | O `before_action` (`application_controller.rb:40`) redireciona quem não tem endereço, e pode ser confundido com falha de autenticação. Por isso o passo 3 cria **dois** usuários — um com endereço, outro sem |
| 7 | `Devise::Encryptor.digest` nas fixtures (API interna) mudar | Muito baixa | Baixo | Verificado presente no 5.0.4. Se quebrar, a suíte falha no carregamento das fixtures — visível imediatamente no passo 9 |
| 8 | **17 views customizadas divergindo do 5.0** | Baixa | Baixo | Nossas views vencem; os 3 breaking changes de template não nos alcançam (§3.10–3.12). Divergência aqui é cosmética, não funcional |
| 9 | **Produção tem 15 usuários e 10 endereços de teste** | — | Baixo | Não é risco do upgrade, mas é o dado que torna o passo 15 possível — e o único ambiente onde "usuário existente autentica" é testável de verdade |

**Risco que NÃO existe, apesar de parecer:** mudança de rotas. O `devise_for` é a forma mais simples
possível (§2.5) e a única diferença de geração entre 4.9.4 e 5.0.4 no caminho que usamos é o `**` do
`resource :registration` (§5). Os path helpers gerados são idênticos.

---

## 9. Estimativa de tempo

O `UPGRADE_PLAN.md` estima **1–2h** para a Etapa F. **Essa estimativa está subdimensionada**, pela
mesma razão que a da Etapa E estava (revista lá de 2–3h para 3h–4h15): ela conta o upgrade da gem, não
o ritual de validação que é o que faz a etapa chegar em produção sem regressão.

| Bloco | Passos | Tempo |
|---|---|---|
| Preparação (backup, branch, snapshot) | 1–2 | 10 min |
| **Criar usuários de teste no dev** | 3 | 20 min |
| **Fluxo 1 no 4.9.4 — linha de base** | 4 | **40 min** |
| Gemfile + `bundle update devise` + revisão do lock | 5–6 | 15 min |
| Remover contorno + prova direta + suíte | 7–9 | 20 min |
| **Escrever o primeiro teste com `sign_in`** | 10 | **30–45 min** |
| Conferir deprecations = 0 | 11 | 5 min |
| **Fluxo 1 no 5.0.4 — comparação** | 12 | **40 min** |
| Revisar initializer contra o template | 13 | 15 min |
| Merge + deploy | 14 | 15 min |
| **Fluxo 1 no Heroku** | 15 | **30 min** |
| **Total** | | **3h40 – 4h15** |

**O que domina a estimativa não é o Devise — é o Fluxo 1**, percorrido três vezes (baseline, pós-upgrade
local, produção): ~1h50 dos ~4h. Esse custo não é desperdício desta etapa; é a dívida de validação que
a D1 e a E deixaram acumular sendo paga aqui, no lugar onde ela finalmente é obrigatória.

**Caminho curto, se o tempo apertar:** os passos 3, 4 e 12 (baseline + comparação local) são o que dá
confiança; o passo 10 (primeiro teste com `sign_in`) é o que deixa a confiança **permanente**. Se algum
tiver que sair, que seja o 13 (revisão do initializer), que é registro, não verificação. **Não cortar o
passo 8** — sem ele a remoção do contorno vira ato de fé.

---

## 10. Execução do Fluxo 1 no 5.0.4 — registro

> Esta seção é **log de execução**, escrita enquanto o fluxo é percorrido. Passos 3 a 11 do §7 já
> estavam feitos quando ela começou.

### 10.0 — Onde a execução pegou o trabalho

**O Fluxo 1 no 5.0.4 já tinha sido iniciado em 2026-08-14 e as anotações se perderam** quando a sessão
travou. O que sobrou é rastro indireto no banco e no `letter_opener`: um cadastro
(`novo-cadastro-50@dev.local`, criado 17:15 UTC, confirmado 17:34 UTC) e o reset de senha da §3.9. **Nada
disso foi documentado**, e por isso **não conta**: o fluxo está sendo refeito do zero aqui, sem tentar
reconstruir o que não tem registro.

**Assimetria honesta desta comparação:** a linha de base do 4.9.4 (passo 4 do §7) **também nunca foi
escrita neste repositório** — foi percorrida em 2026-08-14 (o usuário `novo-cadastro@dev.local`, 14:31
UTC, e o e-mail em `tmp/letter_opener/1786717871_*` provam que foi), mas os resultados ficaram só no
chat perdido. A comparação abaixo é contra as anotações do usuário, não contra um baseline versionado.
**Lição operacional:** anotar direto no doc enquanto percorre, não ao final — foi exatamente essa a
diferença entre o que sobreviveu ao travamento e o que não sobreviveu.

**Estado do ambiente para esta execução:**

| Item | Valor |
|---|---|
| Branch | `upgrade/devise-5` (criada de `master` em `a2e95d3`, passo 2 do §7) |
| Devise | 5.0.4 (`bundle info devise`) |
| Rails | 8.1.3.1 |
| Suíte | 24 runs / 64 assertions / 0 failures / 0 errors / 0 skips |
| Contorno do `test_helper.rb` | removido (`grep routes_reloader` → vazio) |
| Servidor | `bin/rails server -p 3000 -b 127.0.0.1` — servidor real, não `runner`, não teste de integração |
| Cliente | `curl` com cookie jar e `authenticity_token` extraído do HTML, `Accept: text/html,application/xhtml+xml` |

### 10.1 — Passo A: sign_in, rota protegida, sign_out, deslogado barrado

| # | Requisição | Esperado | Observado | |
|---|---|---|---|---|
| A1 | `GET /shipping_addresses` deslogado | 302 → `/users/sign_in` | **302 → `/users/sign_in`** | ✅ |
| A2 | `GET /orders/mine` deslogado | 302 → `/users/sign_in` | **302 → `/users/sign_in`** | ✅ |
| A3 | `GET /users/sign_in` | 200, form com CSRF | **200**, `authenticity_token` de 86 chars | ✅ |
| A4 | `POST /users/sign_in` (`confirmado@dev.local`) | 303 + sessão criada | **303 → `/shipping_addresses`** | ✅ ⚠️ |
| A5 | `GET /` logado | navbar com o nome | **200**, body contém `Dev Confirmado` | ✅ |
| A6 | `GET /shipping_addresses` logado | 200 com o endereço do próprio usuário | **200**, contém `Dev Confirmado` e `Avenida Paulista` | ✅ |
| A7 | `DELETE /users/sign_out` (`Accept: text/html`) | 303 → `/` | **303 → `/`** | ✅ |
| A8 | `GET /shipping_addresses` depois do sign_out | 302 → `/users/sign_in` | **302 → `/users/sign_in`** | ✅ |
| A9 | `GET /` depois do sign_out | sem o nome na navbar | **200**, body **não** contém `Dev Confirmado` | ✅ |

**Passo A inteiro verde.** `authenticate_user!` barra nos dois sites, `current_user` resolve para o
usuário certo (A6 mostra o endereço **dele**, não "alguma sessão existe"), e o ciclo entrar/sair fecha
de fato — A9 é o que separa "sign_out respondeu 303" de "a sessão morreu".

**⚠️ A4 não redireciona para `root_path`, e isso está certo.** O destino foi `/shipping_addresses` —
a rota que A1 tentou antes de ser barrada. É o *friendly forwarding* do Devise:
`authenticate_user!` guarda a rota negada em `session["user_return_to"]` e
`after_sign_in_path_for` a consome via `stored_location_for(:user)`. Anotado porque numa leitura
apressada parece divergência do baseline: quem entra em `/users/sign_in` **direto**, sem ter batido
antes numa rota protegida, cai em `root_path`. O destino depende do caminho percorrido, não da versão
do Devise — comportamento idêntico no 4.9.4.

**Sobre o 303 do A7:** medido com `Accept: text/html`. O contraste `*/*` (204) vs `text/html` (303) é
o detalhe do passo B e ainda **não** foi percorrido aqui — o valor acima não é a comparação, é só a
metade `text/html` dela.

### 10.2 — Passo A, fechamento: o caminho exato do baseline

Para tornar a comparação com o 4.9.4 **idêntica em caminho**, e não só em resultado, o login foi
refeito em sessão nova onde a **primeira** requisição é o próprio formulário — nada guardado em
`session["user_return_to"]`:

| # | Requisição | Esperado (4.9.4) | Observado (5.0.4) | |
|---|---|---|---|---|
| A10.1 | `GET /users/sign_in` como 1ª requisição da sessão | 200 | **200** | ✅ |
| A10.2 | `POST /users/sign_in` (`confirmado@dev.local`) | 303 → **`/`** | **303 → `/`** | ✅ |
| A10.3 | `GET /` | flash de login + nome na navbar | **200**, flash `"Login realizado com sucesso."`, contém `Dev Confirmado` | ✅ |

**`after_sign_in_path_for` não mudou.** Mesmo usuário, mesma senha, mesma versão — só o caminho
percorrido antes difere, e ele sozinho explica `/` (A10) contra `/shipping_addresses` (A4). A hipótese
do friendly forwarding fica confirmada por construção: removida a causa (`user_return_to`), o destino
volta a ser `root_path`.

### 10.3 — Passo B: `sem-endereco@dev.local` e o `ensure_first_address_created`

| # | Requisição | Esperado | Observado | |
|---|---|---|---|---|
| B1 | `POST /users/sign_in` (login direto) | 303 → `/` | **303 → `/`** | ✅ |
| B2 | `GET /` | 302 → `/shipping_addresses/new` | **302 → `/shipping_addresses/new?return_to=checkout`** | ✅ |
| B3 | `GET /shipping_addresses/new?return_to=checkout` | 200, formulário | **200**, contém `Dev Sem Endereço` | ✅ |
| B4 | `GET /orders/mine` (rota protegida que **não** é o formulário) | 302 → `/shipping_addresses/new` | **302 → `/shipping_addresses/new?return_to=checkout`** | ✅ |

**Não é falha de autenticação, e B3 é o que prova isso.** O `sign_in` funcionou (B1 devolveu 303, não
re-renderizou o formulário), e a navbar em B3 mostra `Dev Sem Endereço` — ou seja, `current_user`
resolve, a sessão está viva, e o que barra é o `before_action` de negócio
(`application_controller.rb:40`), não o Warden.

**B4 é o contraste que fecha a leitura.** O redirect não é específico de `/shipping_addresses`: qualquer
rota fora de `shipping_addresses#new/create` cai no mesmo lugar enquanto o usuário não tiver endereço.
Um leitor que só olhasse B2 poderia achar que o login "não completou"; B3 + B4 mostram que completou e
que o desvio é intencional.

**Por que dois usuários no `db/seeds_users.rb`:** este passo é exatamente o risco #6 do §8 — o
`ensure_first_address_created` confundido com falha de auth. Com `confirmado@dev.local` (§10.1, A6)
navegando livre e `sem-endereco@dev.local` desviado aqui, a diferença é observável em vez de suposta.

### 10.4 — Passo B: `sign_out` e o contraste por `Accept`

**Sessão viva nos dois casos** — é a condição que separa este teste do comportamento novo do 5.0:

| # | Requisição | Esperado | Observado | |
|---|---|---|---|---|
| B5a | `DELETE /users/sign_out`, `Accept: */*` | **204** No Content | **204** | ✅ |
| B5b | `DELETE /users/sign_out`, `Accept: text/html` | **303** → `/` | **303 → `/`** | ✅ |
| B5c | `GET /shipping_addresses` depois de cada um | 302 → `/users/sign_in` | **302 → `/users/sign_in`** nos dois | ✅ |

Bate com o baseline do 4.9.4 (204/303). A diferença vem do `respond_to` do `SessionsController#destroy`:
sem preferência por HTML, o Devise responde `head :no_content`; com `text/html`, redireciona com o
303 que o Turbo exige em resposta a `DELETE`.

**O 401 do CHANGELOG do 5.0 não nos atinge, e B5c é o que sustenta a afirmação.** A mudança vale para
`sign_out` **sem sessão ativa** — antes devolvia sucesso, agora devolve 401. Os dois casos acima têm
sessão, então caem no caminho de sucesso de sempre. B5c confirma que a sessão foi de fato destruída nos
dois, e não que só o status mudou. **O caso sem sessão não foi medido** — está fora do baseline B1–B4 e
fora do que o app exercita (o botão "Sair" só existe renderizado para quem está logado).

### 10.5 — Passo C: cadastro + confirmação

Conta nova `fluxo1-50@dev.local`, nome `Fluxo Um Cinquenta`, criada pelo formulário real:

| # | Requisição / verificação | Esperado | Observado | |
|---|---|---|---|---|
| C1 | `GET /users/sign_up` | 200 com CSRF | **200** | ✅ |
| C2 | `POST /users` | 303 → `/` (conta nasce inativa: `after_inactive_sign_up_path_for`) | **303 → `/`** | ✅ |
| C3 | flash depois do cadastro | aviso de confirmação pendente | **`"Enviamos um e-mail com o link de confirmação..."`** | ✅ |
| C4 | navbar depois do cadastro | **sem** o nome (não logou) | body **não** contém `Fluxo Um Cinquenta` | ✅ |
| C5 | `name` no model | persistido | **`name = "Fluxo Um Cinquenta"`** | ✅ |
| C6 | estado do registro | `confirmed_at` nulo, token gerado | `confirmed_at=nil`, `confirmation_token` presente, `active_for_authentication?=false`, `inactive_message=:unconfirmed` | ✅ |
| C7 | e-mail no `letter_opener` | 1 dir novo, assunto pt-BR | **`1787056634_6318092_d49930f`**, `"Confirme sua conta na Trautoparts"` | ✅ |
| C8 | token do e-mail × token do banco | iguais | **iguais** (`Za187HMKXEa92r8FWqyy`) | ✅ |
| C9 | `sign_in` **antes** de confirmar | barrado | **302 → `/users/sign_in`**, flash `"Você precisa confirmar seu e-mail antes de continuar."` | ✅ |
| C10 | `GET` do link de confirmação | confirma e redireciona | **302 → `/users/sign_in`**, flash `"Seu e-mail foi confirmado com sucesso..."` | ✅ |
| C11 | `sign_in` **depois** de confirmar | entra | **303 → `/`**, depois 302 → `/shipping_addresses/new` (sem endereço), navbar com `Fluxo Um Cinquenta` | ✅ |
| C12 | estado final | confirmado | `confirmed_at=2026-08-18T12:38:23Z`, `active_for_authentication?=true`, `unconfirmed_email=nil` | ✅ |

**C5 é a verificação do `configure_permitted_parameters`** (`application_controller.rb:63`). Se o
`devise_parameter_sanitizer.permit(:sign_up, keys: [:name])` tivesse se perdido no upgrade, o cadastro
ainda passaria — só que com `name` nulo. O 5.0 não mexeu na API do sanitizer, e o campo chegou ao
model.

**C4 e C9 são o par que prova que `:confirmable` está ativo de verdade.** Cadastro que não loga
(C4) e login barrado antes da confirmação (C9), com a mensagem pt-BR certa vinda do nosso
`config/locales/devise.pt-BR.yml`, não da string em inglês da gem.

**C11 volta a passar pelo `ensure_first_address_created`** — conta nova não tem endereço, então o
desvio para `/shipping_addresses/new` é o mesmo comportamento do §10.3, não uma anomalia do cadastro.

### 10.6 — Achado lateral, fora do baseline: erro de confirmação sem tradução pt-BR

Verificação extra, não prevista no baseline C1–C7: **reusar um link de confirmação já usado**.

`confirmable` **não limpa o `confirmation_token`** depois de confirmar (segue no banco), então o link
antigo continua resolvendo para o usuário. O Devise adiciona o erro certo — mas ele chega ao usuário
final assim:

```
Email Translation missing. Options considered were:
- pt-BR.activerecord.errors.models.user.attributes.email.already_confirmed
- pt-BR.errors.messages.already_confirmed
...
```

Mesma coisa para token inexistente (`...messages.invalid`, em `confirmation_token`).

**Causa:** `config/locales/devise.pt-BR.yml` é uma tradução **mínima escrita à mão** — o bloco
`pt-BR.errors.messages` (linha 41) tem só `taken` e `not_saved`. As chaves `already_confirmed`,
`invalid`, `confirmation_period_expired` e as demais nunca existiram lá.

**Não é regressão da Etapa F.** O arquivo é versionado e **não** aparece em `git status` nesta branch —
é byte-a-byte o de `master@a2e95d3`, anterior ao upgrade. A cadeia de lookup que o Devise usa para
esses erros é a mesma do 4.9.4; a chave simplesmente nunca esteve no nosso locale. *(Ressalva: isso
não foi medido empiricamente no 4.9.4 — a conclusão vem do arquivo, não de execução.)*

**Deixado como está.** Corrigir é adicionar chaves ao locale, o que é mudança de conteúdo pt-BR sem
relação com o Devise 5.0, e misturá-la aqui polui o diff da etapa. Registrado para virar item próprio.
Impacto real é baixo: só aparece a quem clica duas vezes no link de confirmação ou adultera o token.

**A página `devise/confirmations/new` também está em inglês e sem estilo** (`app/views/devise/
confirmations/new.html.erb` é a cópia crua do `rails g devise:views`, com `<h2>Resend confirmation
instructions</h2>`). Mesma classificação: pré-existente, fora do escopo da F.

---

## 11. CVE-2026-32700 (reconfirmable) — verificação isolada

O motivo da etapa. Executado em 2026-08-18, na branch `upgrade/devise-5`, com `devise 5.0.4` e
`Devise.reconfirmable = true` (`config/initializers/devise.rb:160`).

### 11.1 — A linha existe na gem em uso

Comparação direta entre as **duas gems instaladas na máquina** (`gem list devise` → `5.0.4, 4.9.4`),
não contra o GitHub:

```diff
$ diff -u <(awk '/def postpone_email_change.../,/^        end$/' devise-4.9.4/lib/devise/models/confirmable.rb) \
          <(awk '/def postpone_email_change.../,/^        end$/' devise-5.0.4/lib/devise/models/confirmable.rb)

         def postpone_email_change_until_confirmation_and_regenerate_confirmation_token
           @reconfirmation_required = true
+          # Force unconfirmed_email to be updated, even if the value hasn't changed, to prevent a
+          # race condition which could allow an attacker to confirm an email they don't own. See #5783.
+          devise_unconfirmed_email_will_change!
           self.unconfirmed_email = self.email
           self.email = self.devise_email_in_database
           self.confirmation_token = nil
           generate_confirmation_token
         end
```

**O diff do método é exatamente a correção — uma linha de código e dois de comentário, nada mais.**
Presente em `devise-5.0.4/lib/devise/models/confirmable.rb:265`. E o que ela chama, para ActiveRecord
(`devise-5.0.4/lib/devise/orm.rb:38`):

```ruby
def devise_unconfirmed_email_will_change!
  unconfirmed_email_will_change!
end
```

Ou seja: marca `unconfirmed_email` como sujo **na marra**, para que o ActiveRecord inclua a coluna no
`UPDATE` mesmo quando o valor não mudou. É esse forçar que fecha a janela da race.

### 11.2 — A troca de e-mail, passo a passo

`confirmado@dev.local` → `confirmado-novo@dev.local`, pelo formulário real de `/users/edit`, com a
senha atual que o Devise exige.

**Estado ANTES:**

```
email             = "confirmado@dev.local"
unconfirmed_email = nil
confirmed_at      = "2026-08-14T14:23:54Z"
confirmation_token= nil
pending_reconfirmation? = false
```

| # | Verificação | Esperado (reconfirmable correto) | Observado | |
|---|---|---|---|---|
| D3 | `PUT /users` com o e-mail novo | 303, sem erro | **303 → `/`** | ✅ |
| D3.1 | **`email` (o ativo)** | **continua o ANTIGO** | **`"confirmado@dev.local"`** | ✅ |
| D3.2 | **`unconfirmed_email`** | recebe o NOVO | **`"confirmado-novo@dev.local"`** | ✅ |
| D3.3 | `confirmed_at` | inalterado | **`2026-08-14T14:23:54Z`** (o mesmo) | ✅ |
| D3.4 | `confirmation_token` | regenerado | **`Kw-ixfeS2e9Y1eDtKdbg`** | ✅ |
| D3.5 | `pending_reconfirmation?` | `true` | **`true`** | ✅ |
| D4 | e-mail de confirmação | 1, **para o endereço NOVO** | dir `1787057524_288624_1bc841c`, destinatário **`confirmado-novo@dev.local`** apenas | ✅ |
| D4.1 | token do link × token do banco | iguais | **iguais** (`Kw-ixfeS2e9Y1eDtKdbg`) | ✅ |
| D5 | sessão corrente depois da troca | continua viva | **200** em `/shipping_addresses`, com o endereço do usuário | ✅ |
| D6 | login com o e-mail **ANTIGO** | **funciona** | **303**, flash de login, navbar com o nome | ✅ |
| D7 | login com o e-mail **NOVO** | **não** funciona ainda | **422**, `"E-mail ou senha inválidos."` | ✅ |
| D8 | `/users/edit` | mostra o aviso de pendência | contém `"Estamos aguardando a confirmação do novo e-mail"` + o endereço novo | ✅ |
| D9 | `GET` do link de confirmação | confirma a troca | **302**, flash `"Seu e-mail foi confirmado com sucesso..."` | ✅ |
| D9.1 | `email` depois de confirmar | vira o NOVO | **`"confirmado-novo@dev.local"`** | ✅ |
| D9.2 | `unconfirmed_email` depois | volta a `nil` | **`nil`** | ✅ |
| D10 | login com o e-mail NOVO | funciona | **303**, navbar com o nome | ✅ |
| D11 | login com o e-mail ANTIGO | **não** funciona mais | **422**, `"E-mail ou senha inválidos."` | ✅ |

**O invariante de segurança do reconfirmable vale em todos os pontos:** o endereço que autentica só
muda **depois** que o dono do endereço novo prova posse dele. Entre D3 e D9 existe uma janela em que o
usuário pediu a troca e ela ainda não valeu — e nessa janela D6 e D7 mostram o comportamento correto:
o antigo continua sendo a identidade, o novo não é nada ainda.

### 11.3 — O ponto da CVE: token e `unconfirmed_email` consistentes

A race não foi reproduzida (é timing, e reproduzi-la exigiria concorrência forçada). O que dá para
verificar de forma determinística é **o efeito da linha nova**, e ele aparece no SQL.

O caso que expõe o mecanismo é **repetir a troca para o endereço que já está pendente** — aí
`unconfirmed_email` recebe um valor **idêntico ao que já está no banco**, enquanto o
`confirmation_token` é regenerado. É exatamente a situação em que o ActiveRecord, sozinho, deixaria a
coluna de fora do `UPDATE` por não haver diferença:

```sql
-- 1ª troca (valor novo — a coluna entraria no UPDATE de qualquer jeito)
UPDATE "users" SET "updated_at" = ..., "confirmation_token" = 'Kw-ixfeS2e9Y1eDtKdbg',
  "confirmation_sent_at" = ..., "unconfirmed_email" = 'confirmado-novo@dev.local'
  WHERE "users"."id" = 1

-- 2ª troca, MESMO endereço (o caso que importa)
UPDATE "users" SET "updated_at" = ..., "confirmation_token" = 'GfMTDhzrJWFz2hvjF_Ai',
  "confirmation_sent_at" = ..., "unconfirmed_email" = 'confirmado-novo@dev.local'
  WHERE "users"."id" = 1
```

**A segunda statement é a prova.** O valor de `unconfirmed_email` não mudou, e mesmo assim a coluna
está lá — porque `devise_unconfirmed_email_will_change!` a marcou como suja. **Token novo e
`unconfirmed_email` viajam na mesma statement, sempre**, e o par nunca é escrito pela metade. Sem a
linha, esse segundo `UPDATE` carregaria só o token novo, e é dessa dissociação entre token e endereço
pendente que a CVE-2026-32700 vive.

Confirmado também no ciclo de fechamento: a confirmação escreve `email`, `confirmed_at` e
`unconfirmed_email = NULL` numa statement só —

```sql
UPDATE "users" SET "email" = 'confirmado-novo@dev.local', "updated_at" = ...,
  "confirmed_at" = ..., "unconfirmed_email" = NULL WHERE "users"."id" = 1
```

E o token antigo **morre na regeneração**: depois da segunda troca, o link `Kw-ix...` do primeiro
e-mail não confirma mais nada — só o `GfMT...` vale. Um token por vez, sempre casado com o
`unconfirmed_email` corrente.

**Conclusão da §11: a CVE-2026-32700 está fechada na versão em uso**, verificada no código da gem
instalada (11.1), no comportamento observável do fluxo (11.2) e no SQL que o mecanismo produz (11.3).

### 11.4 — Achado: flash de atualização de conta sem tradução pt-BR

Descoberto aqui, no D3: depois de salvar `/users/edit`, o usuário recebe como flash o texto

```
Translation missing. Options considered were:
- pt-BR.devise.registrations.user.updated
- pt-BR.devise.registrations.updated
```

Conferido por lookup direto — faltam no `config/locales/devise.pt-BR.yml`:

| Chave | Estado |
|---|---|
| `devise.registrations.signed_up_but_unconfirmed` | ✅ existe |
| `devise.registrations.updated` | ❌ **faltando** |
| `devise.registrations.update_needs_confirmation` | ❌ **faltando** |
| `devise.registrations.destroyed` | ❌ **faltando** |

**Mais sério que o §10.6.** Aquele só aparece a quem clica duas vezes num link de confirmação; este
aparece para **qualquer usuário que edite a conta** — é caminho normal, e está em produção hoje.

**Mesma classificação, mesmo tratamento:** pré-existente e **não** regressão da F —
`config/locales/devise.pt-BR.yml` não aparece em `git status` nesta branch, é byte-a-byte o de
`master@a2e95d3`. As chaves nunca estiveram lá. **Não corrigido aqui**, para não misturar conteúdo
pt-BR no diff do upgrade. Vira item próprio, junto com o §10.6 — e com prioridade maior que ele.

### 11.5 — Nota de método: `per_form_csrf_tokens` e o primeiro 422

A primeira tentativa do D3 devolveu **422 `InvalidAuthenticityToken`**, e **não era bug do app nem do
Devise** — era o cliente de teste. Registrado porque quem repetir estes comandos vai tropeçar no
mesmo:

O projeto roda com `per_form_csrf_tokens = true`, então **cada `<form>` tem um token próprio, escopado
ao par (path, método)**. Em `/users/edit` o **primeiro** form da página não é o de edição: é o
`button_to "Sair"` da navbar (`POST /users/sign_out`). Pegar "o primeiro `authenticity_token` do HTML"
entrega o token errado, válido só para o sign_out. O token certo é o do form `id="edit_user"`.

Nos passos anteriores o atalho não doeu por acaso: nas páginas de sign_in/sign_up o usuário está
deslogado (não há navbar com "Sair"), e no sign_out do §10.4 o token da navbar **era** o token certo.
**Um 422 é o sintoma esperado quando o token está errado** — o que significa que os passos que
devolveram 2xx/3xx não foram afetados por isso.

### 11.6 — Efeito colateral no banco de development

`confirmado@dev.local` **agora é `confirmado-novo@dev.local`** — a troca foi real e ficou. Consequências:

- Rodar `bin/rails runner db/seeds_users.rb` de novo **cria um `confirmado@dev.local` novo**, já que o
  arquivo casa por e-mail. O ambiente ficaria com dois usuários equivalentes, um deles sem endereço.
- O `reset_password_token` remanescente do trabalho perdido (§3.9) foi zerado pelo próprio `UPDATE` do
  D3 — some do banco como efeito da troca, não por limpeza deliberada.

**Deixado como está**, porque desfazer apagaria a evidência que esta seção documenta. Reverter, se for
o caso, é uma linha: `User.find(1).update!(email: "confirmado@dev.local")`.

---

## 12. Revisão do `config/initializers/devise.rb` sob o 5.0 (§7 passo 13)

Executado em 2026-08-18. O passo 13 previa "revisar só para registrar divergências; **não** adotar o
template novo". É o que segue.

### 12.1 — Comparação estrutural com o template do 5.0.4

Nomes de opção extraídos dos dois arquivos — o nosso e o
`devise-5.0.4/lib/generators/templates/devise.rb` da gem instalada:

```
NOSSO devise.rb : 13 opções ativas, 41 comentadas
TEMPLATE 5.0.4  : 13 opções ativas, 41 comentadas
```

| Pergunta | Resposta | Como foi verificado |
|---|---|---|
| Opção que usamos foi **removida ou renomeada** no 5.0? | **Nenhuma** | As 13 ativas respondem em `Devise` e constam do template 5.0.4 |
| Opção do template **ausente** do nosso arquivo? | **Nenhuma** | `(template) − (nosso) = ∅` |
| Opção nossa que **não existe mais** no template? | **Nenhuma** | `(nosso) − (template) = ∅` |
| Opção **nova** de segurança a adotar? | **Nenhuma existe** | Os dois arquivos têm o mesmo conjunto de 54 opções |

**As 13 opções que o template 5.0.4 mantém ativas são exatamente as 13 que ativamos** — não há
default novo para fixar explicitamente. As diferenças de texto restantes são: ERB do gerador
(`SecureRandom.hex(64)` em `secret_key` e `pepper`, `options[:orm]` no `require`), o `mailer_sender`
que é o nosso de verdade, um rename cosmético no exemplo comentado do Warden (`|manager|` →
`|warden_config|`), e três linhas de comentário novas sobre `send_email_changed_notification`.

### 12.2 — Os quatro pontos sensíveis

| Config | Estado | Evidência |
|---|---|---|
| `config.reconfirmable` | ✅ **ativo, `true`** (linha 160) | Runtime `Devise.reconfirmable = true`. É a config que a §11 validou |
| `config.secret_key` | ✅ **comentado** (linha 17) — deriva de `secret_key_base` | Digest SHA-256 de `Devise.secret_key` == digest de `secret_key_base` (`c31b4c0182b9`) |
| `config.paranoid` | comentado, runtime `false` | Sem mudança necessária |
| `config.mailer_sender` | ✅ `'TR AutoParts <trautoparts.suporte@gmail.com>'` | E-mail gerado traz `From: TR AutoParts <trautoparts.suporte@gmail.com>` |

**Sobre o `secret_key`:** é a confirmação final do §3.9. A remoção do `SecretKeyFinder` não nos atinge
porque **nunca setamos a opção** — e ela continua existindo no template do 5.0.4, com o mesmo texto. O
que mudou foi a cadeia interna de fallback, não a interface.

**Sobre o `mailer_sender`:** o `default from:` do `ApplicationMailer` não interfere, porque o
`Devise::Mailer` não herda dele — `config.mailer` e `config.parent_mailer` seguem comentados.

**Sobre o `paranoid`:** se um dia for ligado, as chaves `send_paranoid_instructions` adicionadas ao
`devise.pt-BR.yml` (§11.4) entram em uso automaticamente. Já estão lá.

### 12.3 — Divergência encontrada: `responder.error_status` (é do Rack, não do Devise)

Único ponto em que o nosso valor difere do que o template geraria hoje:

```ruby
# nosso (linha 305)
config.responder.error_status = :unprocessable_entity
# template 5.0.4
config.responder.error_status = <%= Rack::Utils::SYMBOL_TO_STATUS_CODE.key(422).inspect %>
```

Sob o Rack 3.2.7 desta app, esse ERB gera **`:unprocessable_content`**:

```
SYMBOL_TO_STATUS_CODE[:unprocessable_entity]   = nil
SYMBOL_TO_STATUS_CODE[:unprocessable_content]  = 422
Rack::Utils.status_code(:unprocessable_entity) = 422
  + warning: Status code :unprocessable_entity is deprecated and will be
             removed in a future version of Rack. Please use :unprocessable_content instead.
```

**Funciona hoje** — o Fluxo 1 inteiro devolveu 422 nos pontos certos (§10.5 C9, §11.2 D7 e D11). O
símbolo saiu do `SYMBOL_TO_STATUS_CODE` e sobrevive por um caminho de compatibilidade que o Rack já
anuncia que vai remover.

**Não é do Devise.** É herança do Rack 3.2, que entrou com a Etapa E; a revisão do initializer é só
onde apareceu. **Deixado para item próprio** (`TODO.md`), pelo mesmo critério que separou a tradução
pt-BR: mudança motivada por outra dependência não entra no commit do upgrade do Devise.

**Ponto cego que isso revelou:** o aviso é `Kernel#warn` do Rack, **não** um
`ActiveSupport::Deprecation`. O critério de aceite do §5 (`... | grep -c DEPRECATION` → `0`) **não o
captura**. Registrado no `LESSONS.md` — não é regressão daquela verificação, é limite dela.

### 12.4 — Veredito

**O `config/initializers/devise.rb` é compatível com o Devise 5.0.4 sem nenhuma mudança
obrigatória.** Nenhuma opção removida, nenhuma renomeada, nenhum default novo a fixar, nenhuma opção
de segurança nova disponível. O arquivo **não foi modificado** nesta etapa.

---

## Apêndice — comandos de verificação usados nesta investigação

Todos somente-leitura; nenhum modificou o repositório.

```bash
# Versões e metadados da gem
curl -s https://rubygems.org/api/v1/versions/devise.json
curl -s https://rubygems.org/api/v2/rubygems/devise/versions/5.0.4.json

# CHANGELOG e fonte do 5.0.x
curl -s https://raw.githubusercontent.com/heartcombo/devise/main/CHANGELOG.md
curl -s https://raw.githubusercontent.com/heartcombo/devise/main/lib/devise.rb
curl -s https://raw.githubusercontent.com/heartcombo/devise/main/lib/devise/rails/routes.rb
curl -s https://raw.githubusercontent.com/heartcombo/devise/v5.0.4/lib/devise/models/confirmable.rb
curl -s https://raw.githubusercontent.com/heartcombo/devise/v5.0.4/lib/devise/failure_app.rb

# Faixas das CVEs
curl -s https://api.github.com/advisories/GHSA-57hq-95w6-v4fc   # CVE-2026-32700
curl -s https://api.github.com/advisories/GHSA-jp94-3292-c3xv   # CVE-2026-40295

# Diff contra a gem instalada
diff -u "$(bundle show devise)/lib/devise/models/confirmable.rb" <5.0.4>
diff -u "$(bundle show devise)/lib/devise/failure_app.rb"        <5.0.4>

# Deprecations reais (test env imprime em stderr; development só loga)
RAILS_ENV=test bin/rails runner 'Rails.application.reload_routes_unless_loaded'

# Origem do secret_key, por digest (nunca o valor)
bin/rails runner '...Digest::SHA256.hexdigest(...)[0,12]...'
heroku config --app trscrews-prod          # apenas nomes
heroku config:get SECRET_KEY_BASE --app trscrews-prod | sha256sum
```
