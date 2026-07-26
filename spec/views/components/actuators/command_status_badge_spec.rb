# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Actuators::CommandStatusBadge do
  def mock_command(id: 1, status: "confirmed")
    OpenStruct.new(id: id, status: status)
  end

  describe "rendering" do
    let(:html) { render_component(command: mock_command) }

    it "renders the badge with unique id" do
      expect(html).to include("command_status_1")
    end

    it "renders the status text" do
      expect(html).to include("confirmed")
    end

    it "applies uppercase styling" do
      expect(html).to include("uppercase")
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
      html = render_component(command: mock_command(status: "issued"))
      expect(html).to include("bg-yellow-900")
      expect(html).to include("text-yellow-200")
    end

    it "renders sent with blue background" do
      html = render_component(command: mock_command(status: "sent"))
      expect(html).to include("bg-blue-900")
      expect(html).to include("text-blue-200")
    end

    it "renders acknowledged with emerald background" do
      html = render_component(command: mock_command(status: "acknowledged"))
      expect(html).to include("bg-emerald-900")
      expect(html).to include("text-emerald-200")
    end

    it "renders failed with red background" do
      html = render_component(command: mock_command(status: "failed"))
      expect(html).to include("bg-red-900")
      expect(html).to include("text-red-200")
    end

    it "renders confirmed with emerald-800 background" do
      html = render_component(command: mock_command(status: "confirmed"))
      expect(html).to include("bg-emerald-800")
      expect(html).to include("text-emerald-100")
    end

    it "falls back to zinc for unknown status" do
      html = render_component(command: mock_command(status: "something_else"))
      expect(html).to include("bg-zinc-800")
      expect(html).to include("text-zinc-300")
    end
  end

  describe "element id" do
    it "uses command id in the element id" do
      html = render_component(command: mock_command(id: 99))
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
