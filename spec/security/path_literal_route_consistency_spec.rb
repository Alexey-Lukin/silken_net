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
  "telemetry/uid" => {
    paths: %w[/api/v1/trees/1/telemetry /api/v1/gateways/1/telemetry /api/v1/telemetry/live
              /api/v1/provisioning/register],
    verbs: nil
  },
  "logins/ip" => {
    paths: %w[/api/v1/login /api/v1/forgot_password /api/v1/reset_password],
    verbs: %w[POST PATCH]
  },
  # Правило матчить ПРЕФІКСОМ, тож накриває сімʼю підшляхів: базовий — GET-сторінка,
  # а мутації, заради яких throttle і стоїть, живуть глибше. Перелічуємо саме їх.
  "account_security/ip" => {
    paths: %w[/api/v1/account_security/password /api/v1/account_security/mfa],
    verbs: %w[PATCH DELETE]
  },
  "m2m_auth/ip" => { paths: %w[/api/v1/auth/m2m_token], verbs: %w[POST] },
  "oracle_callbacks/ip" => { paths: %w[/api/v1/oracle_callbacks], verbs: %w[POST] },
  "helium_sos/ip" => { paths: %w[/api/v1/telemetry/helium], verbs: %w[POST] },
  "codex/attunements" => { paths: %w[/api/v1/codex/nodes/some-slug/attunements], verbs: %w[POST] },
  "codex/comments" => { paths: %w[/api/v1/codex/nodes/some-slug/comments], verbs: %w[POST] },
  "codex/fractions" => { paths: %w[/api/v1/codex/fractions], verbs: %w[POST] },
  "codex/matches/create" => { paths: %w[/api/v1/codex/matches], verbs: %w[POST] }
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

  # 🔴 Саме та вісь, на якій розійшовся `reset_password`: шлях існує, правило
  # матчить його регексом — і мовчки не спрацьовує, бо дієслово інше.
  describe "дієслово правила збігається з маршрутом" do
    it "logins/ip накриває обидва дієслова ланцюга скидання пароля" do
      expect(route_exists?("/api/v1/login", "POST")).to be(true)
      expect(route_exists?("/api/v1/forgot_password", "POST")).to be(true)
      # Фінальний крок зареєстровано як PATCH — правило мусить читати і його.
      expect(route_exists?("/api/v1/reset_password", "PATCH")).to be(true)
      expect(route_exists?("/api/v1/reset_password", "POST")).to be(false)
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
