# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::M2mAuthController, type: :request do
  let(:organization) { create(:organization) }
  let!(:admin_user) { create(:user, :admin, organization: organization) }
  let(:cluster) { create(:cluster, organization: organization) }
  let(:gateway) { create(:gateway, cluster: cluster) }

  let(:keypair) { Ed25519Crypto::SigningService.generate_keypair }
  let(:seed_hex) { keypair[:seed_hex] }
  let(:public_key_hex) { keypair[:public_key_hex] }

  let!(:hardware_key) do
    HardwareKey.create!(
      device_uid: gateway.uid,
      aes_key_hex: SecureRandom.hex(32).upcase,
      ed25519_public_key_hex: public_key_hex
    )
  end

  before do
    ActiveRecord::Encryption.configure(
      primary_key: "test-primary-key-that-is-long-enough",
      deterministic_key: "test-deterministic-key-long-enough",
      key_derivation_salt: "test-salt-value-for-derivation-ok"
    )
  end

  describe "POST /api/v1/auth/m2m_token" do
    let(:timestamp) { Time.current.iso8601 }
    let(:message) { "#{gateway.uid}:#{timestamp}" }
    let(:signature) { Ed25519Crypto::SigningService.sign(seed_hex, message) }

    context "with valid Ed25519 signature" do
      it "issues an M2M token" do
        post "/api/v1/auth/m2m_token",
             params: { did: gateway.uid, timestamp: timestamp, signature: signature },
             as: :json

        expect(response).to have_http_status(:created)
        body = response.parsed_body
        expect(body["token"]).to be_present
        expect(body["device_uid"]).to eq(gateway.uid)
        expect(body["token_type"]).to eq("Bearer")
      end
    end

    context "with invalid signature" do
      it "returns 401 unauthorized" do
        post "/api/v1/auth/m2m_token",
             params: { did: gateway.uid, timestamp: timestamp, signature: "a" * 128 },
             as: :json

        expect(response).to have_http_status(:unauthorized)
        expect(response.parsed_body["error"]).to include("підпис")
      end
    end

    context "with expired timestamp" do
      let(:old_timestamp) { 10.minutes.ago.iso8601 }
      let(:old_message) { "#{gateway.uid}:#{old_timestamp}" }
      let(:old_signature) { Ed25519Crypto::SigningService.sign(seed_hex, old_message) }

      it "returns 401 unauthorized" do
        post "/api/v1/auth/m2m_token",
             params: { did: gateway.uid, timestamp: old_timestamp, signature: old_signature },
             as: :json

        expect(response).to have_http_status(:unauthorized)
        expect(response.parsed_body["error"]).to include("Timestamp")
      end
    end

    context "with unknown device" do
      it "returns 404 not found" do
        post "/api/v1/auth/m2m_token",
             params: { did: "SNET-Q-UNKNOWN00", timestamp: timestamp, signature: signature },
             as: :json

        expect(response).to have_http_status(:not_found)
      end
    end

    context "with device without Ed25519 key" do
      before { hardware_key.update_columns(ed25519_public_key_hex: nil) }

      it "returns 422 unprocessable" do
        post "/api/v1/auth/m2m_token",
             params: { did: gateway.uid, timestamp: timestamp, signature: signature },
             as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body["error"]).to include("Ed25519")
      end
    end

    context "with malformed timestamp" do
      it "returns 400 bad request" do
        post "/api/v1/auth/m2m_token",
             params: { did: gateway.uid, timestamp: "not-a-date", signature: signature },
             as: :json

        expect(response).to have_http_status(:bad_request)
      end
    end

    context "with malformed hex signature (SigningError)" do
      it "returns 401 instead of 500" do
        post "/api/v1/auth/m2m_token",
             params: { did: gateway.uid, timestamp: timestamp, signature: "not-hex-!!!" },
             as: :json

        expect(response).to have_http_status(:unauthorized)
        expect(response.parsed_body["error"]).to include("signature")
      end
    end

    context "with M2M replay attack prevention" do
      it "rejects duplicate M2M auth with same signature" do
        # First request — succeeds
        post "/api/v1/auth/m2m_token",
             params: { did: gateway.uid, timestamp: timestamp, signature: signature },
             as: :json
        expect(response).to have_http_status(:created)

        # Replay — same DID, timestamp, signature
        post "/api/v1/auth/m2m_token",
             params: { did: gateway.uid, timestamp: timestamp, signature: signature },
             as: :json
        expect(response).to have_http_status(:unauthorized)
        expect(response.parsed_body["error"]).to include("Replay")
      end

      it "allows new auth with different timestamp and signature" do
        post "/api/v1/auth/m2m_token",
             params: { did: gateway.uid, timestamp: timestamp, signature: signature },
             as: :json
        expect(response).to have_http_status(:created)

        # New timestamp generates a different signature
        new_timestamp = (Time.current + 1.second).iso8601
        new_message = "#{gateway.uid}:#{new_timestamp}"
        new_signature = Ed25519Crypto::SigningService.sign(seed_hex, new_message)

        post "/api/v1/auth/m2m_token",
             params: { did: gateway.uid, timestamp: new_timestamp, signature: new_signature },
             as: :json
        expect(response).to have_http_status(:created)
      end
    end

    it "does not require Bearer token authentication" do
      post "/api/v1/auth/m2m_token",
           params: { did: gateway.uid, timestamp: timestamp, signature: signature },
           as: :json

      expect(response).not_to have_http_status(:unauthorized)
    end

    context "when device is not linked to an organization" do
      it "returns 422 when device has no organization in hierarchy" do
        orphan_uid = "SNET-ORPHAN-0001"
        HardwareKey.create!(
          device_uid: orphan_uid,
          aes_key_hex: SecureRandom.hex(32).upcase,
          ed25519_public_key_hex: public_key_hex
        )
        ts = Time.current.iso8601
        sig = Ed25519Crypto::SigningService.sign(seed_hex, "#{orphan_uid}:#{ts}")

        post "/api/v1/auth/m2m_token",
             params: { did: orphan_uid, timestamp: ts, signature: sig },
             as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body["error"]).to include("організації")
      end
    end

    context "when organization has no users" do
      it "returns 422 when organization has no users for token issuance" do
        empty_org = create(:organization)
        empty_cluster = create(:cluster, organization: empty_org)
        empty_gw = create(:gateway, cluster: empty_cluster)
        HardwareKey.create!(
          device_uid: empty_gw.uid,
          aes_key_hex: SecureRandom.hex(32).upcase,
          ed25519_public_key_hex: public_key_hex
        )
        ts = Time.current.iso8601
        sig = Ed25519Crypto::SigningService.sign(seed_hex, "#{empty_gw.uid}:#{ts}")

        post "/api/v1/auth/m2m_token",
             params: { did: empty_gw.uid, timestamp: ts, signature: sig },
             as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body["error"]).to include("користувачів")
      end
    end
  end
end
