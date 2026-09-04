# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# [ARCH.119] Ре-арм peaq-реєстрації. `PeaqRegistrationWorker` має ОДИН enqueue-сайт
# (провіжн), тож без цього воркера дерево без DID не діставало другої нагоди ніколи.
RSpec.describe PeaqBackfillWorker, type: :worker do
  # Нога оголошено ЖИВА: приклади нижче про ПОВЕДІНКУ дренажу, не про гейт;
  # сам гейт пінить негативний приклад в кінці.
  before do
    allow(Peaq::DidRegistryService).to receive(:configured?).and_return(true)
    allow(PeaqRegistrationWorker).to receive(:perform_async)
    silence_broadcasts!(:tree_map)
  end

  let(:cluster) { create(:cluster) }

  def pending_tree
    create(:tree, cluster: cluster).tap { |t| t.update_column(:peaq_did, nil) }
  end

  def registered_tree
    create(:tree, cluster: cluster).tap { |t| t.update_column(:peaq_did, "did:peaq:0x#{SecureRandom.hex(20)}") }
  end

  it "re-arms every tree still missing a peaq DID" do
    a = pending_tree
    b = pending_tree

    described_class.new.perform

    expect(PeaqRegistrationWorker).to have_received(:perform_async).with(a.id)
    expect(PeaqRegistrationWorker).to have_received(:perform_async).with(b.id)
  end

  it "skips trees that already carry a DID — only the stranded need recovery" do
    done = registered_tree

    described_class.new.perform

    expect(PeaqRegistrationWorker).not_to have_received(:perform_async).with(done.id)
  end

  it "caps the pass at BATCH_LIMIT (backlog drains across nights)" do
    stub_const("#{described_class}::BATCH_LIMIT", 1)
    pending_tree
    pending_tree

    described_class.new.perform

    expect(PeaqRegistrationWorker).to have_received(:perform_async).once
  end

  it "counts re-armed TREES, not passes" do
    allow(SilkenNet::Metrics::PEAQ_BACKFILL_REARMED_TOTAL).to receive(:increment)
    pending_tree
    pending_tree

    described_class.new.perform

    expect(SilkenNet::Metrics::PEAQ_BACKFILL_REARMED_TOTAL).to have_received(:increment).with(by: 2)
  end

  it "stays silent when there is nothing stranded" do
    allow(SilkenNet::Metrics::PEAQ_BACKFILL_REARMED_TOTAL).to receive(:increment)
    registered_tree

    described_class.new.perform

    expect(PeaqRegistrationWorker).not_to have_received(:perform_async)
    expect(SilkenNet::Metrics::PEAQ_BACKFILL_REARMED_TOTAL).not_to have_received(:increment)
  end

  describe "activation gate [ARCH.119]" do
    it "re-arms nothing when the leg is unconfigured, and NAMES the backlog it is holding" do
      allow(Peaq::DidRegistryService).to receive(:configured?).and_return(false)
      allow(Rails.logger).to receive(:warn)
      pending_tree

      described_class.new.perform

      expect(PeaqRegistrationWorker).not_to have_received(:perform_async)
      # Голос обовʼязковий: тихий no-op робить стан невідрізнимим від «нема заборгованості».
      expect(Rails.logger).to have_received(:warn).with(/не сконфігурована.*1 дерев/m)
    end
  end
end
