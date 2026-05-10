# frozen_string_literal: true

require "rails_helper"

RSpec.describe Codex::AttunementBroadcastWorker do
  let(:user) { create(:user) }
  let(:node) { create(:codex_node) }

  it "is wired to the default queue with retry: 3" do
    expect(described_class.sidekiq_options["queue"].to_s).to eq("default")
    expect(described_class.sidekiq_options["retry"]).to eq(3)
  end

  it "broadcasts the post-commit attunement_count to the public node channel" do
    create(:codex_attunement, user: user, node: node)

    payloads = []
    allow(ActionCable.server).to receive(:broadcast) do |_topic, payload|
      payloads << payload
    end

    described_class.new.perform(node.id, user.id)

    expect(payloads.first).to include(
      node_id: node.id,
      attunement_count: node.reload.attunement_count,
      actor_user_id: user.id
    )
  end

  it "broadcasts a per-user envelope with the `attuned` flag" do
    create(:codex_attunement, user: user, node: node)

    captured = []
    allow(ActionCable.server).to receive(:broadcast) do |topic, payload|
      captured << [ topic, payload ]
    end

    described_class.new.perform(node.id, user.id)

    private_topic = "codex_node_#{node.id}_attunements_user_#{user.id}"
    private_msg   = captured.find { |t, _| t == private_topic }
    expect(private_msg).not_to be_nil
    expect(private_msg.last).to include(attuned: true)
  end

  it "reports `attuned: false` when the user has just removed their attunement" do
    captured = []
    allow(ActionCable.server).to receive(:broadcast) do |topic, payload|
      captured << [ topic, payload ]
    end

    # No attunement row exists.
    described_class.new.perform(node.id, user.id)

    private_topic = "codex_node_#{node.id}_attunements_user_#{user.id}"
    expect(captured.find { |t, _| t == private_topic }.last).to include(attuned: false)
  end

  it "is a no-op for an unknown node id" do
    expect(ActionCable.server).not_to receive(:broadcast)
    described_class.new.perform(0, user.id)
  end

  it "re-raises StandardError from ActionCable so Sidekiq can retry" do
    create(:codex_attunement, user: user, node: node)
    allow(ActionCable.server).to receive(:broadcast).and_raise(StandardError, "cable down")
    expect {
      described_class.new.perform(node.id, user.id)
    }.to raise_error(StandardError, "cable down")
  end
end
