# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# [I18N.2 · клас 2] Пара «фрейм ⟷ заглушка» — контракт, у якому кожна половина
# без іншої безглузда, тож перевіряються вони разом.
RSpec.describe Actuators::CommandStatusFrame do
  def build_command(id: 7, status: "acknowledged")
    # [TEST.12] Реальний незбережений `ActuatorCommand`: `status` тепер ходить через
    # справжній enum, тож значення поза набором (`issued`/`sent`/`acknowledged`/
    # `failed`/`confirmed`) тут неможливе — модель кидає `ArgumentError` у конструкторі.
    # `id` несучий: із нього будується адреса броадкасту (`command_status_{id}` у бейджі,
    # `CommandStatusFrame.dom_id` у фреймі), яку адресує `actuator_command_worker`.
    ActuatorCommand.new(id: id, status: status)
  end

  describe "page/response frame (no src)" do
    let(:html) { render_component(command: build_command) }

    it "wraps the badge in a turbo-frame carrying the broadcast target id" do
      expect(html).to include("command_status_frame_7")
      expect(html).to include("turbo-frame")
    end

    # Несуче, але не через «нескінченний цикл»: Turbo ловить self-referencing
    # `src`, пише `references itself` у консоль і лишає фрейм ПОРОЖНІМ. Тобто
    # регресія тут виглядає як назавжди порожня клітинка, а не як шторм запитів —
    # симптом тихий, і саме тому потрібен пін.
    it "carries no src attribute" do
      expect(html).not_to include("src=")
    end

    it "renders the localized badge inside" do
      localized = I18n.with_locale(:uk) { render_component(command: build_command) }

      expect(localized).to include("виконується")
    end

    # id фрейма ≠ id бейджа — інакше в DOM був би дубль.
    it "keeps the frame id distinct from the badge id it wraps" do
      expect(html).to include('id="command_status_frame_7"')
      expect(html).to include('id="command_status_7"')
    end
  end

  describe Actuators::CommandStatusFrameStub do
    let(:stub_html) do
      described_class.new(command_id: 7, src: "/actuator_commands/7").call
    end

    it "renders an eager turbo-frame with the same id and a src" do
      expect(stub_html).to include('id="command_status_frame_7"')
      expect(stub_html).to include('src="/actuator_commands/7"')
      expect(stub_html).to include('loading="eager"')
    end

    # Це і є весь сенс класу 2: payload той самий у будь-якій локалі, тож ціна
    # live-оновлення росте з ГЛЯДАЧАМИ, ніколи з каталогом мов (`04_04 §8.1а`).
    it "renders byte-identically in every configured locale" do
      renders = I18n.available_locales.map do |locale|
        I18n.with_locale(locale) { described_class.new(command_id: 7, src: "/x").call }
      end

      expect(renders.uniq.size).to eq(1)
    end

    # Раніше тут стояв пін «не містить слова статусу» — вакуумний: стаб не
    # отримує `command` взагалі, тож жодна досяжна мутація не могла б відрендерити
    # статус. Змістовна вісь інша: плейсхолдер мусить ТРИМАТИ МІСЦЕ бейджа, бо
    # порожній фрейм (перша версія) смикав висоту рядка на кожне оновлення.
    it "renders a placeholder that holds the badge's space" do
      expect(stub_html).to include("animate-pulse")
      expect(stub_html).to match(/\bw-\d+\b/)
      expect(stub_html).to match(/\bh-\d+\b/)
    end

    # Плейсхолдер тримає місце бейджа, але не має що сказати скрін-рідеру:
    # озвучувати порожнє очікування — шум, а текст зробив би payload локальним.
    it "hides the placeholder from assistive tech" do
      expect(stub_html).to include('aria-hidden="true"')
    end
  end
end
