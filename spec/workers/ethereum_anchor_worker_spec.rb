# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe EthereumAnchorWorker, type: :worker do
  describe "sidekiq_options" do
    it "uses the web3_low queue" do
      expect(described_class.sidekiq_options["queue"]).to eq("web3_low")
    end

    it "has retry set to 5" do
      expect(described_class.sidekiq_options["retry"]).to eq(5)
    end

    it "has unique_for set to 7 days to prevent overlapping anchoring cycles" do
      expect(described_class.sidekiq_options["unique_for"]).to eq(7.days)
    end
  end

  describe "module inclusion" do
    it "includes ApplicationWeb3Worker" do
      expect(described_class.ancestors).to include(ApplicationWeb3Worker)
    end
  end

  describe "#perform" do
    let(:mock_service) { instance_double(Ethereum::StateAnchorService) }

    before do
      allow(Ethereum::StateAnchorService).to receive(:new).and_return(mock_service)
    end

    it "calls Ethereum::StateAnchorService#anchor_to_l1!" do
      allow(mock_service).to receive(:anchor_to_l1!).and_return("0x" + "ab" * 32)

      described_class.new.perform

      expect(mock_service).to have_received(:anchor_to_l1!)
    end

    it "returns the tx_hash from the service" do
      expected_hash = "0x" + "ab" * 32
      allow(mock_service).to receive(:anchor_to_l1!).and_return(expected_hash)

      # The perform method delegates, but through with_web3_error_handling
      expect { described_class.new.perform }.not_to raise_error
    end

    it "re-raises errors after logging" do
      allow(mock_service).to receive(:anchor_to_l1!).and_raise(RuntimeError, "Ethereum L1 Timeout: execution expired")

      allow(Rails.logger).to receive(:error).with(/L1 anchoring failed/)

      expect {
        described_class.new.perform
      }.to raise_error(RuntimeError, /Ethereum L1 Timeout/)

      expect(Rails.logger).to have_received(:error).with(/L1 anchoring failed/)
    end

    it "re-raises RPC connection errors for Sidekiq retry" do
      allow(mock_service).to receive(:anchor_to_l1!).and_raise(Errno::ECONNREFUSED, "Connection refused")
      allow(SilkenNet::Metrics::RPC_ERRORS_TOTAL).to receive(:increment)

      expect {
        described_class.new.perform
      }.to raise_error(Errno::ECONNREFUSED)
    end

    it "re-raises HTTPX timeout errors for Sidekiq retry" do
      allow(mock_service).to receive(:anchor_to_l1!).and_raise(HTTPX::TimeoutError.new(nil, "timeout"))
      allow(SilkenNet::Metrics::RPC_ERRORS_TOTAL).to receive(:increment)

      expect {
        described_class.new.perform
      }.to raise_error(HTTPX::TimeoutError)
    end

    it "logs with the Ethereum prefix on any error" do
      allow(mock_service).to receive(:anchor_to_l1!).and_raise(StandardError, "unexpected error")

      allow(Rails.logger).to receive(:error).with(/\[EthereumAnchor\].*L1 anchoring failed/)

      expect {
        described_class.new.perform
      }.to raise_error(StandardError, "unexpected error")

      expect(Rails.logger).to have_received(:error).with(/\[EthereumAnchor\].*L1 anchoring failed/)
    end
  end

  describe "#detect_missed_anchor_weeks! (S6.6)" do
    let(:mock_service) { instance_double(Ethereum::StateAnchorService) }

    before do
      allow(Ethereum::StateAnchorService).to receive(:new).and_return(mock_service)
      allow(mock_service).to receive(:anchor_to_l1!).and_return("0x" + "ab" * 32)
    end

    it "does not warn when no previous anchors exist (first ever anchor)" do
      allow(Rails.logger).to receive(:warn)

      described_class.new.perform

      expect(Rails.logger).not_to have_received(:warn).with(/Missed anchor week/)
    end

    it "does not warn when last CONFIRMED anchor is within 8 days" do
      travel_to(6.days.ago) do
        EthereumAnchor.create!(
          state_root: "a" * 64,
          total_growth_points: 100.0,
          chain_hash: "recent_hash",
          anchored_at: Time.current,
          status: :confirmed,
          tx_hash: "0x#{"bb" * 32}"
        )
      end

      allow(Rails.logger).to receive(:warn)

      described_class.new.perform

      expect(Rails.logger).not_to have_received(:warn).with(/Missed anchor week/)
    end

    it "[ARCH.66] warns when the last CONFIRMED anchor is old even if a fresh :sent exists" do
      # F3-fix: a stuck :sent must NOT mask a genuinely unconfirmed gap. The narrowed
      # detect_missed counts only :confirmed, so a fresh weekly :sent no longer resets the gap.
      travel_to(10.days.ago) do
        EthereumAnchor.create!(
          state_root: "a" * 64, total_growth_points: 100.0, chain_hash: "old_confirmed",
          anchored_at: Time.current, status: :confirmed, tx_hash: "0x#{"bb" * 32}"
        )
      end
      travel_to(1.day.ago) do
        EthereumAnchor.create!(
          state_root: "b" * 64, total_growth_points: 200.0, chain_hash: "fresh_sent",
          anchored_at: Time.current, status: :sent, tx_hash: "0x#{"cc" * 32}"
        )
      end

      allow(Rails.logger).to receive(:warn).with(/Missed anchor week detected/)
      allow(SilkenNet::Metrics::ANCHOR_MISSED_WEEKS_TOTAL).to receive(:increment)

      described_class.new.perform

      expect(Rails.logger).to have_received(:warn).with(/Missed anchor week detected/)
      expect(SilkenNet::Metrics::ANCHOR_MISSED_WEEKS_TOTAL).to have_received(:increment)
    end

    it "warns and increments metric when last anchor is older than 8 days" do
      travel_to(10.days.ago) do
        EthereumAnchor.create!(
          state_root: "b" * 64,
          total_growth_points: 200.0,
          chain_hash: "old_hash",
          anchored_at: Time.current,
          status: :confirmed,
          tx_hash: "0x#{"cc" * 32}"
        )
      end

      allow(Rails.logger).to receive(:warn).with(/Missed anchor week detected/)
      allow(SilkenNet::Metrics::ANCHOR_MISSED_WEEKS_TOTAL).to receive(:increment)

      described_class.new.perform

      expect(Rails.logger).to have_received(:warn).with(/Missed anchor week detected/)
      expect(SilkenNet::Metrics::ANCHOR_MISSED_WEEKS_TOTAL).to have_received(:increment)
    end

    # 🔴 [INF.26] Лічильник рахує ТИЖНІ, як обіцяє докстрінг, а не спрацювання детектора.
    # Доти `missed_weeks` обчислювався й логувався, а до метрики не доїжджав — тож
    # пʼятитижнева прогалина важила стільки ж, скільки одна, і недолік був НЕЗВОРОТНИЙ:
    # наступного тижня `last_anchor` уже свіжий, детекція мовчить, і ті тижні не долічить
    # ніхто. ⚠️ Сусідні приклади вище пінять ФАКТ інкременту (`have_received(:increment)`),
    # тобто зелені й на голому виклику — розрізняє лише пін на ВЕЛИЧИНУ.
    it "counts missed WEEKS, not detector firings" do
      travel_to(36.days.ago) do
        EthereumAnchor.create!(
          state_root: "d" * 64, total_growth_points: 200.0, chain_hash: "very_old",
          anchored_at: Time.current, status: :confirmed, tx_hash: "0x#{"dd" * 32}"
        )
      end

      allow(Rails.logger).to receive(:warn).with(/Missed anchor week detected/)
      allow(SilkenNet::Metrics::ANCHOR_MISSED_WEEKS_TOTAL).to receive(:increment)

      described_class.new.perform

      # 36 днів ≈ 5 тижнів; поточний (очікуваний) віднімається → 4.
      expect(SilkenNet::Metrics::ANCHOR_MISSED_WEEKS_TOTAL).to have_received(:increment).with(by: 4)
    end

    it "ignores failed anchors when checking for gaps" do
      EthereumAnchor.create!(
        state_root: "c" * 64,
        total_growth_points: 300.0,
        chain_hash: "failed_hash",
        anchored_at: 2.days.ago,
        status: :failed,
        error_message: "some error"
      )

      # No sent/confirmed anchors exist, so this is treated as first-ever
      allow(Rails.logger).to receive(:warn)

      described_class.new.perform

      expect(Rails.logger).not_to have_received(:warn).with(/Missed anchor week/)
    end

    it "does not block anchoring if detection itself fails" do
      allow(EthereumAnchor).to receive(:status_confirmed).and_raise(StandardError, "DB error")

      allow(Rails.logger).to receive(:warn).with(/Missed anchor detection failed/)
      allow(mock_service).to receive(:anchor_to_l1!).and_return("0x" + "dd" * 32)

      described_class.new.perform

      expect(Rails.logger).to have_received(:warn).with(/Missed anchor detection failed/)
      expect(mock_service).to have_received(:anchor_to_l1!)
    end
  end
end
