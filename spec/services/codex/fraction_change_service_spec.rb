# frozen_string_literal: true

require "rails_helper"

RSpec.describe Codex::FractionChangeService, type: :service do
  let(:org)  { create(:organization) }
  let(:user) { create(:user, organization: org) }
  let(:realm) { create(:codex_realm) }
  let(:node)  { create(:codex_node, realm: realm, lifecycle_status: :thriving, archetype_key: "nlos_routing") }
  let(:other_node) { create(:codex_node, realm: realm, lifecycle_status: :thriving, archetype_key: "mesh_sharding") }

  before { Sidekiq::Worker.clear_all }

  describe "happy paths" do
    it "creates a fraction on first call, denormalises archetype_key, enqueues audit" do
      result = described_class.call(user: user, node: node)

      expect(result.success?).to be(true)
      fraction = result.fraction
      expect(fraction).to be_persisted
      expect(fraction.user_id).to eq(user.id)
      expect(fraction.codex_node_id).to eq(node.id)
      expect(fraction.archetype_key).to eq("nlos_routing")
      expect(fraction.house_color_token).to eq(realm.accent_token)
      expect(fraction.chosen_at).to eq(fraction.last_changed_at)
      expect(Codex::FractionAuditWorker.jobs.size).to eq(1)
    end

    it "updates existing fraction once cooldown elapses, keeps chosen_at, refreshes last_changed_at" do
      now = Time.current
      original = travel_to(now - 8.days) { described_class.call(user: user, node: node).fraction }

      result = described_class.call(user: user, node: other_node)
      expect(result.success?).to be(true)
      reloaded = result.fraction.reload
      expect(reloaded.codex_node_id).to eq(other_node.id)
      expect(reloaded.archetype_key).to eq("mesh_sharding")
      expect(reloaded.chosen_at).to eq(original.chosen_at)
      expect(reloaded.last_changed_at).to be > original.last_changed_at
      expect(result.previous_node_id).to eq(node.id)
    end
  end

  describe "cooldown enforcement" do
    it "blocks a re-pick within the 7-day window with a structured failure" do
      described_class.call(user: user, node: node)
      result = described_class.call(user: user, node: other_node)

      expect(result.success?).to be(false)
      expect(result.errors).to include("cooldown_active")
      expect(result.cooldown_until).to be_within(1.second).of(result.fraction.cooldown_until)
      expect(result.fraction.codex_node_id).to eq(node.id)
    end
  end

  describe "validation rejections" do
    it "rejects extinct nodes without enqueueing audit" do
      dead = create(:codex_node, realm: realm, lifecycle_status: :extinct)
      result = described_class.call(user: user, node: dead)

      expect(result.success?).to be(false)
      expect(result.errors).to include("node is not pickable")
      expect(Codex::FractionAuditWorker.jobs).to be_empty
    end

    it "rejects unsaved user/node" do
      r1 = described_class.call(user: User.new, node: node)
      r2 = described_class.call(user: user, node: Codex::Node.new)
      expect(r1.success?).to be(false)
      expect(r2.success?).to be(false)
    end
  end

  describe "Phase 6 cross-domain Discovery probe" do
    let(:user) { create(:user) }
    let(:node) { create(:codex_node, lifecycle_status: :thriving) }

    it "enqueues a fraction_choice probe on initial pick" do
      expect(Codex::DiscoveryProbeWorker).to receive(:perform_async).with(
        user.id, "fraction_choice",
        hash_including("codex_node_id" => node.id, "previous_node_id" => nil,
                       "trigger_ref_type" => "Codex::Fraction")
      )
      described_class.call(user: user, node: node)
    end

    it "carries previous_node_id on re-pick" do
      first = create(:codex_node, lifecycle_status: :thriving)
      described_class.call(user: user, node: first, now: 8.days.ago)
      expect(Codex::DiscoveryProbeWorker).to receive(:perform_async).with(
        user.id, "fraction_choice",
        hash_including("codex_node_id" => node.id, "previous_node_id" => first.id)
      )
      described_class.call(user: user, node: node)
    end

    it "swallows probe enqueue errors (fraction change is the contract)" do
      allow(Codex::DiscoveryProbeWorker).to receive(:perform_async).and_raise(Redis::CannotConnectError)
      result = described_class.call(user: user, node: node)
      expect(result.success?).to be true
    end

    it "skips the probe when DiscoveryProbeWorker is undefined (forward-compat guard)" do
      hide_const("Codex::DiscoveryProbeWorker")
      result = described_class.call(user: user, node: node)
      expect(result.success?).to be(true)
    end
  end

  describe "guard rails" do
    it "returns invalid result when user is nil" do
      result = described_class.call(user: nil, node: node)
      expect(result.success?).to be(false)
      expect(result.errors).to include("user is required")
    end

    it "returns invalid result when node is nil" do
      result = described_class.call(user: user, node: nil)
      expect(result.success?).to be(false)
      expect(result.errors).to include("node is required")
    end
  end

  describe "post-lock cooldown race" do
    it "re-checks cooldown inside the transaction and aborts when another writer just landed" do
      now = Time.current
      Codex::Fraction.create!(
        user: user, codex_node_id: other_node.id, archetype_key: "mesh_sharding",
        house_color_token: realm.accent_token, last_changed_at: now - 6.hours, chosen_at: now - 6.hours
      )

      call_count = 0
      allow_any_instance_of(Codex::Fraction).to receive(:cooldown_active?) do |_inst, _t|
        call_count += 1
        call_count >= 2 # first check (outside tx) → false, post-lock check → true
      end

      result = described_class.new(user: user, node: node, now: now).call
      expect(result.success?).to be(false)
      expect(result.errors).to include("cooldown_active")
    end
  end

  describe "save! failure (ActiveRecord::RecordInvalid)" do
    it "returns a failure Result with model error messages" do
      allow_any_instance_of(Codex::Fraction).to receive(:save!).and_wrap_original do |_m, *|
        record = Codex::Fraction.new
        record.errors.add(:base, "simulated validation failure")
        raise ActiveRecord::RecordInvalid.new(record)
      end

      result = described_class.call(user: user, node: node)
      expect(result.success?).to be(false)
      expect(result.errors).to include("simulated validation failure")
    end
  end

  describe "enqueue_audit failure is swallowed" do
    it "still returns success when the audit worker enqueue raises" do
      allow(Codex::FractionAuditWorker).to receive(:perform_async).and_raise(StandardError, "redis down")

      result = described_class.call(user: user, node: node)
      expect(result.success?).to be(true)
      expect(result.fraction).to be_persisted
    end
  end
end
