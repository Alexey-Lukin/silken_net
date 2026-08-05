# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Actuators::Card do
  # 🔴 `commands` НАВМИСНО вибухає. Доти фікстура віддавала `OpenStruct.new(last: nil)`
  # — вона існувала рівно для того, щоб обслужити фолбек `@actuator.commands.last`
  # у конструкторі, тобто описувала світ, у якому запит із Phlex-`initialize`
  # виглядає нормою (`04_04 §6.4` це забороняє). Тепер картка дані ЛИШЕ приймає,
  # і будь-яке повернення фолбека червонить кожен приклад цього файлу.
  def mock_actuator(id: 1, device_type: "valve", state: "active", gateway_uid: "QUEEN-01")
    gateway = OpenStruct.new(uid: gateway_uid)
    commands = Object.new.tap do |o|
      o.define_singleton_method(:last) { raise "Actuators::Card не сміє добирати команди — їх подає викликач" }
    end
    OpenStruct.new(id: id, device_type: device_type, state: state, gateway: gateway, commands: commands)
  end

  def mock_command(status: "confirmed")
    OpenStruct.new(status: status)
  end

  describe "rendering" do
    let(:html) { render_component(actuator: mock_actuator) }

    it "renders the actuator id in the element id" do
      expect(html).to include("actuator_1")
    end

    it "displays the device type" do
      expect(html).to include("valve")
    end

    it "displays the gateway UID in the header" do
      expect(html).to include("QUEEN-01")
    end
  end

  describe "status LED" do
    it "renders emerald glow for active state" do
      html = render_component(actuator: mock_actuator(state: "active"))
      expect(html).to include("bg-emerald-500")
    end

    it "renders red pulse for maintenance_needed state" do
      html = render_component(actuator: mock_actuator(state: "maintenance_needed"))
      expect(html).to include("bg-red-600")
      expect(html).to include("animate-pulse")
    end

    it "renders dark red for offline state" do
      html = render_component(actuator: mock_actuator(state: "offline"))
      expect(html).to include("bg-red-900")
    end

    it "renders gray for unknown state" do
      html = render_component(actuator: mock_actuator(state: "unknown"))
      expect(html).to include("bg-gray-800")
    end
  end

  describe "status matrix" do
    it "displays the physical state" do
      html = render_component(actuator: mock_actuator(state: "active"))
      expect(html).to include("Physical State:")
      expect(html).to include("active")
    end

    it "displays last command status" do
      html = render_component(actuator: mock_actuator, last_command: mock_command(status: "confirmed"))
      expect(html).to include("confirmed")
    end

    it "displays IDLE when no last command" do
      html = render_component(actuator: mock_actuator)
      expect(html).to include("IDLE")
    end

    # 🔴 Обидва наступні приклади мусять жити в НЕ-базовій локалі, і це не
    # прискіпливість. В `en` мітка дорівнює сирому токену (`confirmed:
    # confirmed`, `active: active`), тож англійський `include("confirmed")`
    # зелений і для перекладеної мітки, і для сирого enum'а — тобто не
    # здатний побачити рівно той дефект, заради якого написаний.
    it "resolves the physical state through the locale file, not the raw enum" do
      html = I18n.with_locale(:uk) { render_component(actuator: mock_actuator(state: "active")) }

      expect(html).to include("активність")
      expect(html).not_to match(/>\s*active\s*</)
    end

    it "resolves the last command status through the locale file" do
      html = I18n.with_locale(:uk) do
        render_component(actuator: mock_actuator, last_command: mock_command(status: "confirmed"))
      end

      expect(html).to include("завершено")
    end

    # ⚠️ Стара версія цього прикладу пінила `text-status-danger-accent` — а це
    # клас hover/focus кнопки OFF (`card.rb`), не статусу. Вона лишалась би
    # зеленою, навіть якби статус не рендерився взагалі. Пін мусить бути на
    # стилі САМОГО бейджа, який тепер єдиний дім кольорів усіх п'яти станів.
    it "renders a failed command through the shared status badge" do
      html = render_component(actuator: mock_actuator, last_command: mock_command(status: "failed"))

      # ⚠️ Пін саме на `text-red-200`, і це не примха: `bg-red-900` картка
      # вживає САМА в `status_led_class` для `offline`, тож на ньому приклад
      # був би зелений через сусідній елемент — та сама вада, що в прикладі,
      # який цей замінює. `text-red-200` у картці не існує ніде.
      expect(html).to include("text-red-200")
    end
  end

  describe "edge cases" do
    it "renders without a gateway UID when the actuator has no gateway" do
      actuator = mock_actuator
      actuator.gateway = nil
      html = render_component(actuator: actuator)
      expect(html).to include(actuator.device_type)
    end

    it "renders the max duration row when max_active_duration_s is set" do
      actuator = mock_actuator
      actuator.max_active_duration_s = 30
      html = render_component(actuator: actuator)
      expect(html).to include("Max Duration")
    end

    it "renders the energy budget row when estimated_mj_per_action is set" do
      actuator = mock_actuator
      actuator.estimated_mj_per_action = 5.2
      html = render_component(actuator: actuator)
      expect(html).to include("Energy Budget")
    end

    it "renders the formatted timestamp when last_activated_at is set" do
      actuator = mock_actuator
      actuator.last_activated_at = Time.zone.parse("2025-03-15 10:30:00")
      html = render_component(actuator: actuator)
      expect(html).to include("15.03.25 10:30")
      expect(html).not_to include("NEVER")
    end
  end

  describe "best practices compliance" do
    let(:html) { render_component(actuator: mock_actuator) }

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
