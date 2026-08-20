# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# [UI.3, ⚖️ founder 2026-08-20] ADVISORY axe-прогін — ЛІНЗА, не гейт.
#
# Присуд дослівно: контраст уже тримають три власні браузерні контури (сильніші
# за axe для двотемності — axe міряє одну тему за прогін), тож axe додає РЕШТУ
# правил (ARIA-звʼязність, ролі, імена, структура); знахідки ТРІАЖАТЬСЯ в
# трекер, per-вісь точкові HARD-гейти народжуються як досі (motion_discriminator
# · opacity_contrast · label_association — прецеденти цієї ж форми). HARD-форма
# відхилена присудом: народилась би червоною з реєстром винятків.
#
# ЗАПУСК (дефолтний прогін і CI цю спеку НЕ бачать — тег вимкнено в
# `rails_helper`):
#
#     COVERAGE=0 bin/rspec spec/features/axe_audit_spec.rb --tag advisory
#
# Advisory-семантика: приклади ПАДАЮТЬ на знахідках — це і є звіт для тріажу
# (повідомлення називає сторінку, правило, impact і вузли). «Зелено» тут
# означає «на цих сторінках ці правила ніщо не порушує», не «доступність
# доведена».
#
# 🔴 ЧОМУ ВЛАСНИЙ ВИКЛИК, А НЕ `be_axe_clean` ГЕМА — виміряно, не смак:
# matcher axe-core-api 4.13 на Cuprite мертвий ОБОМА своїми шляхами. Новий
# (`analyze_post_43x`) кличе `driver.manage.timeouts` — selenium-API, якого в
# Ferrum немає (NoMethodError `manage`); legacy (`Configuration.legacy_mode`)
# іде через `execute_async_script_fixed`, який ЗАВЖДИ пробиває крізь адаптер до
# `page.driver.browser.execute_async_script` — імені, якого Cuprite::Browser не
# має. Duck-typing адаптера чистий лише на evaluate_script-пробах; сам аудит —
# ні. Гем лишається НОСІЄМ axe.min.js: версія JS їде атомарно з `bundle update`
# (Configuration#jslib_path), що й було головним аргументом проти vendoring.
#
# 🔒 Стелі, кожна названа свідомо:
#   · ОДНА тема за прогін — headless-дефолт (light). ARIA/ролі/імена/структура
#     тем-незалежні; двотемний контраст тримають власні контури.
#   · `color-contrast` ВИМКНЕНО в options: вісь уже виміряна власними контурами
#     (`contrast_registry` — популяція, `contrast_audit` — числа), і axe міряв
#     би її в одній темі, тобто слабше за наявний прилад.
#   · Популяція = контури `ContrastRegistry` (деривація з `routes.rb` живе там;
#     сторінки ХВИЛЬ сюди не входять, доки їхня хвиля не виміряна).
#   · Розмір вікна один (1440×900) — мобільна розмітка має власну (card-flip
#     `td::before`) і чекає свого контуру (🔗 за UI.1-кампанією).
require "rails_helper"
require "axe/configuration"

RSpec.describe "axe advisory audit", :advisory, :js, type: :feature do
  # Метод, не константа: LeakyConstantDeclaration — describe-блок не є
  # неймспейсом, константа втекла б у глобальний скоуп.
  def rule_tags = %w[wcag2a wcag2aa wcag21a wcag21aa]

  let(:organization) { create(:organization) }
  let(:cluster) { create(:cluster, organization: organization) }
  let(:tree) { create(:tree, cluster: cluster) }
  let(:admin) do
    create(:user, role: :admin, organization: organization,
                  password: "Str0ng!Passw0rd", password_confirmation: "Str0ng!Passw0rd")
  end

  # Інжект + запуск + poll: та сама форма, що польові зонди `contrast_audit`
  # (promise → window-змінна → evaluate_script-очікування). `runOnly` за тегами,
  # `color-contrast` вимкнено (стеля в шапці).
  def run_axe
    page.execute_script(File.read(Axe::Configuration.instance.jslib_path)) unless page.evaluate_script("!!window.axe")
    page.execute_script(<<~JS)
      window.__axeDone = null;
      axe.run(document, {
        runOnly: { type: "tag", values: #{rule_tags.to_json} },
        rules: { "color-contrast": { enabled: false } }
      }).then(function(res) {
        window.__axeDone = { violations: res.violations.map(function(v) {
          return { id: v.id, impact: v.impact, help: v.help,
                   nodes: v.nodes.slice(0, 5).map(function(n) { return n.target.join(" "); }),
                   count: v.nodes.length };
        }), rulesRan: res.passes.length + res.violations.length + res.incomplete.length + res.inapplicable.length };
      }).catch(function(e) { window.__axeDone = { error: String(e) }; });
    JS
    result = nil
    20.times do
      result = page.evaluate_script("window.__axeDone")
      break if result
      sleep 0.25
    end
    raise "axe did not finish on #{page.current_path}" if result.nil?
    raise "axe errored: #{result['error']}" if result["error"]

    result
  end

  # Збирає знахідки сторінки; падіння — ОДНЕ на контур (наприкінці циклу),
  # інакше перша брудна сторінка ховала б решту контуру від тріажу.
  def audit(path, findings)
    result = run_axe
    # Ліхтар живості на КОЖНІЙ сторінці (§Guard-craft #47): «нуль порушень»
    # означає «чисто» лише коли правила ВИКОНАЛИСЬ — нульовий rulesRan значив
    # би, що axe не бачив документа, і зелений колір брехав би.
    expect(result["rulesRan"]).to be > 50, "axe ran #{result['rulesRan']} rules on #{path} — інжект не відбувся?"
    result["violations"].each do |v|
      findings << ("#{path}\n  [#{v['impact']}] #{v['id']} — #{v['help']} (#{v['count']} node(s)):\n" +
        v["nodes"].map { |n| "    #{n}" }.join("\n"))
    end
  end

  def expect_no_findings(findings)
    expect(findings).to be_empty,
      "axe findings — тріаж у 00_07 UI.3:\n#{findings.join("\n")}"
  end

  describe "dashboard contour (root_tokens pages)" do
    before { sign_in_as(admin, password: "Str0ng!Passw0rd") }

    it "audits every measured dashboard page of the contour" do
      ctx = { cluster: cluster, tree: tree }
      findings = []
      ContrastRegistry.paths_for(:root_tokens, ctx).each do |path|
        visit_ok path
        audit(path, findings)
      end
      expect_no_findings(findings)
    end
  end

  describe "auth contour (pre-authentication pages)" do
    it "audits the login and password pages" do
      token = admin.generate_token_for(:password_reset)
      ctx = { reset_token: token }
      findings = []
      ContrastRegistry.paths_for(:auth, ctx).each do |path|
        visit path # без visit_ok: до-auth контур, сторінки легально 200/401
        audit(path, findings)
      end
      expect_no_findings(findings)
    end
  end
end
