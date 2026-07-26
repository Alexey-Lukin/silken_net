# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Security::EncryptionKeyGuard do
  describe ".violations" do
    # Three >=32-char random keys — a clean production AR-encryption env.
    let(:clean_env) do
      {
        "ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY"         => SecureRandom.alphanumeric(32),
        "ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY"   => SecureRandom.alphanumeric(32),
        "ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT" => SecureRandom.alphanumeric(32)
      }
    end

    it "passes a clean env with three strong keys" do
      expect(described_class.violations(clean_env)).to be_empty
    end

    it "flags a missing key" do
      env = clean_env.except("ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY")
      expect(described_class.violations(env))
        .to include(a_string_matching(/\[ar-encryption\].*PRIMARY_KEY is not set/))
    end

    it "flags a blank key" do
      env = clean_env.merge("ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY" => "")
      expect(described_class.violations(env))
        .to include(a_string_matching(/DETERMINISTIC_KEY is not set/))
    end

    it "flags a too-short key (< 32 chars)" do
      env = clean_env.merge("ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY" => "short")
      expect(described_class.violations(env))
        .to include(a_string_matching(/PRIMARY_KEY is 5 chars/))
    end

    it "surfaces a WeakKeyDetector reason (known-vector / degenerate key)" do
      allow(Security::WeakKeyDetector).to receive(:detect).and_return("matches a public test vector")
      expect(described_class.violations(clean_env))
        .to include(a_string_matching(/\[ar-encryption\] matches a public test vector/))
    end

    it "reports every missing key at once, not just the first" do
      expect(described_class.violations({}).size).to eq(3)
    end
  end
end
