# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# ⚖️ [SEC.37, founder 2026-10-25] Момент візиту, вписаний рукою без зони, читається в зоні
# ДІЛЯНКИ цілі. Зону цих прикладів обрано так, щоб стара поведінка (UTC-парсинг) падала:
# «14:00» у Токіо (+9) — уже минуле, а прочитане як UTC — ще майбутнє, і валідація «не в
# майбутньому» відкидає запис. Пін зсуває зону ЗАСТОСУНКУ, не процесу (скіл `backend` #31).
RSpec.describe "Maintenance record — site time zone [SEC.37]", type: :request do
  let(:organization) { create(:organization) }
  let(:other_organization) { create(:organization) }
  let(:forester) { create(:user, :forester, organization: organization) }
  let(:headers) { { "Authorization" => "Bearer #{forester.generate_token_for(:api_access)}" } }
  let(:cluster) { create(:cluster, organization: organization, time_zone: "Asia/Tokyo") }
  let(:tree) { create(:tree, cluster: cluster) }

  before do
    silence_broadcasts!(:tree_map)
    allow(EcosystemHealingWorker).to receive(:perform_async)
  end

  def create_record(performed_at, target: tree)
    post "/maintenance_records",
         params: { maintenance_record: {
           maintainable_type: "Tree", maintainable_id: target.id, action_type: "inspection",
           performed_at: performed_at, notes: "Routine inspection of the node completed."
         } },
         headers: idempotent(headers), as: :json
  end

  it "reads a zone-less moment in the zone of the target's site" do
    travel_to(Time.utc(2026, 5, 23, 12, 0, 0)) do
      create_record("2026-05-23T14:00")

      expect(response).to have_http_status(:created)
      expect(MaintenanceRecord.last.performed_at).to eq(Time.utc(2026, 5, 23, 5, 0, 0))
    end
  end

  # Виміряний дефект із подання: о 16:30 за Києвом лісник вписує київські 14:00 — доти сервер
  # читав їх як 14:00 UTC, тобто як майбутнє, і відкидав запис «≤ 13:30».
  it "accepts Kyiv 14:00 entered at Kyiv 16:30 as 11:00 UTC" do
    cluster.update!(time_zone: "Europe/Kyiv")

    travel_to(Time.utc(2026, 10, 24, 13, 30, 0)) do
      create_record("2026-10-24T14:00")

      expect(response).to have_http_status(:created)
      expect(MaintenanceRecord.last.performed_at).to eq(Time.utc(2026, 10, 24, 11, 0, 0))
    end
  end

  it "keeps a moment with an explicit offset absolute, whatever the site zone" do
    travel_to(Time.utc(2026, 5, 23, 12, 0, 0)) do
      create_record("2026-05-23T10:00:00Z")

      expect(MaintenanceRecord.last.performed_at).to eq(Time.utc(2026, 5, 23, 10, 0, 0))
    end
  end

  it "re-reads an edited moment in the site zone too" do
    record = create(:maintenance_record, user: forester, maintainable: tree,
                                         performed_at: Time.utc(2026, 5, 20, 3, 0, 0))

    travel_to(Time.utc(2026, 5, 23, 12, 0, 0)) do
      patch "/maintenance_records/#{record.id}",
            params: { maintenance_record: { performed_at: "2026-05-22T09:00" } },
            headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(record.reload.performed_at).to eq(Time.utc(2026, 5, 22, 0, 0, 0))
    end
  end

  it "leaves the moment alone when an edit does not send it" do
    record = create(:maintenance_record, user: forester, maintainable: tree,
                                         performed_at: Time.utc(2026, 5, 20, 3, 0, 0))

    patch "/maintenance_records/#{record.id}",
          params: { maintenance_record: { notes: "Re-checked the anchor collar and the seal." } },
          headers: headers, as: :json

    expect(record.reload.performed_at).to eq(Time.utc(2026, 5, 20, 3, 0, 0))
  end

  describe "the new-record form" do
    let(:html_headers) { headers.merge("Accept" => "text/html") }

    it "names the site zone of its own target and prefills its local now" do
      travel_to(Time.utc(2026, 5, 23, 12, 0, 0)) do
        get "/maintenance_records/new", params: { maintainable_type: "Tree", maintainable_id: tree.id },
                                        headers: html_headers

        expect(response.body).to include("Asia/Tokyo")
        expect(response.body).to include('value="2026-05-23T21:00"')
      end
    end

    # Префіл бере ціль із параметрів без гарда — зона чужої ділянки не друкується, і «зараз»
    # не підставляється: це було б і оракулом, і тихим зсувом.
    it "does not print the zone of a foreign target" do
      foreign = create(:tree, cluster: create(:cluster, organization: other_organization,
                                                        time_zone: "America/Manaus"))

      get "/maintenance_records/new", params: { maintainable_type: "Tree", maintainable_id: foreign.id },
                                      headers: html_headers

      expect(response.body).not_to include("America/Manaus")
      expect(response.body).to include(ERB::Util.html_escape(I18n.t("maintenance.form.performed_at_zone_unknown")))
    end

    # Тип звіряється ДО `record.maintainable`: інакше названий клієнтом клас став би оракулом
    # існування рядка в будь-якій таблиці (SEC.36-B) — тут це був би ще й 500 на `cluster_id`.
    it "does not resolve a target of a type outside the allowlist" do
      get "/maintenance_records/new", params: { maintainable_type: "User", maintainable_id: forester.id },
                                      headers: html_headers

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(ERB::Util.html_escape(I18n.t("maintenance.form.performed_at_zone_unknown")))
    end
  end
end
