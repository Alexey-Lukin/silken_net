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

  describe "status styles" do
    it "renders issued with yellow background" do
      html = render_component(command: build_command(status: "issued"))
      expect(html).to include("bg-yellow-900")
      expect(html).to include("text-yellow-200")
    end

    it "renders sent with blue background" do
      html = render_component(command: build_command(status: "sent"))
      expect(html).to include("bg-blue-900")
      expect(html).to include("text-blue-200")
    end

    it "renders acknowledged with emerald background" do
      html = render_component(command: build_command(status: "acknowledged"))
      expect(html).to include("bg-emerald-900")
      expect(html).to include("text-emerald-200")
    end

    it "renders failed with red background" do
      html = render_component(command: build_command(status: "failed"))
      expect(html).to include("bg-red-900")
      expect(html).to include("text-red-200")
    end

    it "renders confirmed with emerald-800 background" do
      html = render_component(command: build_command(status: "confirmed"))
      expect(html).to include("bg-emerald-800")
      expect(html).to include("text-emerald-100")
    end

    # ⚠️ Вхід досяжний ЛИШЕ стабом РИДЕРА: `status` — справжній enum, тож
    # `ActuatorCommand.new(status: "something_else")` кидає `ArgumentError` просто в
    # конструкторі. Доти цю гілку «перевіряло» значення, якого прод не дає.
    # ⊕ Фолбек тут ЧЕСНО розрізнимий, на відміну від `trees/chronicle` ([`04_06 §A.4`] BP 20):
    # `bg-zinc-800` не належить жодному з пʼяти живих статусів, а мітка через
    # `t(default: status)` друкує САМЕ значення — тобто ознака в розмітці є.
    it "falls back to zinc for unknown status" do
      command = build_command
      allow(command).to receive(:status).and_return("something_else")

      html = render_component(command: command)
      expect(html).to include("bg-zinc-800")
      expect(html).to include("text-zinc-300")
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
