# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# [SEC.25] Пін на поверхню, якої в застосунку не було.
#
# ⚠️ Найважливіше твердження тут — НЕ «текст рендериться», а «обидва регіони
# присутні НАВІТЬ порожні». Це не косметика: скрінрідер не оголошує live-region,
# вставлений у DOM разом зі своїм вмістом, тож регіон, що з'являється лише за
# наявності повідомлення, не оголосив би нічого — і жоден візуальний тест цього
# не спіймав би, бо на екрані все виглядало б правильно.
#
# 🔴 Друге за вагою — «категорій чотири, регіонів два». Перевіряти треба саме
# РОЗПОДІЛ: категорія, що поїхала не в той регіон, виглядає нормально й ламає
# лише озвучення. Позиційна форма піна (індекс тексту проти індексу
# `id="flash_polite"`) працює рівно тому, що assertive-регіон іде в DOM першим —
# інакше вона була б тавтологією, бо текст завжди після свого ж регіону.
RSpec.describe Views::Shared::UI::FlashMessages do
  # Позиція `flash_polite` ділить документ навпіл: усе, що до неї — assertive.
  def region_boundary(html) = html.index('id="flash_polite"')

  describe "коли повідомлень немає" do
    let(:html) { render_component }

    it "все одно рендерить assertive-регіон" do
      expect(html).to include('id="flash_assertive"')
    end

    it "все одно рендерить polite-регіон" do
      expect(html).to include('id="flash_polite"')
    end

    it "не малює жодної рамки повідомлення" do
      expect(html).not_to include("border-status-danger")
    end
  end

  describe "розподіл категорій по регіонах" do
    it "error їде в assertive — відмова МУСИТЬ перебити мовлення" do
      html = render_component(messages: { "error" => "Недостатньо прав." })
      expect(html.index("Недостатньо прав.")).to be < region_boundary(html)
    end

    it "security їде в assertive — зміну безпекового стану треба почути" do
      html = render_component(messages: { "security" => "Інші сесії завершено." })
      expect(html.index("Інші сесії завершено.")).to be < region_boundary(html)
    end

    it "success їде в polite — підтвердження не сміє перебивати" do
      html = render_component(messages: { "success" => "Запис збережено." })
      expect(html.index("Запис збережено.")).to be > region_boundary(html)
    end

    it "pending їде в polite — «прийнято, чекаємо» теж не терміново" do
      html = render_component(messages: { "pending" => "Поставлено в чергу." })
      expect(html.index("Поставлено в чергу.")).to be > region_boundary(html)
    end
  end

  describe "дві категорії в ОДНОМУ регіоні" do
    # 🔴 Регресія, можлива лише після розширення 2→4: регіон, що читає ОДНЕ
    # значення, мовчки з'їдає друге повідомлення. `flash` за побудовою може нести
    # і змете з попереднього запиту, і поставлене в поточному.
    it "показує обидві polite-категорії, а не лише першу" do
      html = render_component(messages: { "success" => "Збережено.", "pending" => "Лист у черзі." })
      expect(html).to include("Збережено.").and include("Лист у черзі.")
    end

    it "показує обидві assertive-категорії" do
      html = render_component(messages: { "error" => "Не збережено.", "security" => "Пароль змінено." })
      expect(html).to include("Не збережено.").and include("Пароль змінено.")
    end
  end

  describe "консистентність мап" do
    # 🔴 Дві мапи (склад регіонів ⊥ тони) можуть розійтися тихо, і саме в той бік,
    # від якого будувалась поверхня: категорія без тону падає `KeyError` при
    # рендері, категорія без регіону не рендериться взагалі. Жоден приклад нижче
    # цього не побачив би — вони всі ходять по ВІДОМИХ категоріях.
    it "кожна категорія регіону має тон, і зайвих тонів немає" do
      expect(described_class::KNOWN_KINDS.sort).to eq(described_class::TONES.keys.sort)
    end
  end

  describe "тон на категорію" do
    it "error — небезпека" do
      expect(render_component(messages: { "error" => "х" })).to include("border-status-danger")
    end

    it "security — застереження, НЕ помилка: безпекова подія не є збоєм" do
      expect(render_component(messages: { "security" => "х" })).to include("border-status-warning")
    end

    it "success — успіх" do
      expect(render_component(messages: { "success" => "х" })).to include("border-status-success")
    end

    it "pending — нейтральна інформація" do
      expect(render_component(messages: { "pending" => "х" })).to include("border-status-info")
    end
  end

  describe "нормалізація входу" do
    it "приймає символьні ключі — `flash` віддає їх по-різному залежно від того, хто ставив" do
      html = render_component(messages: { success: "Символьний ключ." })
      expect(html).to include("Символьний ключ.")
    end

    it "мовчки ігнорує невідому категорію — для неї немає ані регіону, ані тону" do
      html = render_component(messages: { "toast" => "Категорії не існує." })
      expect(html).not_to include("Категорії не існує.")
    end

    # ⚠️ Старі імена мусять бути саме НЕВІДОМИМИ: якби вони лишились у мапі як
    # аліаси, недомігрований сайт рендерився б і далі, і міграцію неможливо було б
    # довести завершеною.
    it "старі категорії `notice`/`alert` більше не існують" do
      html = render_component(messages: { "notice" => "Старе.", "alert" => "Теж старе." })
      expect(html).not_to include("Старе.")
      expect(html).not_to include("Теж старе.")
    end

    it "не малює порожнього рядка як повідомлення" do
      html = render_component(messages: { "success" => "" })
      expect(html).not_to include("border-status-success")
    end

    it "переживає nil замість хеша" do
      expect { render_component(messages: nil) }.not_to raise_error
    end
  end

  describe "доступність" do
    let(:html) { render_component(messages: { "success" => "Готово." }) }

    it "рівно два live-regions — категорій чотири, але оголошень мусить лишитись два" do
      expect(html.scan('aria-atomic="true"').size).to eq(2)
    end

    it "assertive-регіон має role=alert" do
      expect(html).to include('role="alert"').and include('aria-live="assertive"')
    end

    it "polite-регіон має role=status" do
      expect(html).to include('role="status"').and include('aria-live="polite"')
    end

    it "контейнер не перехоплює кліки повз повідомлення" do
      expect(html).to include("pointer-events-none")
    end

    it "саме повідомлення клікабельне (текст можна виділити)" do
      expect(html).to include("pointer-events-auto")
    end
  end
end
