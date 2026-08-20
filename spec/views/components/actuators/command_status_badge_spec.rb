# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Actuators::CommandStatusBadge do
  def build_command(id: 1, status: "confirmed")
    # [TEST.12] Реальний незбережений `ActuatorCommand`: `status` тепер ходить через
    # справжній enum, тож значення поза набором (`issued`/`sent`/`acknowledged`/
    # `failed`/`confirmed`) тут неможливе — модель кидає `ArgumentError` у конструкторі.
    # `id` несучий: із нього будується адреса броадкасту (`command_status_{id}` у бейджі,
    # `CommandStatusFrame.dom_id` у фреймі), яку адресує `actuator_command_worker`.
    ActuatorCommand.new(id: id, status: status)
  end

  describe "rendering" do
    let(:html) { render_component(command: build_command) }

    it "renders the badge with unique id" do
      expect(html).to include("command_status_1")
    end

    it "renders the status text" do
      expect(html).to include("confirmed")
    end

    it "applies uppercase styling" do
      expect(html).to include("uppercase")
    end

    # [UI.3] Сирий enum у data-атрибуті — машинний дискримінатор термінальності
    # для SR-анонсера; без нього JS-половина глуха при зеленій розмітці.
    it "exposes the raw state for the announcer" do
      badge = Capybara.string(html).find("#command_status_1")
      expect(badge["data-command-state"]).to eq("confirmed")
    end

    it "applies rounded styling" do
      expect(html).to include("rounded")
    end

    it "uses text-tiny font size" do
      expect(html).to include("text-tiny")
    end

    it "applies font-bold" do
      expect(html).to include("font-bold")
    end
  end

  # [UI.1] Бейдж-роль = пастельний `status-*` + парний `-text` (`04_04 §3.2`);
  # сирі yellow/blue/emerald/red-класи пішли з міграцією домену.
  describe "status styles" do
    it "renders issued with the warning pair" do
      html = render_component(command: build_command(status: "issued"))
      expect(html).to include("bg-status-warning")
      expect(html).to include("text-status-warning-text")
    end

    it "renders sent with the info pair" do
      html = render_component(command: build_command(status: "sent"))
      expect(html).to include("bg-status-info")
      expect(html).to include("text-status-info-text")
    end

    it "renders acknowledged with the active pair" do
      html = render_component(command: build_command(status: "acknowledged"))
      expect(html).to include("bg-status-active")
      expect(html).to include("text-status-active-text")
    end

    it "renders failed with the danger pair" do
      html = render_component(command: build_command(status: "failed"))
      expect(html).to include("bg-status-danger")
      expect(html).to include("text-status-danger-text")
    end

    it "renders confirmed with the success pair" do
      html = render_component(command: build_command(status: "confirmed"))
      expect(html).to include("bg-status-success")
      expect(html).to include("text-status-success-text")
    end

    # ⚠️ Вхід досяжний ЛИШЕ стабом РИДЕРА: `status` — справжній enum, тож
    # `ActuatorCommand.new(status: "something_else")` кидає `ArgumentError` просто в
    # конструкторі. Доти цю гілку «перевіряло» значення, якого прод не дає.
    # ⊕ Фолбек тут ЧЕСНО розрізнимий, на відміну від `trees/chronicle` ([`04_06 §A.4`] BP 20):
    # `surface-elevated` не належить жодному з пʼяти живих статусів, а мітка через
    # `t(default: status)` друкує САМЕ значення — тобто ознака в розмітці є.
    it "falls back to the elevated-surface style for unknown status" do
      command = build_command
      allow(command).to receive(:status).and_return("something_else")

      html = render_component(command: command)
      expect(html).to include("bg-gaia-surface-elevated")
      expect(html).to include("text-gaia-text-subtle")
      expect(html).to include("something_else") # фолбек показує сире значення
    end
  end

  describe "element id" do
    it "uses command id in the element id" do
      html = render_component(command: build_command(id: 99))
      expect(html).to include("command_status_99")
    end
  end

  describe "STATUS_STYLES constant" do
    it "is frozen" do
      expect(Actuators::CommandStatusBadge::STATUS_STYLES).to be_frozen
    end

    it "contains exactly 5 statuses" do
      expect(Actuators::CommandStatusBadge::STATUS_STYLES.size).to eq(5)
    end
  end
end
