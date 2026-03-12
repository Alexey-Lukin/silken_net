# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::AlertsController, type: :request do
  before do
    allow(AlertNotificationWorker).to receive(:perform_async)
    allow_any_instance_of(EwsAlert).to receive(:broadcast_status_change)
    allow_any_instance_of(EwsAlert).to receive(:dispatch_notifications!)
    allow_any_instance_of(EwsAlert).to receive(:close_associated_maintenance!)
    allow_any_instance_of(EwsAlert).to receive(:broadcast_alert_update)
  end

  let(:organization) { create(:organization) }
  let(:other_organization) { create(:organization) }
  let(:user) { create(:user, :forester, organization: organization) }
  let(:api_token) { user.generate_token_for(:api_access) }
  let(:headers) { { "Authorization" => "Bearer #{api_token}" } }

  let(:own_cluster) { create(:cluster, organization: organization) }
  let(:other_cluster) { create(:cluster, organization: other_organization) }
  let!(:own_alert) { create(:ews_alert, :drought, cluster: own_cluster) }
  let!(:other_alert) { create(:ews_alert, :fire, cluster: other_cluster) }

  describe "GET /api/v1/alerts" do
    it "returns only alerts belonging to the user's organization" do
      get "/api/v1/alerts", headers: headers, as: :json
      expect(response).to have_http_status(:ok)

      ids = response.parsed_body["data"].map { |a| a["id"] }
      expect(ids).to include(own_alert.id)
      expect(ids).not_to include(other_alert.id)
    end
  end

  describe "PATCH /api/v1/alerts/:id/resolve" do
    it "resolves an alert belonging to the user's organization" do
      patch resolve_api_v1_alert_path(own_alert), headers: headers, as: :json
      expect(response).to have_http_status(:ok)
    end

    it "returns 404 for an alert from another organization" do
      patch resolve_api_v1_alert_path(other_alert), headers: headers, as: :json
      expect(response).to have_http_status(:not_found)
    end

    it "renders validation error when resolve! fails" do
      allow_any_instance_of(EwsAlert).to receive(:resolve!).and_return(false)

      patch resolve_api_v1_alert_path(own_alert), headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "redirects on successful HTML resolve" do
      patch resolve_api_v1_alert_path(own_alert),
            headers: { "Authorization" => "Bearer #{api_token}", "Accept" => "text/html" }
      expect(response).to have_http_status(:redirect)
    end
  end

  context "with format.html responses" do
    let(:html_headers) do
      { "Authorization" => "Bearer #{api_token}", "Accept" => "text/html" }
    end

    it "renders HTML for index" do
      get "/api/v1/alerts", headers: html_headers
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("text/html")
    end
  end
end
