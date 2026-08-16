# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe ClusterEntropySweepWorker, type: :worker do
  describe "#perform" do
    # [ARCH.59] Пін тримає ДВІ осі, і кожну доводить СВОЯ мутація — бо саме
    # кількість Redis-звертань і є те, заради чого робота робилась.
    #   `.with(повний набір)` → `find_each { perform_bulk([[id]]) }` (та сама
    #                            кількість RTT, лише під новим іменем) → RED;
    #   `.once`               → повторний прохід із правильним набором → RED
    #                            («expected 1 time, received 2 times»).
    it "enqueues every cluster in a SINGLE bulk round-trip" do
      org = create(:organization)
      clusters = create_list(:cluster, 3, organization: org)
      allow(ClusterEntropyAnalyzerWorker).to receive(:perform_bulk)

      described_class.new.perform

      expect(ClusterEntropyAnalyzerWorker).to have_received(:perform_bulk)
        .with(a_collection_containing_exactly(*clusters.map { |cluster| [ cluster.id ] }))
        .once
    end

    # ⚠️ Негатив мусить стерегти ТОЙ САМИЙ метод, що й позитив: після переходу на
    # bulk пін на `perform_async` став би вакуумним — код більше не кличе його
    # НІКОЛИ, тож приклад був би зелений незалежно від поведінки.
    it "enqueues nothing when there are no clusters" do
      allow(ClusterEntropyAnalyzerWorker).to receive(:perform_bulk)

      described_class.new.perform

      expect(ClusterEntropyAnalyzerWorker).not_to have_received(:perform_bulk)
    end
  end
end
