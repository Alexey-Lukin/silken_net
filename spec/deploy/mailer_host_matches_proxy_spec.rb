# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "spec_helper"
require "yaml"
require_relative "../support/repo_root"

# [ARCH.60 · INF.25] Один факт — «де відповідає веб-застосунок» — має ДВА доми в
# деплой-конфігу, і доти оновлювався лише один.
#
#   · `proxy.host`  — куди kamal-proxy приймає запити (де застосунок ВІДПОВІДАЄ);
#   · `env.clear.APP_HOST` — хост УСЕРЕДИНІ тіла листа
#     (`config/environments/production.rb` → `action_mailer.default_url_options`).
#
# Припис уже стояв написаним у `config/deploy.yml` рядком ВИЩЕ самого значення:
# «links in auth mail must land where the web app answers, or host-authorization
# 403s them». Canopy його порушував: `proxy.host` = `canopy.silkennet.app`,
# а `APP_HOST` мовчки успадковувався з бази — `silkennet.app`.
#
# 🔴 Чому це не косметика і чому носій потрібен саме тут. Дефект ЛАТЕНТНИЙ, доки
# пошта вимкнена (`SILKENNET_SKIP_MAIL_TRANSPORT_CHECK`), тобто прокинеться в той
# самий день, коли задротують ESP — і симптом («reset-лінк не працює») стоятиме за
# два кроки від причини: токен не звалідується на чужому слоті взагалі, бо там інша
# база й інший `password_salt`. Виміряно 2026-09-06: `canopy.silkennet.app` → 200,
# `silkennet.app` → 525.
#
# ⊕ Форма взята з `coap_host_consistency_spec` (INF.4): якір на ДЖЕРЕЛІ, без
# зашитого очікуваного значення, тож дрейф в обидва боки червонить однаково.
#
# 🔒 Оголошені стелі:
#   · Судиться РІВНІСТЬ двох оголошених значень, ніколи досяжність хоста. Обидва
#     можуть указувати в нікуди й пройти.
#   · Периметр — committed YAML. Значення, підставлене оператором у рантаймі
#     (`ENV`), сюди не входить за побудовою.
#   · Успадкування рахується так само, як його рахує Kamal: файл призначення
#     МЕРДЖИТЬСЯ поверх бази, тож відсутній ключ означає базове значення — і саме
#     ця мовчазна форма й була дефектом.
# â ï¸ ÐÐµÑÐ¾Ð´Ð¸ ÑÐ°Ð¹Ð»Ð¾Ð²Ð¾Ð³Ð¾ ÑÑÐ²Ð½Ñ, Ð° Ð½Ðµ Ð»Ð¾ÐºÐ°Ð»ÑÐ½Ñ Ð·Ð¼ÑÐ½Ð½Ñ ÑÑÐ»Ð° `describe`:
# `RSpec/LeakyLocalVariable` Ð·Ð°Ð±Ð¾ÑÐ¾Ð½ÑÑ ÑÐ¸ÑÐ°ÑÐ¸ ÑÐ°ÐºÑ Ð»Ð¾ÐºÐ°Ð»ÑÐ½Ñ Ð²ÑÐµÑÐµÐ´Ð¸Ð½Ñ Ð¿ÑÐ¸ÐºÐ»Ð°Ð´ÑÐ²,
# Ñ Ð·Ð°Ð±Ð¾ÑÐ¾Ð½Ð° Ð¿Ð¾ ÑÑÑÑ â Ð»Ð¾ÐºÐ°Ð»ÑÐ½Ð° Ð·Ð¼ÑÐ½Ð½Ð° ÑÑÐ»Ð° Ð³ÑÑÐ¿Ð¸ Ð¾Ð±ÑÐ¸ÑÐ»ÑÑÑÑÑÑ ÐÐÐÐ ÑÐ°Ð· Ð¿ÑÐ¸
# Ð·Ð°Ð²Ð°Ð½ÑÐ°Ð¶ÐµÐ½Ð½Ñ ÑÐ°Ð¹Ð»Ñ, ÑÐ¾Ð±ÑÐ¾ Ð¿ÑÐ¸ÐºÐ»Ð°Ð´ Ð¼Ð¾Ð²ÑÐºÐ¸ Ð·Ð°Ð»ÐµÐ¶Ð¸ÑÑ Ð²ÑÐ´ ÑÑÐ°Ð½Ñ, ÑÐºÐ¾Ð³Ð¾ Ð½Ðµ Ð±Ð°ÑÐ¸ÑÑ.
def deploy_config_paths
  Dir.glob(REPO_ROOT.join("config/deploy*.yml")).sort
end

def repo_relative(path)
  path.sub("#{REPO_ROOT}/", "")
end

def base_deploy_config
  YAML.load_file(REPO_ROOT.join("config/deploy.yml"), aliases: true)
end

RSpec.describe "mailer host ⇔ proxy host (ARCH.60/INF.25)" do # rubocop:disable RSpec/DescribeClass
  it "guards more than one deploy destination" do
    found = deploy_config_paths.size
    expect(found).to be >= 2,
                     "знайдено #{found} деплой-конфіг(ів) — периметр зламався, і зелений нижче був би твердженням про ПРИЛАД, а не про дерево"
  end

  deploy_config_paths.each do |path|
    it "#{repo_relative(path)}: APP_HOST == proxy.host" do
      rel  = repo_relative(path)
      cfg  = YAML.load_file(path, aliases: true)
      base = base_deploy_config

      proxy_host = cfg.dig("proxy", "host") || base.dig("proxy", "host")
      app_host   = cfg.dig("env", "clear", "APP_HOST") || base.dig("env", "clear", "APP_HOST")

      # ⚠️ НЕ `be_present`: ці спеки їдуть на `spec_helper` БЕЗ Rails, тож
      # ActiveSupport-предикатів тут немає. Перша редакція гейта червоніла на
      # ОБОХ конфігах саме через це — тобто повідомляла про дрейф там,
      # де його не було. Хибний позитив, породжений самим приладом.
      expect(proxy_host.to_s).not_to be_empty, "#{rel}: `proxy.host` не оголошено ані тут, ані в базі"

      expect(app_host).to eq(proxy_host), <<~MSG
        #{rel}: лист повів би читача НЕ туди, де відповідає застосунок.
          proxy.host          = #{proxy_host.inspect}   ← де застосунок ВІДПОВІДАЄ
          env.clear.APP_HOST  = #{app_host.inspect}   ← що піде В ТІЛО ЛИСТА
        Припис — `config/deploy.yml`, коментар над `APP_HOST`.
        Якщо призначення має власний `proxy.host`, воно мусить оголосити І власний
        `APP_HOST`: успадкування з бази тут і є дефектом, бо воно ТИХЕ.
      MSG
    end
  end
end
