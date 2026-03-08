# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::MaintenanceRecordPhotosController, type: :request do
  let(:organization) { create(:organization) }
  let(:other_organization) { create(:organization) }
  let(:forester) { create(:user, :forester, organization: organization) }
  let(:investor) { create(:user, :investor, organization: organization) }
  let(:api_token) { forester.generate_token_for(:api_access) }
  let(:investor_token) { investor.generate_token_for(:api_access) }
  let(:headers) { { "Authorization" => "Bearer #{api_token}" } }
  let(:investor_headers) { { "Authorization" => "Bearer #{investor_token}" } }

  let!(:own_cluster) { create(:cluster, organization: organization) }
  let!(:other_cluster) { create(:cluster, organization: other_organization) }

  let(:own_tree) { create(:tree, cluster: own_cluster) }
  let(:other_tree) { create(:tree, cluster: other_cluster) }

  before do
    allow_any_instance_of(Tree).to receive(:broadcast_map_update)
    allow(EcosystemHealingWorker).to receive(:perform_async)
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

    context "when as JSON" do
      it "purges the photo and returns ok" do
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

      it "returns 404 for a non-existent photo" do
        delete "/api/v1/maintenance_records/#{record.id}/photos/999999",
               headers: headers, as: :json

        expect(response).to have_http_status(:not_found)
      end
    end

    context "when as HTML" do
      it "redirects after purging the photo" do
        record.photos.attach(
          io: StringIO.new("fake-image-data"),
          filename: "evidence.jpg",
          content_type: "image/jpeg"
        )
        photo = record.photos.first

        delete "/api/v1/maintenance_records/#{record.id}/photos/#{photo.id}",
               headers: headers

        expect(response).to have_http_status(:redirect)
      end
    end

    it "returns 404 for a record from another organization" do
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

    it "returns 403 for non-forester users" do
      test_record = MaintenanceRecord.create!(
        maintainable: own_tree,
        user: forester,
        action_type: :inspection,
        performed_at: 1.hour.ago,
        notes: "Test inspection for auth check."
      )
      test_record.photos.attach(
        io: StringIO.new("fake-image-data"),
        filename: "evidence.jpg",
        content_type: "image/jpeg"
      )
      photo = test_record.photos.first

      delete "/api/v1/maintenance_records/#{test_record.id}/photos/#{photo.id}",
             headers: investor_headers, as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it "returns 401 without authentication" do
      delete "/api/v1/maintenance_records/#{record.id}/photos/999", as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
