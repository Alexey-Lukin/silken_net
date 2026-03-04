# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::FirmwaresController, type: :request do
  let(:organization) { create(:organization) }
  let(:admin) { create(:user, :admin, organization: organization) }
  let(:api_token) { admin.generate_token_for(:api_access) }
  let(:headers) { { "Authorization" => "Bearer #{api_token}" } }

  describe "POST /api/v1/firmwares/:id/deploy" do
    let!(:firmware) do
      BioContractFirmware.create!(version: "2.0.0", bytecode_payload: "AABBCCDD")
    end

    before do
      allow(OtaTransmissionWorker).to receive(:perform_async)
    end

    it "passes canary_percentage to OtaTransmissionWorker" do
      post "/api/v1/firmwares/#{firmware.id}/deploy",
           params: { canary_percentage: 5 }, headers: headers, as: :json

      expect(response).to have_http_status(:accepted)
      expect(response.parsed_body["canary_percentage"]).to eq(5)
      expect(OtaTransmissionWorker).to have_received(:perform_async)
        .with(firmware.id, nil, nil, 5)
    end

    it "defaults canary_percentage to 100 when not specified" do
      post "/api/v1/firmwares/#{firmware.id}/deploy",
           headers: headers, as: :json

      expect(response).to have_http_status(:accepted)
      expect(response.parsed_body["canary_percentage"]).to eq(100)
    end

    it "clamps canary_percentage to valid range" do
      post "/api/v1/firmwares/#{firmware.id}/deploy",
           params: { canary_percentage: 200 }, headers: headers, as: :json

      expect(response).to have_http_status(:accepted)
      expect(response.parsed_body["canary_percentage"]).to eq(100)
    end
  end
end
