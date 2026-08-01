# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# [SEC.29 / ARCH.77] Літеральні шляхи, що живуть у конфігах ОКРЕМО від роутера.
#
# Чому це взагалі потрібен окремий гейт, а не «просто спека на rack_attack»:
# Rack::Attack сидить у стеку ПЕРЕД роутером, тож його власні приклади дістають
# свій 429 навіть на шляху, якого не існує. Тобто зелений `rack_attack_spec`
# нічого не каже про те, чи правило досі націлене на живий маршрут — і один із
# них уже розійшовся (`reset_password` зареєстровано як PATCH, а правило читало
# лише POST, тож фінальний крок скидання пароля не лімітувався взагалі).
#
# ⚠️ ЧОГО ЦЕЙ ГЕЙТ НЕ БАЧИТЬ (стеля, названа явно — інакше зелений читається як
# «перевірено все»):
#   · `/assets`, `/up`, `/ready`, `/metrics` — не маршрути застосунку в тому
#     сенсі, що їх перехоплює middleware ДО роутера (Propshaft, PrometheusCollector)
#     або вони оголошені поза `namespace`. Для них джерело істини інше, і звірка
#     мусить бути окремою гілкою, а не цим проходом.
#   · Він доводить УЗГОДЖЕНІСТЬ конфігу з роутером, а не те, що throttle реально
#     зупиняє трафік — це інше твердження й інший приклад.
#   · 🔴 **Колонка `verbs` — рукописна деклАРАЦІЯ, а не вимір самого правила.** Гейт
#     звіряє її з РОУТЕРОМ, тож ловить «шлях помер» і «дієслово на шлях не
#     зареєстроване» — але не «правило читає не те дієслово, яке тут написано».
#     Тобто на founding-класі SEC.29 (шлях живий, правило дивиться на POST при
#     PATCH-маршруті) цей гейт був би ЗЕЛЕНИЙ. Дієслівну вісь доводить лише
#     поведінковий приклад у `spec/initializers/rack_attack_spec.rb`, і його треба
#     писати ОКРЕМО для кожного правила, чиє дієслово несуче.
#   · `recognize_path` доводить, що маршрут ОГОЛОШЕНО, а не що дія існує: сусідній
#     випадок того ж свіпу (`codex/admin` `new`/`edit`) резолвився роутером і
#     віддавав 404 з `ActionNotFound`.
#   · `config/deploy.yml` / `.kamal/**` читає Kamal поза Rails-процесом; сюди вони
#     не потрапляють за побудовою.
#
# 🔴 Реєстр нижче — curated map, тобто сам по собі tripwire: перевірка ПОВНОТИ
# (нижче) червоніє, щойно в `rack_attack.rb` зʼявляється throttle, якого тут
# немає. Без неї гейт мовчки перестав би бачити все нове — рівно та форма
# сліпоти, через яку curated-списки й вважають небезпечними.
#
# Кожен запис реєстру: конкретний ПРИКЛАД шляху (не патерн — роутер розпізнає
# конкретику) + дієслова, на які правило реагує. `verbs: nil` = правило дієслова
# не розрізняє, тож перевіряються всі.
THROTTLE_PATH_REGISTRY = {
  "req/ip" => { paths: [], verbs: nil },
  # [ARCH.77] Єдине правило, що накриває ОБИДВА контури: читання телеметрії шлюза
  # браузерне (корінь), запис — машинний (`/api/v1`). Обидві адреси перелічені
  # явно, бо ліміт стереже РЕСУРС; розвівши їх, ми подвоїли б стелю на ту саму
  # поверхню, і жоден приклад не почервонів би.
  "telemetry/uid" => {
    paths: %w[/trees/1/telemetry /gateways/1/telemetry /telemetry/live
              /provisioning/register /api/v1/gateways/1/telemetry],
    verbs: nil
  },
  "logins/ip" => {
    paths: %w[/login /forgot_password /reset_password],
    verbs: %w[POST PATCH]
  },
  # Правило матчить ПРЕФІКСОМ, тож накриває сімʼю підшляхів: базовий — GET-сторінка,
  # а мутації, заради яких throttle і стоїть, живуть глибше. Перелічуємо саме їх.
  "account_security/ip" => {
    paths: %w[/account_security/password /account_security/mfa],
    verbs: %w[PATCH DELETE]
  },
  # `/refresh` — окремий POST-маршрут ТІЄЇ САМОЇ Ed25519/DID-поверхні, тобто рівно
  # те, від чого правило й ставили. Доти реєстр його не знав, і фікс `==`→префікс
  # не мав жодного піна: мутація-реверт лишалась зеленою.
  "m2m_auth/ip" => {
    paths: %w[/api/v1/auth/m2m_token /api/v1/auth/m2m_token/refresh],
    verbs: %w[POST]
  },
  "oracle_callbacks/ip" => { paths: %w[/api/v1/oracle_callbacks], verbs: %w[POST] },
  "helium_sos/ip" => { paths: %w[/api/v1/telemetry/helium], verbs: %w[POST] },
  # Правило читає `post? || delete?`, і DELETE живе на ОКРЕМОМУ підшляху
  # (`.../attunements/me`) — реєстр доти казав лише POST, тобто брехав про
  # правило з дня народження. Обидві дії перелічені явно.
  "codex/attunements" => {
    paths: %w[/codex/nodes/some-slug/attunements /codex/nodes/some-slug/attunements/me],
    verbs: %w[POST DELETE]
  },
  "codex/comments" => { paths: %w[/codex/nodes/some-slug/comments], verbs: %w[POST] },
  "codex/fractions" => { paths: %w[/codex/fractions], verbs: %w[POST] },
  "codex/matches/create" => { paths: %w[/codex/matches], verbs: %w[POST] }
}.freeze

# Правило дієслова не розрізняє → перевіряємо всі, інакше дефолт `GET` червонив би
# POST-only шлях, тобто гейт бив би по власному дефолту, а не по коду.
ANY_VERB = %w[GET POST PATCH PUT DELETE].freeze

RSpec.describe "path literals vs router", type: :request do
  def route_exists?(path, verb)
    Rails.application.routes.recognize_path(path, method: verb)
    true
  rescue ActionController::RoutingError
    false
  end

  # Викликає САМ matcher правила, а не читає реєстр. `REMOTE_ADDR` обовʼязковий:
  # блок повертає `request.ip` як дискримінатор, тож без нього результат nil
  # завжди — проба «нічого не матчить» була б хибно-зеленою в обидва боки.
  def rule_fires?(name, path, verb)
    env = Rack::MockRequest.env_for(path, method: verb, "REMOTE_ADDR" => "203.0.113.7")
    !Rack::Attack.throttles.fetch(name).block.call(Rack::Attack::Request.new(env)).nil?
  end

  describe "повнота реєстру" do
    # Це і є носій: без нього новий throttle просто не потрапив би під нагляд, а
    # гейт лишався б зеленим — та сама сліпота, що й у гейта з власним хардкодом.
    it "жоден throttle не лишився поза наглядом" do
      expect(Rack::Attack.throttles.keys).to match_array(THROTTLE_PATH_REGISTRY.keys)
    end
  end

  describe "кожен літеральний шлях резолвиться роутером" do
    THROTTLE_PATH_REGISTRY.each do |name, config|
      config[:paths].each do |path|
        it "#{name}: #{path} існує принаймні для одного зі своїх дієслів" do
          verbs = config[:verbs] || ANY_VERB
          # `any?`, а не `all?`: правило може накривати сімʼю шляхів, з яких різні
          # приймають різні дієслова (`account_security` — PATCH і DELETE на РІЗНИХ
          # підшляхах). Несуче тут те, що шлях узагалі живий.
          expect(verbs.any? { |verb| route_exists?(path, verb) })
            .to be(true), "#{path} не резолвиться в роутері для #{verbs.join('/')}"
        end
      end
    end
  end

  # 🔴 ЦЕ — детектор founding-класу SEC.29, і він міряє САМЕ ПРАВИЛО, а не
  # колонку реєстру. Без нього гейт доводив би лише «шлях живий», тобто був би
  # зелений на дефекті, заради якого його поставили: `reset_password` існував
  # увесь час, а правило дивилось на POST при PATCH-маршруті.
  # 🔴 `verbs: nil` пробує КОЖНЕ дієслово, яке приймає роутер, — не літеральний
  # GET. Дефолт `%w[GET]` був сліпотою рівно на тому правилі, заради якого гейт
  # і оновлювався [ARCH.77]: обидва POST-шляхи `telemetry/uid` (машинний uplink
  # + `provisioning/register`) не породжували ЖОДНОГО прикладу, тож зняття
  # опційної префікс-групи з регексу лишало всю сюїту зеленою. Доведено
  # мутацією: без цього фіксу перереєстрація правила без `(?:/api/v1)?` —
  # 40 examples, 0 failures. Клас той самий, що founding-дефект SEC.29
  # («гейт міряв ДЕКЛАРАЦІЮ, не правило»), лише на сусідній осі: там брехала
  # колонка `verbs`, тут — дефолт, яким гейт її підміняв.
  def self.live_verbs_for(path, declared)
    (declared || ANY_VERB).select do |verb|
      Rails.application.routes.recognize_path(path, method: verb)
      true
    rescue ActionController::RoutingError
      false
    end
  end

  describe "правило реально спрацьовує на кожен свій шлях" do
    THROTTLE_PATH_REGISTRY.each do |name, config|
      config[:paths].each do |path|
        live_verbs_for(path, config[:verbs]).each do |verb|
          it "#{name}: #{verb} #{path}" do
            expect(rule_fires?(name, path, verb))
              .to be(true), "#{name} не матчить #{verb} #{path} — правило розійшлося з реєстром"
          end
        end
      end
    end
  end

  # Та сама вісь, але з боку роутера: шлях існує, правило матчить його регексом —
  # і мовчки не спрацьовує, бо дієслово інше.
  describe "дієслово правила збігається з маршрутом" do
    it "logins/ip накриває обидва дієслова ланцюга скидання пароля" do
      expect(route_exists?("/login", "POST")).to be(true)
      expect(route_exists?("/forgot_password", "POST")).to be(true)
      # Фінальний крок зареєстровано як PATCH — правило мусить читати і його.
      expect(route_exists?("/reset_password", "PATCH")).to be(true)
      expect(route_exists?("/reset_password", "POST")).to be(false)
    end
  end

  describe "IO-bound шляхи мідлвара" do
    MarkWeb3RequestsAsIoBound::IO_BOUND_PATHS.each do |path|
      it "#{path} існує для POST" do
        expect(route_exists?(path, MarkWeb3RequestsAsIoBound::IO_BOUND_METHOD)).to be(true)
      end
    end
  end
end
