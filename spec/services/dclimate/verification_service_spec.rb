# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Dclimate::VerificationService, type: :service do
  let(:cluster) { create(:cluster) }
  let(:tree) { create(:tree, cluster: cluster) }
  let(:organization) { cluster.organization }

  before do
    allow(AlertNotificationWorker).to receive(:perform_async)
    silence_broadcasts!(:alert_notify, :alert_update, :alert_new)
    allow_any_instance_of(EwsAlert).to receive(:schedule_satellite_verification!)
    allow(InsurancePayoutWorker).to receive(:perform_async)
    allow(BurnCarbonTokensWorker).to receive(:perform_async)
  end

  describe "#perform" do
    context "when satellite confirms fire (fire_confirmed)" do
      let(:alert) { create(:ews_alert, :fire, cluster: cluster, tree: tree) }
      let(:service) { described_class.new(alert) }

      before do
        allow(service).to receive(:query_dclimate_api).and_return(:fire_confirmed)
      end

      it "updates satellite_status to verified" do
        service.perform
        alert.reload
        expect(alert).to be_satellite_verified
      end

      it "sets dclimate_ref" do
        service.perform
        alert.reload
        expect(alert.dclimate_ref).to start_with("dclimate:")
      end

      it "triggers InsurancePayoutWorker for triggered insurances" do
        insurance = create(:parametric_insurance, :triggered, cluster: cluster, organization: organization)
        service.perform
        expect(InsurancePayoutWorker).to have_received(:perform_async).with(insurance.id)
      end

      it "does not trigger payout when no triggered insurances exist" do
        service.perform
        expect(InsurancePayoutWorker).not_to have_received(:perform_async)
      end
    end

    context "when satellite sees clear sky (clear_sky_no_fire)" do
      let(:alert) { create(:ews_alert, :fire, cluster: cluster, tree: tree) }
      let(:service) { described_class.new(alert) }

      before do
        allow(service).to receive(:query_dclimate_api).and_return(:clear_sky_no_fire)
      end

      it "updates satellite_status to rejected_fraud" do
        service.perform
        alert.reload
        expect(alert).to be_satellite_rejected_fraud
      end

      it "sets dclimate_ref" do
        service.perform
        alert.reload
        expect(alert.dclimate_ref).to start_with("dclimate:")
      end

      it "triggers BurnCarbonTokensWorker for active NaaS contracts" do
        contract = create(:naas_contract, cluster: cluster, organization: organization)
        service.perform
        expect(BurnCarbonTokensWorker).to have_received(:perform_async)
          .with(organization.id, contract.id, tree.id)
      end

      # [ARCH.53/B2] Slash enqueue ПЕРЕД update!: якщо commit вердикту падає (краш-проксі),
      # burn УЖЕ enqueue'нуто, а alert лишається :satellite_unverified → worker-retry переграє
      # ідемпотентно. Раніше update! йшов першим → краш до enqueue → guard early-return → slash
      # застрягав назавжди.
      it "enqueues slashing BEFORE persisting the rejected_fraud verdict (crash-window safety)" do
        contract = create(:naas_contract, cluster: cluster, organization: organization)
        allow(alert).to receive(:update!).and_raise(ActiveRecord::StatementInvalid, "simulated crash")

        expect { service.perform }.to raise_error(ActiveRecord::StatementInvalid)

        expect(BurnCarbonTokensWorker).to have_received(:perform_async)
          .with(organization.id, contract.id, tree.id)
        expect(alert.reload).to be_satellite_unverified
      end
    end

    # 🔴 [ARCH.82] Окремий результат від хмарності, і різниця несуча: хмарність
    # ЧЕКАЄ наступного прольоту (`OrbitalLagError` → Sidekiq-ретрай), бо небо
    # проясниться; координати не «проясняться» — алерт їх не набуде, тож той
    # самий шлях дав би вічний ретрай. Доти проблеми не існувало ЛИШЕ тому, що
    # `coordinates` вигадував `[0.0, 0.0]` і запит ішов у Гвінейську затоку —
    # супутниковий вирок про іншу півкулю лягав на алерт як доказ.
    context "when the alert has no coordinates at all (ARCH.82)" do
      let(:tree) { create(:tree, latitude: nil, longitude: nil) }
      let(:alert) do
        create(:ews_alert, alert_type: :fire_detected, severity: :medium, tree: tree, cluster: nil)
      end
      let(:service) { described_class.new(alert) }

      it "не ретраїть — пише термінальний inconclusive" do
        expect { service.perform }.not_to raise_error
        expect(alert.reload).to be_satellite_inconclusive
      end

      it "не питає dClimate узагалі — верифікувати нема чого" do
        allow(service).to receive(:fetch_firms_data)
        service.perform
        expect(service).not_to have_received(:fetch_firms_data)
      end

      # 🔴 Критична гілка — і провал гілкового покриття вказав саме на неї,
      # тобто на сценарій, який я не запінив: пожежа з `severity: critical`
      # БЕЗ координат. Тут життєва безпека не чекає ні орбіти, ні геоданих —
      # людський вердикт кличеться тим самим шляхом, що при затемненні, лише
      # привід інший. Без цього приклада гілка існувала б неперевіреною рівно
      # там, де ціна помилки найвища.
      context "when the alert is a critical fire" do
        let(:alert) do
          create(:ews_alert, alert_type: :fire_detected, severity: :critical, tree: tree, cluster: nil)
        end

        it "ескалює в негайний Field Audit, а не мовчить" do
          expect { service.perform }.not_to raise_error

          expect(alert.reload).to be_satellite_inconclusive
          expect(alert.resolution_log.last["key"]).to eq("obscured_critical_fire")
        end
      end
    end

    context "when satellite is obscured by clouds (obscured_by_clouds)" do
      before do
        allow(service).to receive(:query_dclimate_api).and_return(:obscured_by_clouds)
      end

      context "when critical fire alert [E.41] (no 48h wait)" do
        let(:alert) { create(:ews_alert, :fire, cluster: cluster, tree: tree) } # severity: critical
        let(:service) { described_class.new(alert) }

        it "escalates to immediate Field Audit (:inconclusive) instead of raising for retry" do
          expect { service.perform }.not_to raise_error
          expect(alert.reload).to be_satellite_inconclusive
          expect(alert.resolution_log.last["key"]).to eq("obscured_critical_fire")
          # Рендер-свідок: фраза збирається локаллю ГЛЯДАЧА в момент показу.
          I18n.with_locale(:uk) do
            expect(alert.resolution_texts.join).to include("негайний Field Audit")
          end
        end
      end

      context "when non-critical fire alert (orbital retry OK)" do
        let(:alert) do
          create(:ews_alert, alert_type: :fire_detected, severity: :medium, cluster: cluster, tree: tree)
        end
        let(:service) { described_class.new(alert) }

        it "raises Dclimate::OrbitalLagError for the 48h orbital window" do
          expect { service.perform }.to raise_error(
            Dclimate::OrbitalLagError, /Satellite pass obscured/
          )
        end

        it "does not change satellite_status (retry pending)" do
          expect { service.perform }.to raise_error(Dclimate::OrbitalLagError)
          expect(alert.reload).to be_satellite_unverified
        end
      end
    end

    context "when alert has no cluster" do
      let(:alert) { create(:ews_alert, :fire, cluster: nil, tree: nil) }

      it "does not raise error on fire_confirmed without cluster" do
        service = described_class.new(alert)
        allow(service).to receive(:query_dclimate_api).and_return(:fire_confirmed)
        expect { service.perform }.not_to raise_error
      end
    end

    context "when query_dclimate_api returns an unknown outcome" do
      let(:alert) { create(:ews_alert, :fire, cluster: cluster, tree: tree) }
      let(:service) { described_class.new(alert) }

      it "does nothing" do
        allow(service).to receive(:query_dclimate_api).and_return(:unknown_outcome)
        expect { service.perform }.not_to raise_error
      end
    end

    context "when trigger_slashing is called with cluster but no organization" do
      let(:alert) { create(:ews_alert, :fire, cluster: cluster, tree: tree) }
      let(:service) { described_class.new(alert) }

      it "returns early without slashing" do
        allow(cluster).to receive(:organization).and_return(nil)
        allow(service).to receive(:query_dclimate_api).and_return(:clear_sky_no_fire)
        expect { service.perform }.not_to raise_error
      end
    end

    # [INS.1] Не-пожежні типи: страховий перил (посуха) і не-страховий критичний акустичний
    # детект (пилка, [SLASH-1]) — fire-супутник не може їх ні підтвердити, ні
    # спростувати → ескалація у Field Audit (:inconclusive), НІКОЛИ rejected_fraud/slashing. Раніше
    # severe_drought йшов крізь fire-двигун → no-fire → rejected_fraud → trigger_slashing (Potemkin-peril).
    # [ARCH.102] Другим членом циклу був знятий insect-перил; його місце зайняв chainsaw —
    # живий не-fire тип цього ж маршруту (severity кожного = як у його диспетчера).
    context "when alert is non-fire (fire-satellite cannot adjudicate)" do
      { severe_drought: :medium, chainsaw_detected: :critical }.each do |peril, severity|
        context "when the alert_type is #{peril}" do
          let(:alert) { create(:ews_alert, cluster: cluster, tree: tree, alert_type: peril, severity: severity) }
          let(:service) { described_class.new(alert) }

          it "escalates to satellite_status :inconclusive (Field Audit, Cat-C)" do
            service.perform
            expect(alert.reload).to be_satellite_inconclusive
          end

          it "never marks rejected_fraud and never queries the FIRMS fire-API" do
            allow(service).to receive(:query_dclimate_api)
            service.perform
            expect(service).not_to have_received(:query_dclimate_api)
            expect(alert.reload).not_to be_satellite_rejected_fraud
          end

          it "does not trigger slashing or payout" do
            create(:naas_contract, cluster: cluster, organization: organization, status: :active)
            create(:parametric_insurance, :triggered, cluster: cluster, organization: organization)
            service.perform
            expect(BurnCarbonTokensWorker).not_to have_received(:perform_async)
            expect(InsurancePayoutWorker).not_to have_received(:perform_async)
          end

          it "records a Field-Audit resolution key" do
            service.perform
            expect(alert.reload.resolution_log.last["key"]).to eq("non_fire_peril")
            expect(alert.reload.resolution_texts.join).to include("Field Audit")
          end
        end
      end
    end
  end

  # ---------------------------------------------------------------
  # 🛰️ HTTP Integration Tests — query_dclimate_api via Web3::HttpClient
  # ---------------------------------------------------------------
  describe "#query_dclimate_api (HTTP integration)" do
    let(:alert) { create(:ews_alert, :fire, cluster: cluster, tree: tree) }
    let(:service) { described_class.new(alert) }
    let(:api_key) { "test-dclimate-api-key-123" }

    before do
      # [DOC-T.31] default and_call_original: ActiveStorage lazy-init (storage.yml)
      # дигає credentials(:aws, …) при першій blob-валідації під цим before — без
      # default вузький .with(:dclimate) stub кидає "unexpected arguments".
      allow(Rails.application.credentials).to receive(:dig).and_call_original
      allow(Rails.application.credentials).to receive(:dig).with(:dclimate, :api_key).and_return(api_key)
    end

    context "when FIRMS data shows active fire (high FRP + high confidence)" do
      let(:firms_response) do
        Web3::HttpClient::Response.new(JSON.generate({
          "data" => [
            { "frp" => 25.5, "confidence" => 85, "brightness" => 340.2, "latitude" => 49.43, "longitude" => 32.06 }
          ],
          "metadata" => { "satellite" => "VIIRS_SNPP", "cloud_cover" => 10.0 }
        }))
      end

      before do
        allow(Web3::HttpClient).to receive(:get).and_return(firms_response)
      end

      it "returns :fire_confirmed" do
        result = service.send(:query_dclimate_api)
        expect(result).to eq(:fire_confirmed)
      end

      it "sends request with correct coordinates and date" do
        service.send(:query_dclimate_api)
        expect(Web3::HttpClient).to have_received(:get).with(
          a_string_matching(/latitude=#{tree.latitude}.*longitude=#{tree.longitude}/),
          hash_including(service_name: "dClimate")
        )
      end

      it "applies strict timeouts for Sidekiq workers" do
        service.send(:query_dclimate_api)
        expect(Web3::HttpClient).to have_received(:get).with(
          anything,
          hash_including(open_timeout: 10, read_timeout: 15)
        )
      end

      it "includes Authorization header with API key" do
        service.send(:query_dclimate_api)
        expect(Web3::HttpClient).to have_received(:get).with(
          anything,
          hash_including(headers: hash_including("Authorization" => "Bearer #{api_key}"))
        )
      end
    end

    context "when FIRMS data shows no fire (low FRP)" do
      let(:firms_response) do
        Web3::HttpClient::Response.new(JSON.generate({
          "data" => [
            { "frp" => 2.1, "confidence" => 30, "brightness" => 295.0 }
          ],
          "metadata" => { "satellite" => "VIIRS_SNPP", "cloud_cover" => 5.0 }
        }))
      end

      before do
        allow(Web3::HttpClient).to receive(:get).and_return(firms_response)
      end

      it "returns :clear_sky_no_fire" do
        result = service.send(:query_dclimate_api)
        expect(result).to eq(:clear_sky_no_fire)
      end
    end

    context "when FIRMS data has high FRP but low confidence" do
      let(:firms_response) do
        Web3::HttpClient::Response.new(JSON.generate({
          "data" => [
            { "frp" => 15.0, "confidence" => 20 }
          ],
          "metadata" => { "cloud_cover" => 5.0 }
        }))
      end

      before do
        allow(Web3::HttpClient).to receive(:get).and_return(firms_response)
      end

      it "returns :clear_sky_no_fire (low confidence rejects detection)" do
        result = service.send(:query_dclimate_api)
        expect(result).to eq(:clear_sky_no_fire)
      end
    end

    context "when cloud cover exceeds threshold" do
      let(:firms_response) do
        Web3::HttpClient::Response.new(JSON.generate({
          "data" => [
            { "frp" => 50.0, "confidence" => 95 }
          ],
          "metadata" => { "cloud_cover" => 85.0 }
        }))
      end

      before do
        allow(Web3::HttpClient).to receive(:get).and_return(firms_response)
      end

      it "returns :obscured_by_clouds" do
        result = service.send(:query_dclimate_api)
        expect(result).to eq(:obscured_by_clouds)
      end
    end

    context "when API returns empty data (no satellite pass)" do
      let(:firms_response) do
        Web3::HttpClient::Response.new(JSON.generate({
          "data" => [],
          "metadata" => {}
        }))
      end

      before do
        allow(Web3::HttpClient).to receive(:get).and_return(firms_response)
      end

      it "returns :obscured_by_clouds" do
        result = service.send(:query_dclimate_api)
        expect(result).to eq(:obscured_by_clouds)
      end
    end

    context "when API returns GeoJSON format" do
      let(:firms_response) do
        Web3::HttpClient::Response.new(JSON.generate({
          "type" => "FeatureCollection",
          "features" => [
            {
              "type" => "Feature",
              "geometry" => { "type" => "Point", "coordinates" => [ 32.06, 49.43 ] },
              "properties" => { "frp" => 30.0, "confidence" => "high" }
            }
          ],
          "metadata" => { "satellite" => "MODIS_AQUA" }
        }))
      end

      before do
        allow(Web3::HttpClient).to receive(:get).and_return(firms_response)
      end

      it "parses GeoJSON features and returns :fire_confirmed" do
        result = service.send(:query_dclimate_api)
        expect(result).to eq(:fire_confirmed)
      end
    end

    context "when VIIRS returns string confidence values" do
      let(:firms_response) do
        Web3::HttpClient::Response.new(JSON.generate({
          "data" => [
            { "frp" => 15.0, "confidence" => "nominal" }
          ],
          "metadata" => { "cloud_cover" => 10.0 }
        }))
      end

      before do
        allow(Web3::HttpClient).to receive(:get).and_return(firms_response)
      end

      it "parses 'nominal' as 50% and returns :fire_confirmed" do
        result = service.send(:query_dclimate_api)
        expect(result).to eq(:fire_confirmed)
      end
    end

    context "when Web3::HttpClient raises RequestError (network failure)" do
      before do
        allow(Web3::HttpClient).to receive(:get)
          .and_raise(Web3::HttpClient::RequestError, "dClimate Timeout: read timeout")
      end

      it "returns :obscured_by_clouds" do
        result = service.send(:query_dclimate_api)
        expect(result).to eq(:obscured_by_clouds)
      end

      it "logs the error" do
        allow(Rails.logger).to receive(:warn)
        service.send(:query_dclimate_api)
        expect(Rails.logger).to have_received(:warn).with(/dClimate API unavailable/)
      end
    end

    context "when API key is not configured" do
      before do
        allow(Rails.application.credentials).to receive(:dig).with(:dclimate, :api_key).and_return(nil)
        allow(Web3::HttpClient).to receive(:get).and_return(
          Web3::HttpClient::Response.new(JSON.generate({ "data" => [], "metadata" => {} }))
        )
      end

      it "sends request without Authorization header" do
        service.send(:query_dclimate_api)
        expect(Web3::HttpClient).to have_received(:get).with(
          anything,
          hash_including(headers: { "Accept" => "application/json" })
        )
      end
    end
  end

  describe "#generate_dclimate_ref" do
    let(:alert) { create(:ews_alert, :fire, cluster: cluster, tree: tree) }
    let(:service) { described_class.new(alert) }

    it "includes satellite name from metadata" do
      service.instance_variable_set(:@satellite_metadata, { "satellite" => "VIIRS_SNPP" })
      ref = service.send(:generate_dclimate_ref)
      expect(ref).to match(/\Adclimate:firms:VIIRS_SNPP:\d{8}T\d{6}Z:[a-f0-9]{16}\z/)
    end

    it "uses UNKNOWN when no satellite metadata" do
      ref = service.send(:generate_dclimate_ref)
      expect(ref).to match(/\Adclimate:firms:UNKNOWN:\d{8}T\d{6}Z:[a-f0-9]{16}\z/)
    end

    it "uses UNKNOWN when satellite_metadata is nil (safe-nav fallback)" do
      service.instance_variable_set(:@satellite_metadata, nil)
      ref = service.send(:generate_dclimate_ref)
      expect(ref).to match(/\Adclimate:firms:UNKNOWN:\d{8}T\d{6}Z:[a-f0-9]{16}\z/)
    end
  end

  describe "#parse_confidence" do
    let(:alert) { create(:ews_alert, :fire, cluster: cluster, tree: tree) }
    let(:service) { described_class.new(alert) }

    it "parses 'low' confidence string to 20" do
      result = service.send(:parse_confidence, "low")
      expect(result).to eq(20)
    end

    it "returns 0 for unexpected non-nil string values with warning" do
      allow(Rails.logger).to receive(:warn).with(/Unexpected FIRMS confidence/)
      result = service.send(:parse_confidence, "unknown_value")
      expect(Rails.logger).to have_received(:warn).with(/Unexpected FIRMS confidence/)
      expect(result).to eq(0)
    end

    it "returns 0 for nil without warning" do
      allow(Rails.logger).to receive(:warn)
      result = service.send(:parse_confidence, nil)
      expect(Rails.logger).not_to have_received(:warn)
      expect(result).to eq(0)
    end
  end

  describe "#trigger_slashing" do
    let(:alert) { create(:ews_alert, :fire, cluster: cluster, tree: tree) }
    let(:service) { described_class.new(alert) }

    context "when cluster has active NaaS contracts" do
      it "enqueues BurnCarbonTokensWorker for each non-breached contract" do
        contract = create(:naas_contract, cluster: cluster, organization: organization, status: :active)

        service.send(:trigger_slashing)

        expect(BurnCarbonTokensWorker).to have_received(:perform_async).with(organization.id, contract.id, alert.tree_id)
      end
    end

    context "when alert has no cluster" do
      it "returns early without error" do
        alert.update_column(:cluster_id, nil)

        expect { service.send(:trigger_slashing) }.not_to raise_error
        expect(BurnCarbonTokensWorker).not_to have_received(:perform_async)
      end
    end
  end

  describe "#extract_entries" do
    let(:alert) { create(:ews_alert, :fire, cluster: cluster, tree: tree) }
    let(:service) { described_class.new(alert) }

    # Covers the fallback when the API payload has neither a "data" array nor a
    # GeoJSON "features" array — interpret_fire_data then treats it as no-pass.
    it "returns [] when neither data nor features is an array" do
      expect(service.send(:extract_entries, { "foo" => "bar" })).to eq([])
    end
  end
end
