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
  end
end
