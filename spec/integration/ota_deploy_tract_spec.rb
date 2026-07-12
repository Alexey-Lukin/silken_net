# frozen_string_literal: true

require "rails_helper"

# [SEC.20 Rails-half] Шов-тест deploy-тракту: HTTP deploy → Ota::DeploymentDispatcherService
# fan-out → РЕАЛЬНИЙ OtaTransmissionWorker (drain) → CoAP-чанки → gateway lifecycle.
#
# Клас бага, який цей файл вбиває назавжди: «два зелені кінці, мертвий шов» —
# контролер-спека мокала воркер із ЗМІЩЕНИМИ аргументами, воркер-спека кликала
# правильні, і жоден тест не проганяв обидва кінці разом (00_07 SEC.20,
# знахідка 2026-07-12). Тут мокнуто лише мережевий край (CoapClient/Turbo);
# пакування (OtaPackagerService + FW.23 HMAC-трейлер) і шифрування — реальні.
RSpec.describe "OTA deploy tract (SEC.20 Rails-half)", type: :request do
  let(:organization) { create(:organization) }
  let(:admin) { create(:user, :admin, organization: organization) }
  let(:headers) { { "Authorization" => "Bearer #{admin.generate_token_for(:api_access)}" } }
  let(:cluster) { create(:cluster, organization: organization) }
  let!(:gateway) { create(:gateway, cluster: cluster, state: :idle) }
  let!(:key_record) { create(:hardware_key, device_uid: gateway.uid) }
  let!(:firmware) { create(:bio_contract_firmware, bytecode_payload: "AB" * 64) }

  before do
    OtaTransmissionWorker.clear
    allow(CoapClient).to receive(:put).and_return(double(success?: true, code: "2.04"))
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
  end

  it "drives the full tract: deploy → fan-out → real worker chunks → gateway completes" do
    post "/api/v1/firmwares/#{firmware.id}/deploy",
         params: { cluster_id: cluster.id }, headers: headers, as: :json

    expect(response).to have_http_status(:accepted)
    expect(OtaTransmissionWorker.jobs.sole["args"]).to eq([ gateway.uid, "firmware", firmware.id, 0, 0 ])

    # drain жене РЕАЛЬНИЙ perform крізь увесь ланцюг чанків (self-scheduling
    # perform_in у fake-режимі лягає в ту саму чергу) — аргумент-паритет
    # контролер↔воркер доведено виконанням, не дзеркальним моком.
    # Prosopite-пауза: N однакових find_by! тут = N окремих job-виконань
    # в одному спек-прикладі, не реальний N+1.
    begin
      Prosopite.pause if defined?(Prosopite)
      OtaTransmissionWorker.drain
    ensure
      Prosopite.resume if defined?(Prosopite)
    end

    expect(CoapClient).to have_received(:put).at_least(:once)
    gateway.reload
    expect(gateway.state).to eq("idle")
    expect(gateway.firmware_version).to eq(firmware.version)
    expect(cluster.reload.ota_version_hiwater).to eq(firmware.id)
    expect(firmware.reload.is_active).to be(true)
  end

  it "replaying the same campaign after completion is rejected by the hiwater guard" do
    post "/api/v1/firmwares/#{firmware.id}/deploy",
         params: { cluster_id: cluster.id }, headers: headers, as: :json
    begin
      Prosopite.pause if defined?(Prosopite)
      OtaTransmissionWorker.drain
    ensure
      Prosopite.resume if defined?(Prosopite)
    end

    post "/api/v1/firmwares/#{firmware.id}/deploy",
         params: { cluster_id: cluster.id }, headers: headers, as: :json

    expect(response).to have_http_status(:unprocessable_content)
    expect(OtaTransmissionWorker.jobs).to be_empty
  end
end
