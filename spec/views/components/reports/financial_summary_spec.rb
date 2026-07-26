# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Reports::FinancialSummary do
  def mock_org(name: "GreenFund")
    OpenStruct.new(name: name)
  end

  def mock_data(total_contracted: 75_000, active_contracts: 12, total_contracts: 20,
                blockchain_transactions: nil)
    {
      total_contracted: total_contracted,
      active_contracts: active_contracts,
      total_contracts: total_contracts,
      blockchain_transactions: blockchain_transactions || {
        total: 500, confirmed: 480, pending: 15, failed: 5
      }
    }
  end

  let(:org)  { mock_org }
  let(:data) { mock_data }
  let(:html) { render_component(organization: org, data: data) }

  describe "header section" do
    it "renders Financial Summary Report label" do
      expect(html).to include("Financial Summary Report")
    end

    it "renders organization name" do
      expect(html).to include("GreenFund")
    end

    it "renders generated timestamp" do
      expect(html).to include("Generated:")
    end
  end

  describe "stat cards" do
    it "renders Total Contracted stat card" do
      # Service wording, not investment wording — BIZ.22 / 07_01 §1. The label moved
      # from "Total Invested"; the i18n KEY (`metrics.total_invested`) deliberately did
      # not, since keys are never shown to a user.
      expect(html).to include("Total Contracted")
    end

    it "renders Active Contracts stat card" do
      expect(html).to include("Active Contracts")
    end

    it "renders Total Contracts stat card" do
      expect(html).to include("Total Contracts")
    end
  end

  describe "blockchain breakdown table" do
    it "renders Blockchain Transactions Breakdown heading" do
      expect(html).to include("Blockchain Transactions Breakdown")
    end

    it "renders Total Transactions row" do
      expect(html).to include("Total Transactions")
    end

    it "renders Confirmed row" do
      expect(html).to include("Confirmed")
    end

    it "renders Pending row" do
      expect(html).to include("Pending")
    end

    it "renders Failed row" do
      expect(html).to include("Failed")
    end

    it "renders total count" do
      expect(html).to include("500")
    end

    it "renders confirmed count" do
      expect(html).to include("480")
    end

    it "renders pending count" do
      expect(html).to include("15")
    end

    it "renders failed count" do
      expect(html).to include("5")
    end
  end

  describe "footer" do
    it "renders generated at footer" do
      expect(html).to include("Report generated at")
    end

    it "includes organization name in footer" do
      expect(html).to include("GreenFund")
    end
  end
end
