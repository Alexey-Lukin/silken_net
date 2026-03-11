# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::ProvisioningController, type: :request do
  let(:organization) { create(:organization) }
  let(:other_organization) { create(:organization) }
  let(:forester) { create(:user, :forester, organization: organization) }
  let(:api_token) { forester.generate_token_for(:api_access) }
  let(:headers) { { "Authorization" => "Bearer #{api_token}" } }

  let!(:own_cluster) { create(:cluster, organization: organization) }
  let!(:other_cluster) { create(:cluster, organization: other_organization) }
  let(:tree_family) { create(:tree_family) }

  before do
    ActiveRecord::Encryption.configure(
      primary_key: "test-primary-key-that-is-long-enough",
      deterministic_key: "test-deterministic-key-long-enough",
      key_derivation_salt: "test-salt-value-for-derivation-ok"
    )
    allow(HardwareKeyService).to receive(:provision).and_return(SecureRandom.hex(32).upcase)
    allow(PeaqRegistrationWorker).to receive(:perform_async)
    allow_any_instance_of(Tree).to receive(:broadcast_map_update)
  end

  describe "POST /api/v1/provisioning/register" do
    let(:valid_params) do
      {
        provisioning: {
          hardware_uid: "AABBCCDD11223344",
          device_type: "gateway",
          cluster_id: own_cluster.id,
          latitude: 49.4285,
          longitude: 32.0620
        }
      }
    end

    it "rejects duplicate hardware_uid registration" do
      HardwareKey.create!(
        device_uid: "AABBCCDD11223344",
        aes_key_hex: SecureRandom.hex(32).upcase
      )

      post "/api/v1/provisioning/register", params: valid_params, headers: headers, as: :json

      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body["error"]).to include("вже зареєстрований")
    end

    context "when registering a new gateway" do
      let(:gateway_params) do
        {
          provisioning: {
            hardware_uid: "SNET-Q-AA11BB22",
            device_type: "gateway",
            cluster_id: own_cluster.id,
            latitude: 49.4285,
            longitude: 32.0620
          }
        }
      end

      it "successfully registers a gateway device" do
        post "/api/v1/provisioning/register", params: gateway_params, headers: headers, as: :json

        expect(response).to have_http_status(:created)
        body = response.parsed_body
        expect(body["did"]).to eq("SNET-Q-AA11BB22")
        expect(body["aes_key"]).to be_present
      end
    end

    context "when registering a new tree" do
      let(:tree_params) do
        {
          provisioning: {
            hardware_uid: "AABB11223344CCDD",
            device_type: "tree",
            cluster_id: own_cluster.id,
            family_id: tree_family.id,
            latitude: 49.4285,
            longitude: 32.0620
          }
        }
      end

      it "successfully registers a tree device with auto-generated DID" do
        post "/api/v1/provisioning/register", params: tree_params, headers: headers, as: :json

        expect(response).to have_http_status(:created)
        body = response.parsed_body
        expect(body["did"]).to eq("SNET-3344CCDD")
        expect(body["aes_key"]).to be_present
      end

      it "enqueues PeaqRegistrationWorker for tree registration" do
        post "/api/v1/provisioning/register", params: tree_params, headers: headers, as: :json

        expect(response).to have_http_status(:created)
        expect(PeaqRegistrationWorker).to have_received(:perform_async).with(Tree.last.id)
      end
    end

    context "when registering a gateway" do
      it "does not enqueue PeaqRegistrationWorker" do
        gateway_params = {
          provisioning: {
            hardware_uid: "SNET-Q-BB22CC33",
            device_type: "gateway",
            cluster_id: own_cluster.id,
            latitude: 49.4285,
            longitude: 32.0620
          }
        }

        post "/api/v1/provisioning/register", params: gateway_params, headers: headers, as: :json

        expect(response).to have_http_status(:created)
        expect(PeaqRegistrationWorker).not_to have_received(:perform_async)
      end
    end

    context "when device_type is unknown" do
      let(:bad_type_params) do
        {
          provisioning: {
            hardware_uid: "AABBCCDD99887766",
            device_type: "quantum_sensor",
            cluster_id: own_cluster.id,
            latitude: 49.4285,
            longitude: 32.0620
          }
        }
      end

      it "returns internal server error" do
        post "/api/v1/provisioning/register", params: bad_type_params, headers: headers, as: :json

        expect(response).to have_http_status(:internal_server_error)
        expect(response.parsed_body["error"]).to include("Збій ініціації")
      end
    end

    context "when user is not a forester" do
      let(:investor) { create(:user, :investor, organization: organization) }
      let(:investor_token) { investor.generate_token_for(:api_access) }
      let(:investor_headers) { { "Authorization" => "Bearer #{investor_token}" } }

      it "returns forbidden" do
        post "/api/v1/provisioning/register", params: valid_params, headers: investor_headers, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end

    context "when device fails validation" do
      let(:invalid_gateway_params) do
        {
          provisioning: {
            hardware_uid: "INVALIDUID",
            device_type: "gateway",
            cluster_id: own_cluster.id,
            latitude: 49.4285,
            longitude: 32.0620
          }
        }
      end

      it "returns validation errors" do
        post "/api/v1/provisioning/register", params: invalid_gateway_params, headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body["errors"]).to be_present
      end
    end
  end

  describe "format.html responses" do
    let(:html_headers) do
      { "Authorization" => "Bearer #{api_token}", "Accept" => "text/html" }
    end

    it "renders HTML success after registering a gateway" do
      gateway_params = {
        provisioning: {
          hardware_uid: "SNET-Q-FF99EE88",
          device_type: "gateway",
          cluster_id: own_cluster.id,
          latitude: 49.4285,
          longitude: 32.0620
        }
      }

      post "/api/v1/provisioning/register", params: gateway_params, headers: html_headers
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("text/html")
    end

    it "renders HTML errors when device validation fails" do
      invalid_params = {
        provisioning: {
          hardware_uid: "INVALIDUID",
          device_type: "gateway",
          cluster_id: own_cluster.id,
          latitude: 49.4285,
          longitude: 32.0620
        }
      }

      post "/api/v1/provisioning/register", params: invalid_params, headers: html_headers
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("text/html")
    end
  end
end
