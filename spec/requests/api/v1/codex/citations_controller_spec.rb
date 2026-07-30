# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Codex::Citations", type: :request do
  let(:org)       { create(:organization) }
  let(:forester)  { create(:user, organization: org, role: :forester) }
  let(:investor)  { create(:user, organization: org, role: :investor) }
  let(:admin)     { create(:user, :admin, organization: org) }
  let(:node)      { create(:codex_node) }
  # [SEC.26] Ціль МУСИТЬ належати організації актора — інакше приклад стверджує
  # рівно той крос-тенант запис, який ця поверхня тепер забороняє. Доти тут стояло
  # голе `create(:tree)`, а фабрика тягне власні cluster+organization, тож майже
  # кожен позитивний приклад файлу мовчки був крос-org і пінив 201 на чужій цілі.
  let(:cluster)   { create(:cluster, organization: org) }
  let(:tree)      { create(:tree, cluster: cluster) }
  let(:token)     { forester.generate_token_for(:api_access) }
  let(:headers) do
    { "Authorization" => "Bearer #{token}",
      "Content-Type"  => "application/json",
      "Idempotency-Key" => SecureRandom.uuid }
  end

  describe "POST /api/v1/codex/citations" do
    it "rejects unauthenticated requests" do
      post "/api/v1/codex/citations", as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it "rejects investors (forester+ only)" do
      bad_token = investor.generate_token_for(:api_access)
      post "/api/v1/codex/citations",
           params: { codex_node_slug: node.slug, citable_type: "Tree", citable_id: tree.id },
           headers: headers.merge("Authorization" => "Bearer #{bad_token}"),
           as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it "creates a citation and increments node.citation_count" do
      expect {
        post "/api/v1/codex/citations",
             params: { codex_node_slug: node.slug, citable_type: "Tree", citable_id: tree.id, note: "see lore_md" },
             headers: headers, as: :json
      }.to change { node.reload.citation_count }.by(1)

      expect(response).to have_http_status(:created)
      payload = response.parsed_body["data"]
      expect(payload).to include(
        "codex_node_id" => node.id,
        "citable_type"  => "Tree",
        "citable_id"    => tree.id,
        "note"          => "see lore_md",
        "node_slug"     => node.slug
      )
    end

    it "rejects JSON writes without Idempotency-Key" do
      post "/api/v1/codex/citations",
           params: { codex_node_slug: node.slug, citable_type: "Tree", citable_id: tree.id },
           headers: headers.except("Idempotency-Key"), as: :json
      expect(response).to have_http_status(:bad_request)
    end

    it "returns the cached response on Idempotency-Key replay" do
      post "/api/v1/codex/citations",
           params: { codex_node_slug: node.slug, citable_type: "Tree", citable_id: tree.id },
           headers: headers, as: :json
      first = response.parsed_body
      expect {
        post "/api/v1/codex/citations",
             params: { codex_node_slug: node.slug, citable_type: "Tree", citable_id: tree.id },
             headers: headers, as: :json
      }.not_to change(Codex::Citation, :count)
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq(first)
    end

    it "rejects an unsupported citable_type" do
      post "/api/v1/codex/citations",
           params: { codex_node_slug: node.slug, citable_type: "User", citable_id: 1 },
           headers: headers, as: :json
      expect(response).to have_http_status(:bad_request)
    end

    it "returns 422 on duplicate (DB UNIQUE)" do
      create(:codex_citation, node: node, created_by_user: forester,
             citable_type: "Tree", citable_id: tree.id)
      post "/api/v1/codex/citations",
           params: { codex_node_slug: node.slug, citable_type: "Tree", citable_id: tree.id },
           headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "resolves OracleVision citable_type to AiInsight when no STI subclass is defined" do
      insight = create(:ai_insight, analyzable: cluster)
      expect(defined?(::OracleVision)).to be_nil

      post "/api/v1/codex/citations",
           params: { codex_node_slug: node.slug, citable_type: "OracleVision", citable_id: insight.id },
           headers: headers, as: :json

      expect(response).to have_http_status(:created)
      expect(response.parsed_body.dig("data", "citable_type")).to eq("AiInsight")
    end

    it "supports citable_type=Cluster" do
      post "/api/v1/codex/citations",
           params: { codex_node_slug: node.slug, citable_type: "Cluster", citable_id: cluster.id },
           headers: headers, as: :json
      expect(response).to have_http_status(:created)
      expect(response.parsed_body.dig("data", "citable_type")).to eq("Cluster")
    end

    it "supports citable_type=AiInsight" do
      insight = create(:ai_insight, analyzable: cluster)
      post "/api/v1/codex/citations",
           params: { codex_node_slug: node.slug, citable_type: "AiInsight", citable_id: insight.id },
           headers: headers, as: :json
      expect(response).to have_http_status(:created)
      expect(response.parsed_body.dig("data", "citable_type")).to eq("AiInsight")
    end

    it "supports citable_type=EwsAlert" do
      alert = create(:ews_alert, cluster: cluster, tree: tree)
      post "/api/v1/codex/citations",
           params: { codex_node_slug: node.slug, citable_type: "EwsAlert", citable_id: alert.id },
           headers: headers, as: :json
      expect(response).to have_http_status(:created)
      expect(response.parsed_body.dig("data", "citable_type")).to eq("EwsAlert")
    end

    it "supports citable_type=NaasContract" do
      contract = create(:naas_contract, organization: org, cluster: cluster)
      post "/api/v1/codex/citations",
           params: { codex_node_slug: node.slug, citable_type: "NaasContract", citable_id: contract.id },
           headers: headers, as: :json
      expect(response).to have_http_status(:created)
      expect(response.parsed_body.dig("data", "citable_type")).to eq("NaasContract")
    end

    it "honors an OracleVision STI subclass when present" do
      stub_const("OracleVision", Class.new(AiInsight))
      insight = OracleVision.create!(analyzable: tree, insight_type: :daily_health_summary,
                                     target_date: Date.current - 1, stress_index: 0.1, summary: "x")

      post "/api/v1/codex/citations",
           params: { codex_node_slug: node.slug, citable_type: "OracleVision", citable_id: insight.id },
           headers: headers, as: :json

      expect(response).to have_http_status(:created)
      expect(response.parsed_body.dig("data", "citable_type")).to eq("AiInsight")
    end

    # [SEC.26] Тенант-ізоляція запису. Доти пінів тут було НУЛЬ, і майже кожен
    # позитивний приклад файлу мовчки стверджував протилежне — 201 на чужій цілі.
    describe "крос-тенант ізоляція цілі" do
      let(:foreign_cluster) { create(:cluster) }
      let(:foreign_tree)    { create(:tree, cluster: foreign_cluster) }

      it "відмовляє в цитуванні дерева чужої організації" do
        expect {
          post "/api/v1/codex/citations",
               params: { codex_node_slug: node.slug, citable_type: "Tree", citable_id: foreign_tree.id },
               headers: headers, as: :json
        }.not_to change(Codex::Citation, :count)

        expect(response).to have_http_status(:not_found)
      end

      # Приклад НА ТИП, а не цикл усередині одного: шість однакових SELECT в межах
      # одного прикладу — це N+1 за визначенням Prosopite, тож спільний цикл падав би
      # на харнесі замість перевіряти ізоляцію. Дрібніша гранулярність ще й називає,
      # ЯКИЙ саме тип лишився відкритим.
      %w[Cluster EwsAlert AiInsight OracleVision NaasContract].each do |type|
        it "відмовляє в цитуванні чужого #{type}" do
          post "/api/v1/codex/citations",
               params: { codex_node_slug: node.slug, citable_type: type,
                         citable_id: foreign_target_id_for(type) },
               headers: headers, as: :json

          expect(response).to have_http_status(:not_found)
        end
      end

      def foreign_target_id_for(type)
        case type
        when "Cluster"                 then foreign_cluster.id
        when "EwsAlert"                then create(:ews_alert, cluster: foreign_cluster, tree: foreign_tree).id
        when "AiInsight", "OracleVision" then create(:ai_insight, analyzable: foreign_cluster).id
        when "NaasContract"            then create(:naas_contract, organization: foreign_cluster.organization,
                                                                   cluster: foreign_cluster).id
        end
      end

      # Чужий і неіснуючий id мусять бути НЕВІДРІЗНЯЛЬНІ: інакше 404-проти-іншого-коду
      # відповідає на питання «чи існує такий запис на платформі» — тобто ендпоінт
      # лишається existence-оракулом навіть із закритим записом.
      it "не відрізняє чужу ціль від неіснуючої" do
        post "/api/v1/codex/citations",
             params: { codex_node_slug: node.slug, citable_type: "Tree", citable_id: foreign_tree.id },
             headers: headers, as: :json
        foreign = [ response.status, response.parsed_body ]

        post "/api/v1/codex/citations",
             params: { codex_node_slug: node.slug, citable_type: "Tree", citable_id: 0 },
             headers: headers.merge("Idempotency-Key" => SecureRandom.uuid), as: :json

        expect([ response.status, response.parsed_body ]).to eq(foreign)
      end
    end


    # Non-JSON requests bypass the Idempotency-Key gate; the cache helpers
    # all early-return `nil` for blank keys (covers L124/L131/L137 branches).
    it "creates the citation without Idempotency-Key for form-encoded requests" do
      post "/api/v1/codex/citations",
           params: { codex_node_slug: node.slug, citable_type: "Tree", citable_id: tree.id },
           headers: { "Authorization" => "Bearer #{token}" }

      expect(response).to have_http_status(:created)
      expect(Codex::Citation.exists?(codex_node_id: node.id, citable_id: tree.id)).to be(true)
    end
  end

  describe "DELETE /api/v1/codex/citations/:id" do
    let!(:citation) do
      create(:codex_citation, node: node, created_by_user: forester,
             citable_type: "Tree", citable_id: tree.id)
    end

    it "lets the author delete within the 24 h grace" do
      delete "/api/v1/codex/citations/#{citation.id}", headers: headers

      expect(response).to have_http_status(:no_content)
      expect(Codex::Citation.find_by(id: citation.id)).to be_nil
    end

    it "blocks a non-author forester" do
      other = create(:user, organization: org, role: :forester)
      other_token = other.generate_token_for(:api_access)
      delete "/api/v1/codex/citations/#{citation.id}",
             headers: headers.merge("Authorization" => "Bearer #{other_token}")
      expect(response).to have_http_status(:forbidden)
    end

    it "lets admin+ delete past the grace window" do
      citation.update_columns(created_at: 25.hours.ago)
      admin_token = admin.generate_token_for(:api_access)
      delete "/api/v1/codex/citations/#{citation.id}",
             headers: headers.merge("Authorization" => "Bearer #{admin_token}")
      expect(response).to have_http_status(:no_content)
    end

    # [SEC.26] Дзеркальна половина: `admin_or_above?` не ніс org-умови, тож admin
    # будь-якої організації зносив би будь-яку цитату на платформі.
    it "не дає admin'у чужої організації знести цитату" do
      foreign_admin = create(:user, :admin, organization: create(:organization))

      expect {
        delete "/api/v1/codex/citations/#{citation.id}",
               headers: headers.merge("Authorization" => "Bearer #{foreign_admin.generate_token_for(:api_access)}")
      }.not_to change(Codex::Citation, :count)

      # 404, а не 403 — інакше код відповіді сам відповідає, чи цитата існує.
      expect(response).to have_http_status(:not_found)
    end

    # ⚠️ Тут стояло `expect(ActionCable.server).not_to receive(:broadcast)` —
    # вакуумне НАЗАВЖДИ, бо сирий ActionCable заборонений репо-широко
    # (`spec/security/no_raw_action_cable_spec.rb`, UI.2 descope). Назва обіцяла
    # перевірку «skips broadcast», а довести приклад може лише 204 на знищеному
    # citable — тепер вона це й каже.
    it "returns 204 when the citable target has been destroyed" do
      tree.destroy!

      delete "/api/v1/codex/citations/#{citation.id}", headers: headers
      expect(response).to have_http_status(:no_content)
    end
  end
end
