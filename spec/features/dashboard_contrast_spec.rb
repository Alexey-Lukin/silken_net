# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("spec/support/contrast_registry")

# [UI.1 порція 11] Повний AA-зріз порцелянових сторінок флоту й адмінки —
# ОБОМА темами, чистим ратчетом.
#
# 🔴 Чому цей контур зʼявився саме тепер, а не раніше: хвилі `fleet` і `admin`
# реєстру стояли з `back:` «щойно міграція теми дійде сюди» — міряти ДО неї
# означало б пінити числа, які кампанія міняє. 2026-08-20 кампанію сирої
# палітри вичерпано (десять порцій, периметр гейта = весь view-шар), тож
# контур заходить БЕЗ реєстру винятків: нуль провальних пар, і регресія
# будь-якої сторінки червонить поіменно з парою «токен × поверхня».
#
# 🔒 Стелі — ті самі, що в сусідніх контурів (`root_tokens` шапка): статичний
# знімок без `:hover`-станів · маршрут ≠ усі його ЕКРАНИ (порожні стани
# фікстура наповнює мінімально, не вичерпно). Розмірів вікна ДВА — десктоп і
# мобільний 390×844 (закрив residual `UI.3`; card-flip дає власну популяцію
# вузлів через `td::before`).
#
# ⚠️ Актор — super_admin НЕ з примхи: `tree_families#*` і `organizations#*`
# гейтовані `authorize_super_admin!`, а для слабшого актора той самий шлях
# віддає `Errors::Page` — тобто вимір сторінки помилки при зеленому піні на
# шлях (пін ідентичності в `harvest_contrast` це ловить, але чесніше не
# провокувати). Досяжність РЕШТИ сторінок для admin/forester — інша вісь
# (авторизація), не контраст.
RSpec.describe "[UI.1] Дашборд-сторінки тримають AA в обох темах", :js do
  let(:password)      { "dashboard-contrast-1" }
  let!(:organization) { create(:organization) }
  let!(:actor)        { create(:user, :super_admin, organization: organization, password: password) }
  let!(:member)       { create(:user, :forester, organization: organization) }
  let!(:cluster)      { create(:cluster, organization: organization) }
  let!(:tree)         { create(:tree, cluster: cluster) }
  let!(:gateway)      { create(:gateway, cluster: cluster) }
  let!(:actuator)     { create(:actuator, cluster: cluster) }
  let!(:tree_family)  { create(:tree_family) }
  let!(:firmware)     { create(:bio_contract_firmware) }

  def pages
    ContrastRegistry.paths_for(:dashboard_sweep,
                               cluster: cluster, gateway: gateway, actuator: actuator,
                               tree_family: tree_family, organization: organization, member: member)
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
          "%-38s %5.2f < %.1f  %s",
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

    # [UI.3 → закрито тут] Мобільний контур — ⚖️ 08-20 відкладав його «до
    # закриття кампанії UI.1»; тригер настав того ж дня. Той самий цикл на
    # вʼюпорті телефона: card-flip таблиці міняють РОЗМІТКУ (td::before стає
    # єдиним носієм назви колонки — третій прохід приладу його міряє), тож це
    # не повтор десктопного зрізу, а власна популяція вузлів.
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
