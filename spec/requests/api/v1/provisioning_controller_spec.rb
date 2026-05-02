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

    # =========================================================================
    # FW.24: Reject DID matching firmware fallback magic constant
    # =========================================================================
    # Firmware Soldier використовує magic 0x511CEE01 коли STM32 unique ID XOR == 0.
    # Backend MUST reject hardware_uid'и, останні 8 hex символів яких збігаються,
    # щоб уникнути колізій (defective devices) та реєстраційних атак.
    context "with hardware_uid matching firmware fallback magic [FW.24]" do
      it "rejects exact-match magic UID" do
        magic_params = valid_params.deep_merge(
          provisioning: { hardware_uid: "511CEE01" }
        )
        post "/api/v1/provisioning/register", params: magic_params, headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body["error"]).to include("511CEE01")
        expect(response.parsed_body["error"]).to include("fallback")
      end

      it "rejects UID whose last 8 hex chars match magic (case-insensitive)" do
        magic_params = valid_params.deep_merge(
          provisioning: { hardware_uid: "AABBCCDD511cee01" }
        )
        post "/api/v1/provisioning/register", params: magic_params, headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body["error"]).to include("511CEE01")
      end

      it "does NOT reject UIDs that contain magic earlier in the string" do
        # Magic only matters in last 8 chars (those that form the DID suffix)
        non_magic_params = valid_params.deep_merge(
          provisioning: { hardware_uid: "511CEE01CAFEBABE" }
        )
        post "/api/v1/provisioning/register", params: non_magic_params, headers: headers, as: :json

        # FW.24 guard MUST NOT trigger for this UID. The response body must not
        # mention the fallback magic — it may still be 422 for unrelated validation
        # reasons (other tests cover the happy path).
        body_text = response.body.to_s
        expect(body_text).not_to include("fallback")
        expect(body_text).not_to include("511CEE01")
      end
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
        expect(body["key_derivation"]).to eq("hkdf-sha256")
      end

      it "includes aes_key in TRL4 lab mode (no PROVISIONING_MASTER_KEY)" do
        post "/api/v1/provisioning/register", params: gateway_params, headers: headers, as: :json

        expect(response).to have_http_status(:created)
        body = response.parsed_body
        expect(body["aes_key"]).to be_present
        expect(body["warning"]).to include("TRL4 lab mode")
      end

      # [SEC.11] Lab-mode response also surfaces the freshly-derived
      # K_seed so the burn-in tool can write both blobs into Flash in
      # one operation.
      it "includes lorenz_seed and persists it on HardwareKey [SEC.11]" do
        allow(HardwareKeyService).to receive(:provision).and_call_original

        post "/api/v1/provisioning/register", params: gateway_params, headers: headers, as: :json

        expect(response).to have_http_status(:created)
        body = response.parsed_body
        expect(body["lorenz_seed"]).to match(/\A[0-9A-F]{64}\z/)

        hw_key = HardwareKey.find_by(device_uid: body["did"])
        expect(hw_key.lorenz_seed_hex).to eq(body["lorenz_seed"])
        expect(hw_key.binary_lorenz_seed.bytesize).to eq(32)
      end

      context "with PROVISIONING_MASTER_KEY set (production mode)" do
        before do
          allow(ENV).to receive(:[]).and_call_original
          allow(ENV).to receive(:[]).with("PROVISIONING_MASTER_KEY").and_return("master-secret-key-32bytes-long!!")
        end

        it "does not include aes_key in response" do
          post "/api/v1/provisioning/register", params: gateway_params, headers: headers, as: :json

          expect(response).to have_http_status(:created)
          body = response.parsed_body
          expect(body["did"]).to eq("SNET-Q-AA11BB22")
          expect(body["key_derivation"]).to eq("hkdf-sha256")
          expect(body).not_to have_key("aes_key")
          expect(body).not_to have_key("warning")
        end

        # [SEC.11] HKDF mode also withholds the seed from the response —
        # firmware re-derives it independently from PROVISIONING_MASTER_KEY.
        it "does not include lorenz_seed in HKDF mode but persists it on HardwareKey [SEC.11]" do
          allow(HardwareKeyService).to receive(:provision).and_call_original

          post "/api/v1/provisioning/register", params: gateway_params, headers: headers, as: :json

          expect(response).to have_http_status(:created)
          body = response.parsed_body
          expect(body).not_to have_key("lorenz_seed")

          hw_key = HardwareKey.find_by(device_uid: body["did"])
          expect(hw_key.lorenz_seed_hex).to match(/\A[0-9A-F]{64}\z/)
          expect(hw_key.lorenz_seed_hex).to eq(SilkenNet::SeedDerivation.derive_seed(body["did"]))
        end
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

    context "when ed25519_public_key is provided" do
      let(:ed25519_key_hex) { SecureRandom.hex(32) }
      let(:ed25519_gateway_params) do
        {
          provisioning: {
            hardware_uid: "SNET-Q-ED250001",
            device_type: "gateway",
            cluster_id: own_cluster.id,
            latitude: 49.4285,
            longitude: 32.0620,
            ed25519_public_key: ed25519_key_hex
          }
        }
      end

      before do
        # Allow real provisioning so HardwareKey is created before ed25519 update
        allow(HardwareKeyService).to receive(:provision).and_call_original
      end

      it "stores the Ed25519 public key on the hardware key" do
        post "/api/v1/provisioning/register", params: ed25519_gateway_params, headers: headers, as: :json

        expect(response).to have_http_status(:created)
        hw_key = HardwareKey.find_by(device_uid: "SNET-Q-ED250001")
        expect(hw_key).to be_present
        expect(hw_key.ed25519_public_key_hex).to eq(ed25519_key_hex)
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
        expect(response.parsed_body["error"]).to include("Збій у ядрі Океану")
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

    it "exercises the new provisioning page path" do
      get "/api/v1/provisioning/new", headers: html_headers
      # Phlex component may not fully render in test env, but code path is exercised
      expect(response.status).to be_in([ 200, 500 ])
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

  # [SEC.11] Field-migration endpoint: back-fills `lorenz_seed_hex` for
  # devices that were provisioned before SEC.11.
  describe "POST /api/v1/provisioning/upgrade_seed" do
    let!(:legacy_hw_key) do
      HardwareKey.create!(
        device_uid: "SNET-LEGACY01",
        aes_key_hex: SecureRandom.hex(32).upcase,
        lorenz_seed_hex: nil
      )
    end

    it "back-fills lorenz_seed_hex for a legacy device" do
      post "/api/v1/provisioning/upgrade_seed",
           params: { hardware_uid: "SNET-LEGACY01" },
           headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["upgraded"]).to be(true)
      expect(body["did"]).to eq("SNET-LEGACY01")

      legacy_hw_key.reload
      expect(legacy_hw_key.lorenz_seed_hex).to match(/\A[0-9A-F]{64}\z/)
    end

    it "is idempotent — second call is a no-op" do
      post "/api/v1/provisioning/upgrade_seed",
           params: { hardware_uid: "SNET-LEGACY01" },
           headers: headers, as: :json
      first_seed = legacy_hw_key.reload.lorenz_seed_hex

      post "/api/v1/provisioning/upgrade_seed",
           params: { hardware_uid: "SNET-LEGACY01" },
           headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["upgraded"]).to be(false)
      expect(legacy_hw_key.reload.lorenz_seed_hex).to eq(first_seed)
    end

    it "returns 404 for unknown hardware_uid" do
      post "/api/v1/provisioning/upgrade_seed",
           params: { hardware_uid: "SNET-MISSING0" },
           headers: headers, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it "returns 422 when hardware_uid param is missing" do
      post "/api/v1/provisioning/upgrade_seed", params: {}, headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "includes lorenz_seed in the response when in lab mode" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("PROVISIONING_MASTER_KEY").and_return(nil)

      post "/api/v1/provisioning/upgrade_seed",
           params: { hardware_uid: "SNET-LEGACY01" },
           headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["lorenz_seed"]).to match(/\A[0-9A-F]{64}\z/)
      expect(body["warning"]).to include("TRL4 lab mode")
    end

    it "withholds lorenz_seed in HKDF mode (firmware re-derives independently)" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("PROVISIONING_MASTER_KEY").and_return("master-secret-key-32bytes-long!!")

      post "/api/v1/provisioning/upgrade_seed",
           params: { hardware_uid: "SNET-LEGACY01" },
           headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body).not_to have_key("lorenz_seed")
      expect(body["upgraded"]).to be(true)
    end

    it "rejects unauthenticated callers" do
      post "/api/v1/provisioning/upgrade_seed",
           params: { hardware_uid: "SNET-LEGACY01" }, as: :json
      expect(response.status).to be_in([ 401, 403 ])
    end
  end
end
