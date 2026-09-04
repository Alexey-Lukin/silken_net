# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"
require "csv"

RSpec.describe Api::V1::ReportsController, type: :request do
  let(:organization) { create(:organization) }
  let(:user) { create(:user, organization: organization) }
  let(:api_token) { user.generate_token_for(:api_access) }
  let(:headers) { { "Authorization" => "Bearer #{api_token}" } }

  describe "GET /reports" do
    it "returns a summary report for the organization" do
      get "/reports", headers: headers, as: :json
      expect(response).to have_http_status(:ok)

      body = response.parsed_body
      expect(body["organization"]).to eq(organization.name)
      expect(body["summary"]).to include("total_trees", "health_score", "total_carbon_points")
      expect(body["available_reports"]).to include("carbon_absorption", "financial_summary")
    end
  end

  describe "GET /reports/carbon_absorption" do
    it "returns a carbon absorption report as JSON" do
      get "/reports/carbon_absorption", headers: headers, as: :json
      expect(response).to have_http_status(:ok)

      body = response.parsed_body
      expect(body["report"]).to eq("carbon_absorption")
      expect(body["data"]).to include("total_carbon_points", "wallets_count")
    end

    it "returns a carbon absorption report as CSV" do
      get "/reports/carbon_absorption.csv", headers: headers
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("text/csv")

      rows = CSV.parse(response.body)
      expect(rows[0]).to eq([ "Carbon Absorption Report" ])
      expect(rows[1][0]).to eq("Organization")
      expect(rows[1][1]).to eq(organization.name)
      expect(rows[4]).to eq(%w[Metric Value])
      expect(rows[5][0]).to eq("Total Carbon Points")
    end

    it "returns a carbon absorption report as PDF" do
      get "/reports/carbon_absorption.pdf", headers: headers
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("application/pdf")
      expect(response.body).to start_with("%PDF")
    end
  end

  describe "GET /reports/financial_summary" do
    before do
      # [ARCH.119] Нога оголошено ЖИВА — інакше activation-гейт короткозамикає ДО
      # інстанціювання, `allow_any_instance_of` не досягається, і три «TheGraph лежить»-
      # контексти нижче доводили б гейт замість вендорського збою, який вони називають.
      allow(TheGraph::QueryService).to receive(:configured?).and_return(true)
      allow_any_instance_of(TheGraph::QueryService).to receive(:fetch_protocol_financials)
        .and_return(total_minted: 500_000, total_burned: 150_000)
    end

    it "returns a financial summary report as JSON" do
      get "/reports/financial_summary", headers: headers, as: :json
      expect(response).to have_http_status(:ok)

      body = response.parsed_body
      expect(body["report"]).to eq("financial_summary")
      expect(body["data"]).to include("total_contracted", "blockchain_transactions")
    end

    # [S6.16] Один згрупований прохід замінив чотири окремі COUNT — і доти ці ЧОТИРИ
    # ЧИСЛА не пінував жоден приклад (перевірялась лише ПРИСУТНІСТЬ ключа). Небезпека
    # конкретна: `by_status.fetch("confirmed", 0)` перетворює будь-яку регресію типу
    # ключа на ТИХІ нулі в інвестор-звіті — `total` лишиться правильним, три інші
    # стануть 0, винятку не буде, CI зелений.
    it "counts each status correctly, and total as their sum" do
      # Скоуп звіту — `joins(wallet: { tree: :cluster })`, тож кластер мусить належати
      # ЦІЙ організації. `Tree.after_create` уже створює гаманець (ARCH.56) — беремо його.
      wallet = create(:tree, cluster: create(:cluster, organization: organization)).wallet
      create(:blockchain_transaction, wallet: wallet, status: :confirmed)
      create(:blockchain_transaction, wallet: wallet, status: :pending)
      create(:blockchain_transaction, wallet: wallet, status: :failed)
      create(:blockchain_transaction, wallet: wallet, status: :manual_review)

      get "/reports/financial_summary", headers: headers, as: :json

      tx = response.parsed_body.dig("data", "blockchain_transactions")
      expect(tx).to include("confirmed" => 1, "pending" => 1, "failed" => 1)
      # `total` рахує ВСІ статуси, не лише три названі — `manual_review` теж усередині.
      expect(tx["total"]).to eq(4)
    end

    it "keeps network_emission strictly on-chain (no off-chain premium mixed in)" do
      get "/reports/financial_summary", headers: headers, as: :json
      expect(response).to have_http_status(:ok)

      ry = response.parsed_body.dig("data", "network_emission")
      expect(ry).to include(
        "total_minted_scc" => 500_000,
        "total_burned_scc" => 150_000,
        "net_deflation" => -350_000
      )
      # [ARCH.90] Негативна половина: премія — off-chain USDC-факт і в мережевому
      # блоці їй не місце. Без цього піна повернення старої форми зелене.
      expect(ry).not_to have_key("total_premiums_usdc")
    end

    # 🔴 [ARCH.90] Найважливіший пін цього фіксу: премія в звіті організації мусить
    # бути ЇЇ внеском, а не агрегатом платформи. Доти контролер кликав КЛАСОВУ
    # `NaasContract.total_insurance_premiums`, тож інвестор бачив суму по ВСІХ
    # орендарях — саме ту pooled-величину, яку securities_review F8 називає
    # фактором Howey prong 2. Фікстура навмисно має ДРУГОГО орендаря з БІЛЬШОЮ
    # сумою: з одним тенантом «своє» і «все» збігаються, і приклад не здатен
    # виразити дефект (`04_06 §B.2` BP #21).
    it "scopes insurance premiums to the acting organization, never the whole platform" do
      create(:naas_contract, status: :active, organization: organization,
                             cluster: create(:cluster, organization: organization), total_funding: 600_000)

      other_org = create(:organization)
      create(:naas_contract, status: :active, organization: other_org,
                             cluster: create(:cluster, organization: other_org), total_funding: 4_000_000)

      get "/reports/financial_summary", headers: headers, as: :json
      expect(response).to have_http_status(:ok)

      # 600_000 × 5% = 30_000 — своє. Платформенне було б 230_000.
      expect(response.parsed_body.dig("data", "insurance_premiums_paid_usdc")).to eq(30_000)
    end

    it "returns a financial summary report as CSV" do
      get "/reports/financial_summary.csv", headers: headers
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("text/csv")

      rows = CSV.parse(response.body)
      expect(rows[0]).to eq([ "Financial Summary Report" ])
      expect(rows[1][0]).to eq("Organization")
      expect(rows[1][1]).to eq(organization.name)
      expect(rows[4]).to eq(%w[Metric Value])
      expect(rows[5][0]).to eq("Total Contracted")
    end

    it "includes network_emission data in CSV response" do
      get "/reports/financial_summary.csv", headers: headers

      csv_text = response.body
      expect(csv_text).to include("Network Emission (DePIN/ReFi)")
      expect(csv_text).to include("Total Minted SCC")
      expect(csv_text).to include("Total Burned SCC")
      expect(csv_text).to include("Net Deflation")
      # [ARCH.90] Заголовок мережевої секції мусить САМ казати, чиї це числа —
      # доти єдиною підказкою було слово «Network», а поруч у тій самій секції
      # стояла премія платформи.
      expect(csv_text).to include("not this organization")
      # Премія переїхала в org-секцію під власником у підписі.
      expect(csv_text).to include("Insurance Premiums Paid by This Organization (USDC)")
      expect(csv_text).not_to include("Total Premiums USDC")
    end

    it "returns a financial summary report as PDF" do
      get "/reports/financial_summary.pdf", headers: headers
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("application/pdf")
      expect(response.body).to start_with("%PDF")
    end

    context "when TheGraph service is unavailable" do
      before do
        allow_any_instance_of(TheGraph::QueryService).to receive(:fetch_protocol_financials)
          .and_raise(TheGraph::QueryService::QueryError, "connection refused")
      end

      # 🔴 [ARCH.103] «zero defaults» було не описом поведінки, а ВИМОГОЮ до неї.
      it "reports all three network figures as unmeasured" do
        get "/reports/financial_summary", headers: headers, as: :json
        expect(response).to have_http_status(:ok)

        ry = response.parsed_body.dig("data", "network_emission")
        expect(ry).to include("total_minted_scc", "total_burned_scc", "net_deflation")
        expect(ry.values_at("total_minted_scc", "total_burned_scc", "net_deflation")).to all(be_nil)
      end
    end

    # [ARCH.119] Третя вісь поруч із двома «вендор відмовив» контекстами: ноги немає
    # взагалі. Форма фолбеку тут ВЛАСНА (три ключі) і не збігається з дашбордним скаляром —
    # «симетричний лік» на обидва сайти був би хибним.
    context "when the subgraph is not configured at all" do
      before do
        allow(TheGraph::QueryService).to receive(:configured?).and_return(false)
        allow(TheGraph::QueryService).to receive(:new)
      end

      it "reports all three as unmeasured without ever building the client" do
        allow(Rails.logger).to receive(:warn)

        get "/reports/financial_summary", headers: headers, as: :json
        expect(response).to have_http_status(:ok)

        ry = response.parsed_body.dig("data", "network_emission")
        expect(ry.values_at("total_minted_scc", "total_burned_scc", "net_deflation")).to all(be_nil)
        expect(TheGraph::QueryService).not_to have_received(:new)
        expect(Rails.logger).to have_received(:warn).with(/не сконфігуровано/)
      end
    end

    context "when network emission fetch raises a generic StandardError" do
      before do
        allow_any_instance_of(TheGraph::QueryService).to receive(:fetch_protocol_financials)
          .and_raise(StandardError, "network timeout")
      end

      it "reports all three network figures as unmeasured on generic error" do
        get "/reports/financial_summary", headers: headers, as: :json
        expect(response).to have_http_status(:ok)

        ry = response.parsed_body.dig("data", "network_emission")
        expect(ry).to include("total_minted_scc", "total_burned_scc", "net_deflation")
        expect(ry.values_at("total_minted_scc", "total_burned_scc", "net_deflation")).to all(be_nil)
      end
    end

    context "when TheGraph is down but NaaS premiums exist (DB-sourced)" do
      before do
        allow_any_instance_of(TheGraph::QueryService).to receive(:fetch_protocol_financials)
          .and_raise(TheGraph::QueryService::QueryError, "connection refused")
      end

      it "still reports DB premiums while the subgraph figures stay unmeasured" do
        # [SEC.1] Premiums are DB-sourced, decoupled from the subgraph — a GraphQL
        # outage zeroes minted/burned/net_deflation but NOT a known premium.
        # [ARCH.90] Розв'язка тепер СТРУКТУРНА, а не мерджем: премія живе окремим
        # org-ключем, тож збою subgraph нічим її зачепити — і саме це пінить пара
        # тверджень нижче (блок обнулився ⊥ премія ціла).
        create(:naas_contract, status: :active, organization: organization,
                               cluster: create(:cluster, organization: organization), total_funding: 200_000)

        get "/reports/financial_summary", headers: headers, as: :json
        expect(response).to have_http_status(:ok)

        expect(response.parsed_body.dig("data", "insurance_premiums_paid_usdc")).to eq(10_000)

        ry = response.parsed_body.dig("data", "network_emission")
        expect(ry).to include("total_minted_scc", "total_burned_scc", "net_deflation")
        expect(ry.values_at("total_minted_scc", "total_burned_scc", "net_deflation")).to all(be_nil)
      end
    end
  end

  context "with format.html responses" do
    let(:html_headers) do
      { "Authorization" => "Bearer #{api_token}", "Accept" => "text/html" }
    end

    it "renders HTML for index" do
      get "/reports", headers: html_headers
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("text/html")
    end

    it "renders HTML for carbon_absorption" do
      get "/reports/carbon_absorption", headers: html_headers
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("text/html")
    end

    it "renders HTML for financial_summary" do
      get "/reports/financial_summary", headers: html_headers
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("text/html")
    end
  end
end
