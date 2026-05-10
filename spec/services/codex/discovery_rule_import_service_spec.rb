# frozen_string_literal: true

require "rails_helper"

RSpec.describe Codex::DiscoveryRuleImportService do
  let(:path)  { Rails.root.join("tmp/discovery_rules.yml") }
  let(:author) { create(:user, :super_admin) }

  before do
    allow(User).to receive(:oracle_executioner).and_return(author)
    create(:codex_node, slug: "yggdrasil")
    create(:codex_node, slug: "protocol-codit")
  end

  after { File.delete(path) if File.exist?(path) }

  it "returns zeros when the YAML is missing" do
    File.delete(path) if File.exist?(path)
    result = described_class.call(path: path)
    expect(result.created).to eq(0)
    expect(result.updated).to eq(0)
  end

  it "creates rules from YAML and is idempotent on re-run" do
    File.write(path, [
      { "name" => "ten-matches-mythos",  "node_slug" => "yggdrasil",
        "condition_type" => "match_count", "threshold_value" => 10,
        "params" => { "realm_slug" => "mythos" }, "active" => true },
      { "name" => "first-match-overall", "node_slug" => "protocol-codit",
        "condition_type" => "match_count", "threshold_value" => 1,
        "active" => true }
    ].to_yaml)

    first = described_class.call(path: path)
    expect(first.created).to eq(2)
    expect(first.updated).to eq(0)
    expect(Codex::DiscoveryRule.count).to eq(2)
    yggdrasil_rule = Codex::DiscoveryRule.find_by(name: "ten-matches-mythos")
    expect(yggdrasil_rule.params).to eq("realm_slug" => "mythos")
    expect(yggdrasil_rule.created_by_user_id).to eq(author.id)

    second = described_class.call(path: path)
    expect(second.created).to eq(0)
    expect(second.updated).to eq(2)
    expect(Codex::DiscoveryRule.count).to eq(2)
  end

  it "skips rows whose node_slug is unknown (logs warn)" do
    File.write(path, [ { "name" => "ghost", "node_slug" => "missing",
                         "condition_type" => "match_count",
                         "threshold_value" => 1 } ].to_yaml)
    expect(Rails.logger).to receive(:warn).with(/node_slug=missing not found/)
    result = described_class.call(path: path)
    expect(result.skipped).to eq(1)
    expect(Codex::DiscoveryRule.count).to eq(0)
  end

  it "uses oracle_executioner when created_by_user_email is unknown" do
    File.write(path, [ { "name" => "auto", "node_slug" => "yggdrasil",
                         "condition_type" => "match_count",
                         "threshold_value" => 1,
                         "created_by_user_email" => "ghost@example.com" } ].to_yaml)
    described_class.call(path: path)
    expect(Codex::DiscoveryRule.find_by(name: "auto").created_by_user_id).to eq(author.id)
  end
end
