# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe PuroEarthPassportWorker, type: :worker do
  let(:fake_tx_hash) { "0x#{"fa" * 32}" }
  let(:fake_corc_ref) { "CORC-2026-A1B2C3D4" }

  before do
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
    allow(Turbo::StreamsChannel).to receive(:broadcast_prepend_to)
    allow(Turbo::StreamsChannel).to receive(:broadcast_remove_to)

    # Stub PuroEarth::PassportService (Phase 1: on-chain anchoring)
    allow_any_instance_of(PuroEarth::PassportService).to receive(:anchor!).and_return(fake_tx_hash)
    allow(PuroEarthConfirmationWorker).to receive(:perform_in)

    # Stub PuroEarth::RegistryApiService (Phase 3: REST API submission)
    allow_any_instance_of(PuroEarth::RegistryApiService).to receive(:submit!).and_return(fake_corc_ref)
  end

  describe "#perform" do
    context "when record is a biomass_extraction on a Tree" do
      it "generates a biomass passport tx_hash and stamps :sent alongside it" do
        tree = create(:tree, status: :deceased)
        record = create(:maintenance_record, :biomass_extraction, :with_evidence, :attested, maintainable: tree)

        described_class.new.perform(record.id)

        record.reload
        expect(record.biomass_passport_tx_hash).to be_present
        expect(record.biomass_passport_tx_hash).to start_with("0x")
        expect(record.biomass_passport_tx_hash.length).to eq(66) # "0x" + 64 hex chars
        expect(record).to be_biomass_passport_sent
      end

      it "delegates to PuroEarth::PassportService for on-chain anchoring" do
        tree = create(:tree, status: :deceased)
        record = create(:maintenance_record, :biomass_extraction, :with_evidence, :attested, maintainable: tree)

        expect_any_instance_of(PuroEarth::PassportService).to receive(:anchor!)

        described_class.new.perform(record.id)
      end

      # [PERF.1(д)] Власний поллер (не BlockchainConfirmationWorker: той шукає хеш
      # у blockchain_transactions, куди паспортний хеш не потрапляє ніколи).
      it "schedules PuroEarthConfirmationWorker for receipt tracking" do
        tree = create(:tree, status: :deceased)
        record = create(:maintenance_record, :biomass_extraction, :with_evidence, :attested, maintainable: tree)

        described_class.new.perform(record.id)

        expect(PuroEarthConfirmationWorker).to have_received(:perform_in).with(30.seconds, record.id)
      end

      # [ARCH.53/PuroEarth] Idempotency + crash-recovery on Sidekiq retry.
      it "does NOT re-anchor when a passport tx_hash already exists (double-anchor guard)" do
        tree = create(:tree, status: :deceased)
        record = create(:maintenance_record, :biomass_extraction, :with_evidence, :attested, maintainable: tree,
                                                                   biomass_passport_tx_hash: fake_tx_hash,
                                                                   biomass_passport_status: :sent)

        expect_any_instance_of(PuroEarth::PassportService).not_to receive(:anchor!)

        described_class.new.perform(record.id)
      end

      it "re-schedules confirmation on retry even when anchoring is skipped (B5 gap recovery)" do
        tree = create(:tree, status: :deceased)
        record = create(:maintenance_record, :biomass_extraction, :with_evidence, :attested, maintainable: tree,
                                                                   biomass_passport_tx_hash: fake_tx_hash,
                                                                   biomass_passport_status: :sent)

        # Anchoring is skipped (tx_hash present) — fails on pre-fix code where anchor! always ran.
        expect_any_instance_of(PuroEarth::PassportService).not_to receive(:anchor!)

        described_class.new.perform(record.id)

        expect(PuroEarthConfirmationWorker).to have_received(:perform_in).with(30.seconds, record.id)
      end

      # 🔴 Ядро третьої форми: on_chain_proof не віддається в зовнішній реєстр,
      # доки receipt не доведено — саме ця перевірка була структурно неможлива,
      # коли конфірмейшн-нога вела в чужу таблицю.
      it "does NOT submit to the CORC API while the anchor is unconfirmed (:sent)" do
        tree = create(:tree, status: :deceased)
        record = create(:maintenance_record, :biomass_extraction, :with_evidence, :attested, maintainable: tree,
                                                                   biomass_passport_tx_hash: fake_tx_hash,
                                                                   biomass_passport_status: :sent)

        expect_any_instance_of(PuroEarth::RegistryApiService).not_to receive(:submit!)

        described_class.new.perform(record.id)

        expect(record.reload.puro_earth_corc_ref).to be_nil
      end

      it "submits to the CORC API once the anchor is :confirmed and stores corc_ref" do
        tree = create(:tree, status: :deceased)
        record = create(:maintenance_record, :biomass_extraction, :with_evidence, :attested, maintainable: tree,
                                                                   biomass_passport_tx_hash: fake_tx_hash,
                                                                   biomass_passport_status: :confirmed)

        described_class.new.perform(record.id)

        expect(record.reload.puro_earth_corc_ref).to eq(fake_corc_ref)
      end

      it "does NOT re-submit to the CORC API when corc_ref already exists (double-CORC guard)" do
        tree = create(:tree, status: :deceased)
        record = create(:maintenance_record, :biomass_extraction, :with_evidence, :attested, maintainable: tree,
                                                                   biomass_passport_tx_hash: fake_tx_hash,
                                                                   biomass_passport_status: :confirmed,
                                                                   puro_earth_corc_ref: fake_corc_ref)

        expect_any_instance_of(PuroEarth::RegistryApiService).not_to receive(:submit!)

        described_class.new.perform(record.id)
      end

      it "does not run any phase for a terminally :failed anchor" do
        tree = create(:tree, status: :deceased)
        record = create(:maintenance_record, :biomass_extraction, :with_evidence, :attested, maintainable: tree,
                                                                   biomass_passport_tx_hash: fake_tx_hash,
                                                                   biomass_passport_status: :failed)

        expect_any_instance_of(PuroEarth::PassportService).not_to receive(:anchor!)
        expect_any_instance_of(PuroEarth::RegistryApiService).not_to receive(:submit!)

        described_class.new.perform(record.id)

        expect(PuroEarthConfirmationWorker).not_to have_received(:perform_in)
      end

      it "returns the D-MRV passport payload with correct fields" do
        tree = create(:tree, status: :deceased, latitude: 49.4285, longitude: 32.0620)
        record = create(:maintenance_record, :biomass_extraction, :with_evidence, :attested, :with_gps, maintainable: tree)

        payload = described_class.new.perform(record.id)

        expect(payload[:tree_did]).to eq(tree.did)
        expect(payload[:biomass_yield_kg]).to eq(record.biomass_yield_kg.to_f)
        expect(payload[:extraction_date]).to eq(record.performed_at.iso8601)
        expect(payload[:gps_coordinates][:latitude]).to be_a(Float)
        expect(payload[:gps_coordinates][:longitude]).to be_a(Float)
        expect(payload[:lifetime_telemetry_hash]).to be_present
      end

      it "logs the pass outcome with the anchor status" do
        tree = create(:tree, status: :deceased)
        record = create(:maintenance_record, :biomass_extraction, :with_evidence, :attested, maintainable: tree)

        allow(Rails.logger).to receive(:info).with(a_string_matching(/Biomass Passport pass complete.*sent/))

        described_class.new.perform(record.id)

        expect(Rails.logger).to have_received(:info).with(a_string_matching(/Biomass Passport pass complete.*sent/))
      end

      it "continues successfully when REST API submission fails" do
        tree = create(:tree, status: :deceased)
        record = create(:maintenance_record, :biomass_extraction, :with_evidence, :attested, maintainable: tree,
                                                                   biomass_passport_tx_hash: fake_tx_hash,
                                                                   biomass_passport_status: :confirmed)

        allow_any_instance_of(PuroEarth::RegistryApiService).to receive(:submit!)
          .and_raise(PuroEarth::RegistryApiService::SubmissionError, "API timeout")

        expect { described_class.new.perform(record.id) }.not_to raise_error

        record.reload
        expect(record.biomass_passport_tx_hash).to eq(fake_tx_hash)
        expect(record.puro_earth_corc_ref).to be_nil
      end
    end

    context "when maintainable is not a Tree" do
      it "skips processing and logs a warning" do
        gateway = create(:gateway)
        record = create(:maintenance_record, maintainable: gateway, action_type: :inspection)

        allow(Rails.logger).to receive(:warn).with(a_string_matching(/not a Tree/))

        described_class.new.perform(record.id)

        expect(Rails.logger).to have_received(:warn).with(a_string_matching(/not a Tree/))
        record.reload
        expect(record.biomass_passport_tx_hash).to be_nil
      end
    end

    it "raises RecordNotFound for missing record" do
      expect { described_class.new.perform(-1) }.to raise_error(ActiveRecord::RecordNotFound)
    end

    context "when record has nil coordinates" do
      it "falls back to tree coordinates" do
        tree = create(:tree, status: :deceased, latitude: 49.4285, longitude: 32.0620)
        record = create(:maintenance_record, :biomass_extraction, :with_evidence, :attested, maintainable: tree)
        record.update_columns(latitude: nil, longitude: nil)

        result = described_class.new.perform(record.id)
        expect(result[:gps_coordinates][:latitude]).to eq(tree.latitude.to_f)
        expect(result[:gps_coordinates][:longitude]).to eq(tree.longitude.to_f)
      end
    end

    context "when both record and tree coordinates are nil" do
      it "yields nil gps coordinates (tree fallback also absent)" do
        tree = create(:tree, status: :deceased)
        tree.update_columns(latitude: nil, longitude: nil)
        record = create(:maintenance_record, :biomass_extraction, :with_evidence, :attested, maintainable: tree)
        record.update_columns(latitude: nil, longitude: nil)

        result = described_class.new.perform(record.id)
        expect(result[:gps_coordinates][:latitude]).to be_nil
        expect(result[:gps_coordinates][:longitude]).to be_nil
      end
    end

    context "when anchoring fails" do
      it "re-raises the error for Sidekiq retry" do
        tree = create(:tree, status: :deceased)
        record = create(:maintenance_record, :biomass_extraction, :with_evidence, :attested, maintainable: tree)

        allow_any_instance_of(PuroEarth::PassportService).to receive(:anchor!)
          .and_raise(PuroEarth::PassportService::AnchoringError, "RPC timeout")

        expect {
          described_class.new.perform(record.id)
        }.to raise_error(PuroEarth::PassportService::AnchoringError)
      end
    end

    # [E.20] Ворота незворотної CORC-заявки мають ДВІ умови, і кожна має свій виняток:
    # фотодоказ ⊥ незалежний підпис. Обидві стоять ТУТ, а не на моделі — валідація
    # every-save зламала б Puro-тракт ([ARCH.91]; `update!` обох воркерів).
    context "when the photo evidence has vanished after creation" do
      let(:tree) { create(:tree, status: :deceased) }
      # 🔴 Фікстура відтворює РЕАЛЬНИЙ шлях, а не обходить модель: із 2026-08-24 запис
      # без фото не створюється взагалі (`photo_required_for_biomass_claim`, `on: :create`),
      # тож стан, заради якого існує цей гард, виникає лише через ЗНИКНЕННЯ доказу
      # (purge поза контролерним замком, або запис, старший за валідацію).
      let(:record) do
        rec = create(:maintenance_record, :biomass_extraction, :with_evidence, :attested, maintainable: tree)
        rec.photos.purge
        rec.reload
      end

      it "refuses LOUDLY instead of filing an irreversible CORC claim" do
        expect {
          described_class.new.perform(record.id)
        }.to raise_error(described_class::MissingEvidence, /##{record.id}/)
      end

      # Пін на САМУ незворотну дію, не лише на виняток: гейт, що кидає ПІСЛЯ
      # анкеринга, лишався б зеленим на прикладі вище.
      it "does not anchor and leaves the passport untouched" do
        expect_any_instance_of(PuroEarth::PassportService).not_to receive(:anchor!)

        expect { described_class.new.perform(record.id) }.to raise_error(described_class::MissingEvidence)

        expect(record.reload.biomass_passport_tx_hash).to be_nil
        expect(record.biomass_passport_status).to be_nil
      end

      # Дзеркало «легітимний актор не зачеплений»: без нього «нуль заявок»
      # не відрізнити від «нуль тракту».
      it "anchors again once the evidence is restored" do
        record.photos.attach(io: StringIO.new("evidence"), filename: "e.jpg", content_type: "image/jpeg")

        described_class.new.perform(record.id)

        expect(record.reload.biomass_passport_tx_hash).to be_present
      end
    end

    # [E.20, ⚖️ founder 2026-08-24] Друга умова тих самих воріт: «атестатор ≠ бенефіціар».
    # Стоїть перед ВИХОДОМ у зовнішній реєстр, а не на створенні — атестатор не мусить
    # бути поруч у полі, і вимога на створенні штовхала б до профанації підпису.
    context "when the record carries no independent attestation" do
      let(:tree) { create(:tree, status: :deceased) }
      let(:record) { create(:maintenance_record, :biomass_extraction, :with_evidence, maintainable: tree) }

      it "refuses LOUDLY — a self-reported claim does not reach the external registry" do
        expect {
          described_class.new.perform(record.id)
        }.to raise_error(described_class::MissingAttestation, /##{record.id}/)
      end

      it "does not anchor and leaves the passport untouched" do
        expect_any_instance_of(PuroEarth::PassportService).not_to receive(:anchor!)

        expect { described_class.new.perform(record.id) }.to raise_error(described_class::MissingAttestation)

        expect(record.reload.biomass_passport_tx_hash).to be_nil
      end

      # Дзеркало: тракт живий, щойно другу пару очей отримано. Без нього «нуль
      # заявок» не відрізнити від «нуль тракту».
      it "anchors once a second pair of eyes has vouched" do
        auditor = create(:user, :forester)
        record.attest!(auditor)

        described_class.new.perform(record.id)

        expect(record.reload.biomass_passport_tx_hash).to be_present
      end

      # Порядок воріт має значення: без фото відповідь мусить бути про ФОТО,
      # інакше оператор лагодить не те.
      it "reports the missing photo first when BOTH are absent" do
        record.photos.purge

        expect {
          described_class.new.perform(record.reload.id)
        }.to raise_error(described_class::MissingEvidence)
      end
    end
  end
end
