# frozen_string_literal: true

require "rails_helper"

RSpec.describe FactoryFlashing::MasterKeySource do
  describe FactoryFlashing::MasterKeySource::EnvAdapter do
    subject(:adapter) { described_class.new }

    around do |example|
      original = ENV["PROVISIONING_MASTER_KEY"]
      example.run
    ensure
      ENV["PROVISIONING_MASTER_KEY"] = original
    end

    it "returns the ENV value when it passes WeakKeyDetector" do
      ENV["PROVISIONING_MASTER_KEY"] = SecureRandom.hex(32)
      expect(adapter.fetch_master_key).to eq(ENV["PROVISIONING_MASTER_KEY"])
    end

    it "raises UnavailableError when ENV is blank" do
      ENV["PROVISIONING_MASTER_KEY"] = nil
      expect { adapter.fetch_master_key }
        .to raise_error(FactoryFlashing::MasterKeySource::UnavailableError, /blank/)
    end

    it "raises UnavailableError when WeakKeyDetector flags the key" do
      ENV["PROVISIONING_MASTER_KEY"] = "00" * 32
      expect { adapter.fetch_master_key }
        .to raise_error(FactoryFlashing::MasterKeySource::UnavailableError, /rejected/)
    end

    it "raises UnavailableError when ENV is the FIPS-197 test vector" do
      ENV["PROVISIONING_MASTER_KEY"] = "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"
      expect { adapter.fetch_master_key }
        .to raise_error(FactoryFlashing::MasterKeySource::UnavailableError, /rejected/)
    end
  end

  describe FactoryFlashing::MasterKeySource::BitwardenAdapter do
    it "raises NotImplementedError pointing at the design doc" do
      expect { described_class.new.fetch_master_key }
        .to raise_error(NotImplementedError, /SEC\.3.*03_06/)
    end
  end

  describe ".default" do
    it "returns an EnvAdapter instance" do
      expect(described_class.default).to be_a(FactoryFlashing::MasterKeySource::EnvAdapter)
    end
  end

  # abstract Base raises NotImplementedError
  describe FactoryFlashing::MasterKeySource::Base do
    it "raises NotImplementedError to enforce adapter contract" do
      expect { described_class.new.fetch_master_key }
        .to raise_error(NotImplementedError, /must implement #fetch_master_key/)
    end
  end
end
