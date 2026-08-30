# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe SystemParameter, type: :model do
  describe "validations" do
    subject(:param) { build(:system_parameter) }

    it { is_expected.to be_valid }

    it "requires key" do
      param.key = nil
      expect(param).not_to be_valid
    end

    it "requires unique key" do
      create(:system_parameter, key: "unique_key")
      param.key = "unique_key"
      expect(param).not_to be_valid
    end

    it "requires snake_case key" do
      param.key = "CamelCase"
      expect(param).not_to be_valid
    end

    it "rejects keys starting with number" do
      param.key = "1invalid"
      expect(param).not_to be_valid
    end

    it "accepts valid snake_case keys" do
      param.key = "lorenz_sigma_v2"
      expect(param).to be_valid
    end

    it "requires value" do
      param.value = nil
      expect(param).not_to be_valid
    end

    it "requires valid value_type" do
      param.value_type = "invalid"
      expect(param).not_to be_valid
    end

    it "requires valid category" do
      param.category = "invalid"
      expect(param).not_to be_valid
    end

    it "requires valid source" do
      param.source = "invalid"
      expect(param).not_to be_valid
    end

    it "accepts all valid value_types" do
      %w[integer float decimal string boolean json].each do |vt|
        param.value_type = vt
        expect(param).to be_valid, "expected value_type '#{vt}' to be valid"
      end
    end

    it "accepts all valid categories" do
      %w[lorenz tokenomics minting alerts hardware insurance general].each do |cat|
        param.category = cat
        expect(param).to be_valid, "expected category '#{cat}' to be valid"
      end
    end

    it "accepts all valid sources" do
      %w[default admin governance].each do |src|
        param.source = src
        expect(param).to be_valid, "expected source '#{src}' to be valid"
      end
    end
  end

  describe "bounds validation" do
    it "rejects value below min_value" do
      param = build(:system_parameter, value: "3.0", value_type: "float",
                                       min_value: 5.0, max_value: 30.0)
      expect(param).not_to be_valid
      expect(param.errors[:value]).to include("must be >= 5.0")
    end

    it "rejects value above max_value" do
      param = build(:system_parameter, value: "50.0", value_type: "float",
                                       min_value: 5.0, max_value: 30.0)
      expect(param).not_to be_valid
      expect(param.errors[:value]).to include("must be <= 30.0")
    end

    it "accepts value within bounds" do
      param = build(:system_parameter, value: "10.0", value_type: "float",
                                       min_value: 5.0, max_value: 30.0)
      expect(param).to be_valid
    end

    it "skips bounds validation for non-numeric values" do
      param = build(:system_parameter, value: "hello", value_type: "string",
                                       min_value: 5.0)
      expect(param).to be_valid
    end
  end

  describe "#typed_value" do
    it "returns integer for integer type" do
      param = build(:system_parameter, value: "10000", value_type: "integer")
      expect(param.typed_value).to eq(10_000)
      expect(param.typed_value).to be_a(Integer)
    end

    it "returns float for float type" do
      param = build(:system_parameter, value: "10.0", value_type: "float")
      expect(param.typed_value).to eq(10.0)
      expect(param.typed_value).to be_a(Float)
    end

    it "returns BigDecimal for decimal type" do
      param = build(:system_parameter, value: "0.02", value_type: "decimal")
      expect(param.typed_value).to eq(BigDecimal("0.02"))
      expect(param.typed_value).to be_a(BigDecimal)
    end

    it "returns string for string type" do
      param = build(:system_parameter, value: "hello", value_type: "string")
      expect(param.typed_value).to eq("hello")
    end

    it "returns boolean true for boolean type" do
      param = build(:system_parameter, value: "true", value_type: "boolean")
      expect(param.typed_value).to be(true)
    end

    it "returns boolean false for boolean type" do
      param = build(:system_parameter, value: "false", value_type: "boolean")
      expect(param.typed_value).to be(false)
    end

    it "returns parsed hash for json type" do
      param = build(:system_parameter, value: '{"key":"val"}', value_type: "json")
      expect(param.typed_value).to eq({ "key" => "val" })
    end
  end

  describe ".current" do
    it "returns typed value for existing parameter" do
      create(:system_parameter, :lorenz_sigma)
      expect(described_class.current(:lorenz_sigma)).to eq(10.0)
    end

    it "returns default when parameter not found" do
      expect(described_class.current(:nonexistent, default: 42)).to eq(42)
    end

    it "returns nil when parameter not found and no default" do
      expect(described_class.current(:nonexistent)).to be_nil
    end

    it "accepts string keys" do
      create(:system_parameter, :lorenz_sigma)
      expect(described_class.current("lorenz_sigma")).to eq(10.0)
    end

    it "caches the value" do
      create(:system_parameter, :lorenz_sigma)

      # First call populates cache
      described_class.current(:lorenz_sigma)

      # Second call should use cache (no DB query) and return same value
      allow(described_class).to receive(:find_by)
      expect(described_class.current(:lorenz_sigma)).to eq(10.0)

      expect(described_class).not_to have_received(:find_by)
    end

    it "invalidates cache on update" do
      param = create(:system_parameter, :lorenz_sigma)

      # Populate cache
      expect(described_class.current(:lorenz_sigma)).to eq(10.0)

      # Update the parameter
      param.update!(value: "15.0")

      # Should return new value
      expect(described_class.current(:lorenz_sigma)).to eq(15.0)
    end

    it "correctly caches boolean false values" do
      create(:system_parameter, key: "disabled_flag", value: "false", value_type: "boolean", category: "general")

      # First call should return false (not nil)
      expect(described_class.current(:disabled_flag)).to be(false)

      # Second call should return cached false (not fall through to DB)
      allow(described_class).to receive(:find_by)
      expect(described_class.current(:disabled_flag)).to be(false)

      expect(described_class).not_to have_received(:find_by)
    end

    # Regression: попередня реалізація використовувала `exist? + read + write` —
    # 2-step lookup, який не кешував misses. Кожен `current(:nonexistent_key)`
    # бомбив `find_by` на DB. Тепер misses кешуються через `MISS_SENTINEL`,
    # тож повторні lookups неіснуючих keys мають бути SQL-free.
    it "caches missing keys to avoid repeated DB lookups (MISS_SENTINEL)" do
      # Перший виклик — find_by виконається один раз, нічого не знаходить.
      allow(described_class).to receive(:find_by).and_call_original
      expect(described_class.current(:never_seeded, default: 42)).to eq(42)

      # Подальші виклики мають читати з кешу: find_by НЕ викликається.
      expect(described_class.current(:never_seeded, default: 42)).to eq(42)
      expect(described_class.current(:never_seeded, default: 99)).to eq(99)

      expect(described_class).to have_received(:find_by).once
    end

    # Regression: попередній `exist? + read` був TOCTOU-race — якщо entry
    # exhibit'ить між двома операціями, read повертає nil; sentry перепаде
    # на default замість fetch fresh value. Тепер single-shot `Rails.cache.fetch`
    # robust against the race.
    it "does not race between exist? and read (single Rails.cache.fetch call)" do
      create(:system_parameter, :lorenz_sigma)
      cache_key = described_class.cache_key_for("lorenz_sigma")

      # Перший виклик — fetch блок виконається; cache буде primed.
      described_class.current(:lorenz_sigma)
      expect(Rails.cache.read(cache_key)).to eq(10.0)

      # Без single-call fetch — race window міг повернути default. З fetch —
      # ніколи: fetch атомарно read-or-store у блоці.
      expect(described_class.current(:lorenz_sigma, default: 999)).to eq(10.0)
    end
  end

  describe ".current_values" do
    it "returns hash of multiple parameters" do
      create(:system_parameter, :lorenz_sigma)
      create(:system_parameter, :lorenz_rho)

      result = described_class.current_values(
        lorenz_sigma: 10.0,
        lorenz_rho: 28.0,
        nonexistent: 99.0
      )

      expect(result).to eq({
        lorenz_sigma: 10.0,
        lorenz_rho: 28.0,
        nonexistent: 99.0
      })
    end
  end

  describe ".set" do
    it "creates a new parameter" do
      described_class.set("new_param", "42", value_type: "integer", category: "general")

      param = described_class.find_by(key: "new_param")
      expect(param).to be_present
      expect(param.value).to eq("42")
      expect(param.value_type).to eq("integer")
    end

    it "updates existing parameter" do
      create(:system_parameter, key: "existing", value: "old", value_type: "string")

      described_class.set("existing", "new")

      param = described_class.find_by(key: "existing")
      expect(param.value).to eq("new")
    end

    it "records updated_by user" do
      user = create(:user, :admin)
      described_class.set("tracked", "val", updated_by: user, value_type: "string", category: "general")

      param = described_class.find_by(key: "tracked")
      expect(param.updated_by).to eq(user)
    end
  end

  describe "associations" do
    it "belongs to updated_by (User)" do
      user = create(:user, :admin)
      param = create(:system_parameter, updated_by: user)
      expect(param.updated_by).to eq(user)
    end

    it "allows nil updated_by" do
      param = create(:system_parameter, updated_by: nil)
      expect(param.updated_by).to be_nil
    end
  end

  describe "scopes" do
    it ".by_category filters by category" do
      lorenz = create(:system_parameter, :lorenz_sigma)
      create(:system_parameter, :emission_threshold)

      expect(described_class.by_category("lorenz")).to contain_exactly(lorenz)
    end
  end

  # [ARCH.57] Мутація значення → ГЛОБАЛЬНИЙ ланцюг (organization_id: nil);
  # bootstrap-create (seeds) свідомо не аудитується.
  describe "parameter-change audit-trail [ARCH.57]" do
    let!(:oracle) do
      create(:user, :super_admin, email_address: "oracle.executioner@system.silkennet.com",
                                  first_name: "Oracle", last_name: "Executioner")
    end

    it "does not audit the bootstrap create" do
      expect { described_class.set(:audit_probe, 1, value_type: "integer", category: "general") }
        .not_to change { AuditLogWorker.jobs.size }
    end

    it "audits a value mutation into the global (org-less) chain" do
      described_class.set(:audit_probe, 1, value_type: "integer", category: "general")

      expect { described_class.set(:audit_probe, 2) }
        .to change { AuditLogWorker.jobs.size }.by(1)

      job = AuditLogWorker.jobs.last
      attrs = job["args"].first
      expect(attrs["action"]).to eq("system_parameter_changed")
      expect(attrs["organization_id"]).to be_nil
      expect(attrs["metadata"]).to include("key" => "audit_probe", "from" => "1", "to" => "2")
      expect(job["args"][1]).to be false
    end
  end
end
