# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# [ARCH.94 / ARCH.59] Дім семпла stall-глибини після переїзду з мертвого
# Batch-колбека. Дискримінатор точний: мінт піднімає `locked_balance`, тож після
# здорового циклу eligible-множина порожня за побудовою — усе, що в ній лишилось,
# мало змінтувати й не змінтувало.
RSpec.describe MintStallProbeWorker, type: :worker do
  let(:threshold) { TokenomicsEvaluatorWorker.emission_threshold }

  describe "#perform" do
    it "reports depth 0 when every eligible wallet converted its points" do
      tree = create(:tree, status: :active)
      # available = balance − locked = 0 → сконвертовано, більше не eligible
      tree.wallet.update!(balance: threshold, locked_balance: threshold)

      allow(SilkenNet::Metrics::MINT_ELIGIBLE_UNMINTED_DEPTH).to receive(:set).with(0)

      described_class.new.perform

      expect(SilkenNet::Metrics::MINT_ELIGIBLE_UNMINTED_DEPTH).to have_received(:set).with(0)
    end

    it "reports a non-zero depth when an eligible wallet produced no mint" do
      tree = create(:tree, status: :active)
      # Фікстура МУСИТЬ перетинати поріг, інакше клас невидимий (04_06 §B.2 BP #14).
      tree.wallet.update!(balance: threshold * 2, locked_balance: 0)

      allow(SilkenNet::Metrics::MINT_ELIGIBLE_UNMINTED_DEPTH).to receive(:set).with(1)

      described_class.new.perform

      expect(SilkenNet::Metrics::MINT_ELIGIBLE_UNMINTED_DEPTH).to have_received(:set).with(1)
    end

    # Прилад спостережності не сміє впасти й забрати із собою розклад: сусідні
    # cron-джоби цієї ж черги не мають страждати від недоступної БД.
    it "swallows a probe failure instead of raising" do
      allow(TokenomicsEvaluatorWorker).to receive(:eligible_wallets).and_raise(StandardError, "db down")

      expect { described_class.new.perform }.not_to raise_error
    end

    # 🔴 [PERF.1] Нуль — це ВИМІР, а не тиша: мовчазний прохід невідрізненний від
    # приладу, який не біг, і саме на нулі метрика найцінніша.
    it "speaks on a zero reading" do
      allow(Rails.logger).to receive(:info)

      described_class.new.perform

      expect(Rails.logger).to have_received(:info).with(/Глибина застряглої емісії: 0/)
    end
  end
end
