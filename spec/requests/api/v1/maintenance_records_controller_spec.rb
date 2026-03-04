# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::MaintenanceRecordsController, type: :request do
  let(:organization) { create(:organization) }
  let(:other_organization) { create(:organization) }
  let(:forester) { create(:user, :forester, organization: organization) }
  let(:api_token) { forester.generate_token_for(:api_access) }
  let(:headers) { { "Authorization" => "Bearer #{api_token}" } }

  let!(:own_cluster) { create(:cluster, organization: organization) }
  let!(:other_cluster) { create(:cluster, organization: other_organization) }
  let(:own_tree) { create(:tree, cluster: own_cluster) }
  let(:other_tree) { create(:tree, cluster: other_cluster) }

  before do
    allow_any_instance_of(Tree).to receive(:broadcast_map_update)
    allow(EcosystemHealingWorker).to receive(:perform_async)
  end

  describe "GET /api/v1/maintenance_records" do
    let!(:own_record) do
      MaintenanceRecord.create!(
        maintainable: own_tree,
        user: forester,
        action_type: :inspection,
        performed_at: 1.hour.ago,
        notes: "Routine inspection of the node completed successfully."
      )
    end

    let!(:other_record) do
      other_user = create(:user, :forester, organization: other_organization)
      MaintenanceRecord.create!(
        maintainable: other_tree,
        user: other_user,
        action_type: :cleaning,
        performed_at: 2.hours.ago,
        notes: "Cleaned the solar panels and sensors properly."
      )
    end

    it "returns only maintenance records from the user's organization" do
      get "/api/v1/maintenance_records", headers: headers, as: :json
      expect(response).to have_http_status(:ok)

      record_ids = response.parsed_body["records"].map { |r| r["id"] }
      expect(record_ids).to include(own_record.id)
      expect(record_ids).not_to include(other_record.id)
    end

    it "includes pagination metadata" do
      get "/api/v1/maintenance_records", headers: headers, as: :json
      expect(response).to have_http_status(:ok)

      expect(response.parsed_body).to have_key("pagy")
      expect(response.parsed_body["pagy"]).to include("page", "count", "pages")
    end
  end
end
