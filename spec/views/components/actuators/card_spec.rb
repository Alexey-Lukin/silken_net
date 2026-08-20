# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Actuators::Card do
  # 🔴 `commands` НАВМИСНО вибухає. Доти фікстура віддавала `OpenStruct.new(last: nil)`
  # — вона існувала рівно для того, щоб обслужити фолбек `@actuator.commands.last`
  # у конструкторі, тобто описувала світ, у якому запит із Phlex-`initialize`
  # виглядає нормою (`04_04 §6.4` це забороняє). Тепер картка дані ЛИШЕ приймає,
  # і будь-яке повернення фолбека червонить кожен приклад цього файлу.
  # [TEST.12] Реальний незбережений `Actuator`: `device_type` тепер ходить через
  # справжній enum, тож вигадане `"valve"` тут неможливе — модель приймає лише
  # `water_valve`/`fire_siren`/`seismic_beacon`/`drone_launcher`. Це не косметика:
  # картка друкує водяний знак із ПЕРШИХ ТРЬОХ літер, тож спека пінила трибуквений
  # код, якого в проді не буває.
  #
  # ⚠️ `commands` навмисно лишається пасткою, і саме тому стабиться на РЕАЛЬНОМУ
  # записі, а не зникає разом із моком: асоціація існує, і якби картка добирала
  # команди сама, конверсія тихо зняла б цей захист (`04_04 §6.4`).
  def build_actuator(id: 1, device_type: :water_valve, state: :active, gateway_uid: "QUEEN-01")
    actuator = Actuator.new(id: id, device_type: device_type, state: state, gateway: Gateway.new(uid: gateway_uid))
    actuator.define_singleton_method(:commands) do
      Object.new.tap do |o|
        o.define_singleton_method(:last) { raise "Actuators::Card не сміє добирати команди — їх подає викликач" }
      end
    end
    actuator
  end

  # 🔴 [TEST.12] `id` тут НЕСУЧИЙ, а не косметика: `CommandStatusBadge` будує з нього
  # `id="command_status_{id}"`, і саме ця адреса є broadcast-таргетом
  # (`actuator_command_worker`). Мок без `id` давав `command_status_` без суфікса —
  # тобто спека пінила адресу, у яку жодне живе оновлення не влучить. У проді
  # недосяжно (`last_command` завжди persisted), але саме тому пін мусить стояти на
  # формі, яку прод справді дає.
  def build_command(id: 7, status: :confirmed)
    ActuatorCommand.new(id: id, status: status)
  end

  describe "rendering" do
    let(:html) { render_component(actuator: build_actuator) }

    it "renders the actuator id in the element id" do
      expect(html).to include("actuator_1")
    end

    # 🔴 [I18N.1] Твердження живе в НЕ-базовій локалі навмисно: в англійській мітка й
    # сирий токен розрізняються слабко, а в українській вони не мають нічого спільного —
    # тобто саме тут пін здатен упасти. Негативна половина обовʼязкова: без неї регресія
    # на сире значення enum'а лишалась би зеленою (`04_06 §A.2`).
    it "displays the device type as a human label, never the raw enum token" do
      I18n.with_locale(:uk) do
        localized = render_component(actuator: build_actuator)

        expect(localized).to include("Клапан поливу")
        expect(localized).not_to include("water_valve")
      end
    end

    it "displays the gateway UID in the header" do
      expect(html).to include("QUEEN-01")
    end
  end

  describe "status LED" do
    it "renders emerald glow for active state" do
      html = render_component(actuator: build_actuator(state: "active"))
      expect(html).to include("bg-gaia-primary-strong")
    end

    it "renders red pulse for maintenance_needed state" do
      html = render_component(actuator: build_actuator(state: "maintenance_needed"))
      expect(html).to include("bg-status-danger-accent")
      expect(html).to include("animate-pulse")
    end

    it "renders dark red for offline state" do
      html = render_component(actuator: build_actuator(state: "offline"))
      expect(html).to include("bg-status-danger-accent")
    end

    # ⚠️ Вхід досяжний ЛИШЕ стабом ридера: `state` — справжній enum, тож
    # `Actuator.new(state: "unknown")` кидає `ArgumentError` просто в конструкторі.
    # Доти цю гілку «перевіряло» значення, якого в проді не буває.
    it "renders gray for an unrecognised state" do
      actuator = build_actuator
      allow(actuator).to receive(:state).and_return("unknown")

      html = render_component(actuator: actuator)
      expect(html).to include("bg-status-neutral-accent")
    end
  end

  describe "status matrix" do
    it "displays the physical state" do
      html = render_component(actuator: build_actuator(state: "active"))
      expect(html).to include("Physical State:")
      expect(html).to include("active")
    end

    it "displays last command status" do
      html = render_component(actuator: build_actuator, last_command: build_command(status: "confirmed"))
      expect(html).to include("confirmed")
    end

    # 🔴 Адреса бейджа — це broadcast-ТАРГЕТ (`actuator_command_worker` шле саме сюди),
    # тож суфікс несучий: доти мок не давав `id`, і спека пінила `command_status_`
    # без нього — форму, у яку жодне живе оновлення не влучає. Без цього прикладу
    # конверсія фікстури оборотна мовчки.
    it "renders the status badge at the id the broadcast actually targets" do
      html = render_component(actuator: build_actuator, last_command: build_command(id: 7))

      expect(html).to include('id="command_status_7"')
      expect(html).not_to include('id="command_status_"')
    end

    it "displays IDLE when no last command" do
      html = render_component(actuator: build_actuator)
      expect(html).to include("IDLE")
    end

    # 🔴 Обидва наступні приклади мусять жити в НЕ-базовій локалі, і це не
    # прискіпливість. В `en` мітка дорівнює сирому токену (`confirmed:
    # confirmed`, `active: active`), тож англійський `include("confirmed")`
    # зелений і для перекладеної мітки, і для сирого enum'а — тобто не
    # здатний побачити рівно той дефект, заради якого написаний.
    it "resolves the physical state through the locale file, not the raw enum" do
      html = I18n.with_locale(:uk) { render_component(actuator: build_actuator(state: "active")) }

      expect(html).to include("активність")
      expect(html).not_to match(/>\s*active\s*</)
    end

    it "resolves the last command status through the locale file" do
      html = I18n.with_locale(:uk) do
        render_component(actuator: build_actuator, last_command: build_command(status: "confirmed"))
      end

      expect(html).to include("завершено")
    end

    # ⚠️ Стара версія цього прикладу пінила `text-status-danger-accent` — а це
    # клас hover/focus кнопки OFF (`card.rb`), не статусу. Вона лишалась би
    # зеленою, навіть якби статус не рендерився взагалі. Пін мусить бути на
    # стилі САМОГО бейджа, який тепер єдиний дім кольорів усіх п'яти станів.
    it "renders a failed command through the shared status badge" do
      html = render_component(actuator: build_actuator, last_command: build_command(status: "failed"))

      # ⚠️ Пін саме на `text-red-200`, і це не примха: `bg-status-danger-accent` картка
      # вживає САМА в `status_led_class` для `offline`, тож на ньому приклад
      # був би зелений через сусідній елемент — та сама вада, що в прикладі,
      # який цей замінює. `text-red-200` у картці не існує ніде.
      expect(html).to include("text-red-200")
    end
  end

  describe "edge cases" do
    it "renders without a gateway UID when the actuator has no gateway" do
      actuator = build_actuator
      actuator.gateway = nil
      html = render_component(actuator: actuator)
      expect(html).to include(actuator.device_type_label)
    end

    it "renders the max duration row when max_active_duration_s is set" do
      actuator = build_actuator
      actuator.max_active_duration_s = 30
      html = render_component(actuator: actuator)
      expect(html).to include("Max Duration")
    end

    it "renders the energy budget row when estimated_mj_per_action is set" do
      actuator = build_actuator
      actuator.estimated_mj_per_action = 5.2
      html = render_component(actuator: actuator)
      expect(html).to include("Energy Budget")
    end

    it "renders the formatted timestamp when last_activated_at is set" do
      actuator = build_actuator
      actuator.last_activated_at = Time.zone.parse("2025-03-15 10:30:00")
      html = render_component(actuator: actuator)
      expect(html).to include("15.03.25 10:30")
      expect(html).not_to include("NEVER")
    end
  end

  # [UI.14] Вісь, якої цей файл не мав ЖОДНОГО разу: що саме кнопка кладе на дріт.
  # Доти картка слала `open`/`close` — вантаж, який модель відкидає РЕГІСТРОМ, тож
  # кожен клік по пожежному клапану давав 500, а сюїта цього не бачила, бо кожен
  # request-приклад подавав власний рукописний літерал ВЕЛИКИМИ. Пін нижче звіряє
  # вивід картки з МОДЕЛЬНОЮ константою, а не з літералом автора, тож він
  # червоніє на будь-якому розходженні UI ⟷ модель, а не лише на цьому.
  describe "manual control payload" do
    let(:html) { render_component(actuator: build_actuator) }

    def rendered_payload(markup)
      CGI.unescape(markup[/action_payload=([^"'&]+)/, 1].to_s)
    end

    it "renders a payload the model actually accepts" do
      payload = rendered_payload(html)

      # Ліхтар: без нього приклад був би зелений на розмітці ЗОВСІМ без кнопки.
      expect(payload).to be_present
      expect(payload).to match(ActuatorCommand::ALLOWED_PAYLOAD_FORMAT)
    end

    it "renders the emergency stop, which is the only action with a backend effect today" do
      payload = rendered_payload(html)

      # `STOP` мусить лишатись override-вантажем: саме з цього виводиться
      # `cancel_pending_for_actuator!`, тобто єдиний спостережуваний ефект дії,
      # поки Королева ACTION не інтерпретує.
      expect(ActuatorCommand.override_payload?(payload)).to be true
    end

    it "no longer offers an actuation the wire cannot carry" do
      # Негативна половина: повернення кнопок «відкрити/закрити» червонить тут.
      # Без неї пін вище лишався б зеленим, якби поруч зі STOP додали ще й `open`.
      expect(html.scan(/action_payload=/).size).to eq(1)
      expect(html).not_to include("action_payload=open")
    end
  end

  describe "best practices compliance" do
    let(:html) { render_component(actuator: build_actuator) }

    it "uses extracted card_container_classes method" do
      expect(html).to include("border-gaia-border")
      expect(html).to include("bg-gaia-surface")
      expect(html).to include("hover:border-gaia-primary")
      expect(html).to include("transition-all")
    end

    it "uses semantic text tokens instead of arbitrary sizes for content" do
      expect(html).to include("text-micro")
      expect(html).to include("text-tiny")
    end

    it "uses tracking-widest for uppercase microcopy" do
      expect(html).to include("tracking-widest")
    end
  end
end
