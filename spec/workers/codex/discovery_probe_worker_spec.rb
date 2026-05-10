# frozen_string_literal: true

require "rails_helper"

RSpec.describe Codex::DiscoveryProbeWorker, type: :worker do
  let(:user) { create(:user) }
  let(:node) { create(:codex_node) }

  before { Rails.cache.clear }

  it "is on queue default with retry: 3" do
    expect(described_class.sidekiq_options["queue"].to_s).to eq("default")
    expect(described_class.sidekiq_options["retry"]).to eq(3)
  end

  it "is a no-op when DiscoveryEngine returns []" do
    allow(::Codex::DiscoveryEngine).to receive(:evaluate).and_return([])
    expect {
      described_class.new.perform(user.id, "match_milestone", {})
    }.not_to change(Codex::Discovery, :count)
  end

  it "creates a Discovery + broadcasts when Engine returns nodes" do
    allow(::Codex::DiscoveryEngine).to receive(:evaluate).and_return([ node ])
    expect(ActionCable.server).to receive(:broadcast).with(
      "codex:discoveries:user:#{user.id}", hash_including(slug: node.slug)
    )
    expect {
      described_class.new.perform(user.id, "match_milestone",
                                  { "trigger_ref_type" => "Codex::Match", "trigger_ref_id" => 42 })
    }.to change(Codex::Discovery, :count).by(1)
    d = Codex::Discovery.last
    expect(d.user_id).to eq(user.id)
    expect(d.codex_node_id).to eq(node.id)
    expect(d.trigger_ref_type).to eq("Codex::Match")
    expect(d.trigger_ref_id).to eq(42)
    expect(d.triggered_by_match_milestone?).to be(true)
  end

  it "is idempotent on the unique-violation race (no double-broadcast)" do
    create(:codex_discovery, user: user, node: node)
    allow(::Codex::DiscoveryEngine).to receive(:evaluate).and_return([ node ])
    expect(ActionCable.server).not_to receive(:broadcast)
    expect {
      described_class.new.perform(user.id, "match_milestone", {})
    }.not_to change(Codex::Discovery, :count)
  end

  it "swallows unknown user_id" do
    expect(::Codex::DiscoveryEngine).not_to receive(:evaluate)
    expect {
      described_class.new.perform(0, "match_milestone", {})
    }.not_to raise_error
  end

  it "swallows RecordNotUnique from a concurrent insert race (idempotency guard)" do
    allow(::Codex::DiscoveryEngine).to receive(:evaluate).and_return([ node ])
    allow(::Codex::Discovery).to receive(:create_with).and_call_original
    allow_any_instance_of(ActiveRecord::Relation).to receive(:find_or_create_by)
      .and_raise(ActiveRecord::RecordNotUnique)
    expect(ActionCable.server).not_to receive(:broadcast)
    expect { described_class.new.perform(user.id, "match_milestone", {}) }.not_to raise_error
  end

  it "swallows ArgumentError from an invalid trigger_type string" do
    allow(::Codex::DiscoveryEngine).to receive(:evaluate).and_return([ node ])
    # Simulate ArgumentError from enum validation when an invalid trigger_type
    # value reaches the DB layer (e.g. ActiveRecord rejects unknown enum values).
    allow_any_instance_of(ActiveRecord::Relation).to receive(:find_or_create_by)
      .and_raise(ArgumentError, "bad enum value")
    expect(ActionCable.server).not_to receive(:broadcast)
    expect { described_class.new.perform(user.id, "match_milestone", {}) }.not_to raise_error
  end

  it "swallows a broadcast StandardError so the DB record is not rolled back" do
    allow(::Codex::DiscoveryEngine).to receive(:evaluate).and_return([ node ])
    allow(ActionCable.server).to receive(:broadcast).and_raise(StandardError, "cable error")
    expect {
      described_class.new.perform(user.id, "match_milestone", {})
    }.not_to raise_error
    # Discovery record was still created
    expect(Codex::Discovery.where(user_id: user.id, codex_node_id: node.id)).to exist
  end
end
