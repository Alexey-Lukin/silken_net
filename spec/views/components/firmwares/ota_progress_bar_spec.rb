# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Firmwares::OtaProgressBar do
  describe "rendering" do
    let(:html) { render_component(uid: "SNET-001", percent: 50, current: 25, total: 50, status: "TRANSMITTING") }

    it "renders with unique OTA progress id" do
      expect(html).to include("ota_progress_SNET-001")
    end

    it "displays the UID in the header" do
      expect(html).to include("OTA_LINK: SNET-001")
    end

    it "displays the status text" do
      expect(html).to include("TRANSMITTING")
    end

    it "renders the progress bar with correct width" do
      expect(html).to include("width: 50%")
    end

    it "displays chunk progress" do
      expect(html).to include("CHUNK: 25 / 50")
    end

    it "displays percentage complete" do
      expect(html).to include("50% COMPLETE")
    end

    it "uses font-mono styling" do
      expect(html).to include("font-mono")
    end

    it "renders with emerald border" do
      expect(html).to include("border-emerald-900")
    end
  end

  describe "status colors" do
    it "renders emerald-400 for COMPLETE status" do
      html = render_component(uid: "X", percent: 100, current: 50, total: 50, status: "COMPLETE")
      expect(html).to include("text-emerald-400")
    end

    # [UI.3] Пульс знято з обох гілок: він стояв на самому СЛОВІ статусу, тобто
    # робив нечитабельним єдиний рядок, що повідомляє про падіння прошивки.
    # Розрізняє чотири стани колір, і завжди розрізняв.
    it "renders red-500 for FAILED status, without motion on the label" do
      html = render_component(uid: "X", percent: 30, current: 15, total: 50, status: "FAILED")
      expect(html).to include("text-red-500")
      expect(html).not_to include("animate-pulse")
    end

    it "renders emerald-600 for in-progress status, without motion on the label" do
      html = render_component(uid: "X", percent: 60, current: 30, total: 50, status: "TRANSMITTING")
      expect(html).to include("text-emerald-600")
      expect(html).not_to include("animate-pulse")
    end
  end

  describe "edge cases" do
    it "handles 0% progress" do
      html = render_component(uid: "Y", percent: 0, current: 0, total: 100, status: "PENDING")
      expect(html).to include("width: 0%")
      expect(html).to include("0% COMPLETE")
    end

    it "handles 100% progress" do
      html = render_component(uid: "Z", percent: 100, current: 100, total: 100, status: "COMPLETE")
      expect(html).to include("width: 100%")
      expect(html).to include("100% COMPLETE")
    end
  end

  describe "initial-render states (SEC.20)" do
    it "renders IDLE in gray without pulse" do
      html = render_component(uid: "X", percent: 0, current: 0, total: 0, status: "IDLE")
      expect(html).to include("text-gray-600")
      expect(html).not_to include("animate-pulse")
    end

    it "hides the chunk counter when total is zero" do
      html = render_component(uid: "X", percent: 100, current: 0, total: 0, status: "COMPLETE")
      expect(html).not_to include("CHUNK:")
      expect(html).to include("COMPLETE")
    end

    it "keeps the Turbo replace target id in the zero-total state" do
      html = render_component(uid: "SNET-Q-1", percent: 0, current: 0, total: 0, status: "IDLE")
      expect(html).to include("ota_progress_SNET-Q-1")
    end
  end

  describe "best practices compliance" do
    let(:html) { render_component(uid: "TEST", percent: 50, current: 25, total: 50, status: "TRANSMITTING") }

    it "uses text-mini for labels" do
      expect(html).to include("text-mini")
    end

    it "uses text-micro for details" do
      expect(html).to include("text-micro")
    end

    it "uses tracking-widest for uppercase labels" do
      expect(html).to include("tracking-widest")
    end
  end
end
