# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("spec/support/contrast_registry")

# [UI.1 ⚖️ знято] Повний AA-зріз ГРОШОВИХ і ОПЕРАЦІЙНИХ поверхонь — обома темами,
# чистим ратчетом.
#
# 🔴 Чому контур зʼявився саме тепер. Обидві черги (`money`/`ops`) стояли з `back:`
# «після ⚖️ про status-token refactor», тобто чекали присуду власника. Вимір
# 2026-08-21 показав, що присуд ВАКУУМНИЙ: рефактор уже відбувся двома чужими
# роботами — `-accent`-ярус завела UI.3 (пастельний токен робив індикатор
# невидимим), а сиру палітру вичерпала кампанія UI.1. Тобто розблокувала ці
# сторінки не подія, а вимір власної підстави.
#
# 🔴 Що знайшов ПЕРШИЙ прогін, і чому це варте запису: рівно ОДНА провальна пара
# на 40 сторінко-візитів — чіп `forest_coin`, у якого монетний токен стояв у
# ТЕКСТ-ролі на власній `/20`-підкладці (3.80 світла, 4.70 темна — на межі бару).
# Носіїв було ТРИ, а прилад побачив один: фабрика транзакції дає `carbon_coin`,
# тож на `wallets#show`/`blockchain_transactions#show` жовтий чіп просто не
# рендерився. Дефект виліз через ЛЕГЕНДУ `blockchain_transactions#index`, яка
# друкує всі три значення enum'а підряд. Це рівно та стеля, яку реєстр оголошує
# сам: контур бачить МАРШРУТИ, не ЕКРАНИ — фікстура вирішує, яка гілка стилю
# взагалі отримає шанс бути виміряною.
#
# 🔒 Стелі — ті самі, що в сусідніх контурів (`dashboard_contrast_spec` шапка):
# статичний знімок без псевдо-КЛАСІВ (`:hover`/`:focus-visible`/`:disabled`) ·
# маршрут ≠ усі його ЕКРАНИ · порожні стани фікстура наповнює мінімально.
#
# ⚠️ Актор — super_admin: `system_audits#index` стоїть за `authorize_admin!`, а
# для слабшого актора той самий шлях віддає `Errors::Page` — тобто вимір сторінки
# помилки при зеленому піні на шлях (пін ідентичності в `harvest_contrast` це
# ловить, але чесніше не провокувати).
RSpec.describe "[UI.1] Грошові й операційні сторінки тримають AA в обох темах", :js do
  let(:password)      { "money-ops-contrast-1" }
  let!(:organization) { create(:organization) }
  let!(:actor)        { create(:user, :super_admin, organization: organization, password: password) }
  let!(:cluster)      { create(:cluster, organization: organization) }
  let!(:tree)         { create(:tree, cluster: cluster) }
  let!(:gateway)      { create(:gateway, cluster: cluster) }
  let!(:wallet)       { create(:wallet, tree: tree) }
  let!(:transaction)  { create(:blockchain_transaction, wallet: wallet) }
  let!(:contract)     { create(:naas_contract, organization: organization, cluster: cluster) }
  let!(:alert)        { create(:ews_alert, cluster: cluster, tree: tree) }
  let!(:audit_log)    { create(:audit_log, user: actor, organization: organization) }
  let!(:record)       { create(:maintenance_record, user: actor, maintainable: tree) }
  let!(:insight)      { create(:ai_insight, analyzable: tree) }

  def pages
    ContrastRegistry.paths_for(:money_ops_sweep,
                               wallet: wallet, transaction: transaction, contract: contract,
                               alert: alert, audit_log: audit_log, record: record)
  end

  before { sign_in_as(actor, password: password) }

  # Один приклад на тему, не на сторінку: кожен `it` платить повний sign_in +
  # підйом браузера, а падіння тут і так називає КОЖНУ провальну пару поіменно
  # разом зі сторінкою — поіменні приклади не додали б діагностики, лише час.
  def sweep(theme)
    failures = []
    starved  = []

    pages.each do |path|
      harvest = harvest_contrast(path, theme: theme)

      # Ліхтар вакууму: сторінка без ЖОДНОЇ пари — це не «чисто», це «прилад
      # нічого не побачив» (редирект, порожній рендер, зламаний збирач).
      starved << path if harvest[:pairs].empty?

      harvest[:pairs].reject(&:passes).each do |pair|
        failures << format(
          "%-42s %5.2f < %.1f  %s",
          path, pair.ratio || 0, pair.threshold, pair.sample_path
        )
      end
    end

    expect(starved).to be_empty,
                       "сторінки без жодної виміряної пари (вимір недійсний): #{starved.join(', ')}"

    expect(failures).to be_empty, <<~MSG
      Провальні AA-пари (#{theme}):

      #{failures.join("\n")}
    MSG
  end

  %i[light dark].each do |theme|
    # rubocop:disable RSpec/NoExpectationExample -- обидва expect живуть у
    # `sweep` (спільні для чотирьох прикладів); статичний коп у хелпер не ходить.
    it "нуль провальних AA-пар у #{theme}-темі на всіх сторінках контуру" do
      sweep(theme)
    end
    # rubocop:enable RSpec/NoExpectationExample

    # Card-flip таблиці цих сторінок (леджер · журнал аудиту · записи
    # обслуговування) міняють РОЗМІТКУ на телефоні: `td::before` стає єдиним
    # носієм назви колонки, і прилад міряє його третім проходом. Тобто це не
    # повтор десктопного зрізу, а власна популяція вузлів.
    it "нуль провальних AA-пар у #{theme}-темі на мобільному вʼюпорті (390×844)" do
      page.driver.resize(390, 844)
      # Ліхтар на САМ resize: якби виклик мовчки не спрацював, сторінки дали б
      # ті самі десктопні пари, і «мобільний зріз» атестував би десктоп під
      # чужим іменем («я налаштував у before» — заява про код, не про систему).
      visit "/dashboard"
      expect(page.evaluate_script("window.innerWidth")).to eq(390)

      sweep(theme)
    ensure
      page.driver.resize(1440, 900)
    end
  end
end
