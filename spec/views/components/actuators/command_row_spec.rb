# frozen_string_literal: true

require "rails_helper"

RSpec.describe Actuators::CommandRow do
  def mock_command(id: 1, status: "confirmed", command_payload: "OPEN_VALVE", created_at: Time.current)
    OpenStruct.new(id: id, status: status, command_payload: command_payload, created_at: created_at)
  end

  describe "rendering" do
    let(:html) { render_component(command: mock_command) }

    it "renders the command row container with correct id" do
      expect(html).to include("command_row_1")
    end

    it "displays the command payload" do
      expect(html).to include("OPEN_VALVE")
    end

    it "renders with font-mono styling" do
      expect(html).to include("font-mono")
    end

    it "renders with border-b separator" do
      expect(html).to include("border-b")
    end

    it "uses text-compact for font sizing" do
      expect(html).to include("text-compact")
    end

    it "renders the CommandStatusBadge sub-component" do
      expect(html).to include("command_status_")
    end
  end

  describe "timestamp display" do
    it "formats created_at with HH:MM:SS" do
      time = Time.new(2024, 6, 1, 9, 15, 42)
      html = render_component(command: mock_command(created_at: time))
      expect(html).to include("09:15:42")
    end

    it "handles nil created_at gracefully" do
      html = render_component(command: mock_command(created_at: nil))
      expect(html).to be_a(String)
    end
  end

  describe "different command payloads" do
    it "renders RESET payload" do
      html = render_component(command: mock_command(command_payload: "RESET"))
      expect(html).to include("RESET")
    end

    it "renders CLOSE_VALVE payload" do
      html = render_component(command: mock_command(command_payload: "CLOSE_VALVE"))
      expect(html).to include("CLOSE_VALVE")
    end
  end

  describe "element id uniqueness" do
    it "uses command id for unique element identification" do
      html = render_component(command: mock_command(id: 42))
      expect(html).to include("command_row_42")
    end

    it "renders different ids for different commands" do
      html1 = render_component(command: mock_command(id: 1))
      html2 = render_component(command: mock_command(id: 2))
      expect(html1).to include("command_row_1")
      expect(html2).to include("command_row_2")
    end
  end

  describe "best practices compliance" do
    let(:html) { render_component(command: mock_command) }

    it "uses emerald-400 for payload text" do
      expect(html).to include("text-emerald-400")
    end

    it "uses zinc-500 for timestamp text" do
      expect(html).to include("text-zinc-500")
    end
  end
end
