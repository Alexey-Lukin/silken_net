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

    it "filters by action_type" do
      get "/api/v1/maintenance_records", params: { action_type: "inspection" },
                                         headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      types = response.parsed_body["records"].map { |r| r["action_type"] }.uniq
      expect(types).to eq([ "inspection" ])
    end

    it "filters by hardware_verified" do
      own_record.update!(hardware_verified: true)
      get "/api/v1/maintenance_records", params: { verified: "1" },
                                         headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      ids = response.parsed_body["records"].map { |r| r["id"] }
      expect(ids).to include(own_record.id)
    end
  end

  describe "PATCH /api/v1/maintenance_records/:id/verify" do
    let(:record) do
      MaintenanceRecord.create!(
        maintainable: own_tree,
        user: forester,
        action_type: :inspection,
        performed_at: 1.hour.ago,
        notes: "Checking all sensor connectors for corrosion damage."
      )
    end

    it "marks the record as hardware_verified" do
      patch "/api/v1/maintenance_records/#{record.id}/verify",
            headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["hardware_verified"]).to be true
      expect(record.reload.hardware_verified).to be true
    end

    it "returns 404 for a record outside the user's organization" do
      other_user = create(:user, :forester, organization: other_organization)
      other_record = MaintenanceRecord.create!(
        maintainable: other_tree,
        user: other_user,
        action_type: :inspection,
        performed_at: 1.hour.ago,
        notes: "External inspection outside the organization boundary."
      )

      patch "/api/v1/maintenance_records/#{other_record.id}/verify",
            headers: headers, as: :json
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "DELETE /api/v1/maintenance_records/:maintenance_record_id/photos/:id" do
    let(:record) do
      MaintenanceRecord.create!(
        maintainable: own_tree,
        user: forester,
        action_type: :inspection,
        performed_at: 1.hour.ago,
        notes: "Routine inspection of the node completed successfully."
      )
    end

    it "purges the photo and returns ok" do
      # Attach a test photo using Active Storage test service
      record.photos.attach(
        io: StringIO.new("fake-image-data"),
        filename: "evidence.jpg",
        content_type: "image/jpeg"
      )
      photo = record.photos.first

      delete "/api/v1/maintenance_records/#{record.id}/photos/#{photo.id}",
             headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["message"]).to be_present
    end

    it "returns 404 for a photo on another organization's record" do
      other_user = create(:user, :forester, organization: other_organization)
      other_record = MaintenanceRecord.create!(
        maintainable: other_tree,
        user: other_user,
        action_type: :inspection,
        performed_at: 1.hour.ago,
        notes: "Inspection in a different organizational forest sector."
      )

      delete "/api/v1/maintenance_records/#{other_record.id}/photos/999",
             headers: headers, as: :json
      expect(response).to have_http_status(:not_found)
    end
  end

  context "format.html responses" do
    let(:html_headers) do
      { "Authorization" => "Bearer #{api_token}", "Accept" => "text/html" }
    end

    let!(:record) do
      MaintenanceRecord.create!(
        maintainable: own_tree,
        user: forester,
        action_type: :inspection,
        performed_at: 1.hour.ago,
        notes: "Routine inspection for HTML format test."
      )
    end

    it "renders HTML for index" do
      get "/api/v1/maintenance_records", headers: html_headers
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("text/html")
    end

    it "renders HTML for show" do
      get "/api/v1/maintenance_records/#{record.id}", headers: html_headers
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("text/html")
    end

    it "renders HTML for new" do
      get "/api/v1/maintenance_records/new", headers: html_headers
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("text/html")
    end

    it "renders HTML for new with pre-populated params" do
      get "/api/v1/maintenance_records/new",
        params: { maintainable_type: "Tree", maintainable_id: own_tree.id },
        headers: html_headers
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("text/html")
    end

    it "renders photos pagination page" do
      get "/api/v1/maintenance_records/#{record.id}/photos", headers: html_headers
      expect(response).to have_http_status(:ok)
    end
  end
end
