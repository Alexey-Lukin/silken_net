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
RSpec.describe Views::Shared::UI::FlashMessages do
  describe "коли повідомлень немає" do
    let(:html) { render_component }

    it "все одно рендерить polite-регіон" do
      expect(html).to include('id="flash_notice"')
    end

    it "все одно рендерить assertive-регіон" do
      expect(html).to include('id="flash_alert"')
    end

    it "не малює жодної рамки повідомлення" do
      expect(html).not_to include("border-status-danger")
    end
  end

  describe "з notice" do
    let(:html) { render_component(messages: { "notice" => "Запис збережено." }) }

    it "рендерить текст" do
      expect(html).to include("Запис збережено.")
    end

    it "кладе його в polite-регіон, а не в assertive" do
      # Порядок у розмітці: assertive-регіон іде першим (KINDS), тож текст мусить
      # опинитись ПІСЛЯ `flash_notice`, а не після `flash_alert`.
      expect(html.index("Запис збережено.")).to be > html.index('id="flash_notice"')
    end

    it "має role=status (polite), бо підтвердження не сміє перебивати мовлення" do
      expect(html).to include('role="status"')
    end

    it "вживає токен поверхні, не сирий Tailwind" do
      expect(html).to include("bg-gaia-surface-sunken")
    end
  end

  describe "з alert" do
    let(:html) { render_component(messages: { "alert" => "Недостатньо прав." }) }

    it "рендерить текст" do
      expect(html).to include("Недостатньо прав.")
    end

    it "має role=alert — відмова МУСИТЬ перебити" do
      expect(html).to include('role="alert"')
    end

    it "має aria-live=assertive" do
      expect(html).to include('aria-live="assertive"')
    end

    it "вживає статусний токен небезпеки" do
      expect(html).to include("border-status-danger")
    end
  end

  describe "з обома одразу" do
    let(:html) { render_component(messages: { "notice" => "Збережено.", "alert" => "Але фото не додалось." }) }

    it "показує обидва" do
      expect(html).to include("Збережено.").and include("Але фото не додалось.")
    end
  end

  describe "нормалізація входу" do
    it "приймає символьні ключі — `flash` віддає їх по-різному залежно від того, хто ставив" do
      html = render_component(messages: { notice: "Символьний ключ." })
      expect(html).to include("Символьний ключ.")
    end

    it "мовчки ігнорує невідому категорію — для неї немає ані ролі, ані тону" do
      html = render_component(messages: { "toast" => "Категорії не існує." })
      expect(html).not_to include("Категорії не існує.")
    end

    it "не малює порожнього рядка як повідомлення" do
      html = render_component(messages: { "notice" => "" })
      expect(html).not_to include("bg-gaia-surface-sunken")
    end

    it "переживає nil замість хеша" do
      expect { render_component(messages: nil) }.not_to raise_error
    end
  end

  describe "доступність" do
    let(:html) { render_component(messages: { "notice" => "Готово." }) }

    it "обидва регіони atomic — читається все повідомлення, а не одна змінена фраза" do
      expect(html.scan('aria-atomic="true"').size).to eq(2)
    end

    it "контейнер не перехоплює кліки повз повідомлення" do
      expect(html).to include("pointer-events-none")
    end

    it "саме повідомлення клікабельне (текст можна виділити)" do
      expect(html).to include("pointer-events-auto")
    end
  end
end
