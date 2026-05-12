# frozen_string_literal: true

require "spec_helper"
require "securerandom"
require "openssl"
require "base64"
require Rails.root.join("app/services/security/weak_key_detector") if defined?(Rails)
# Direct load when Rails is not booted (keeps the suite runnable on machines
# without a Postgres connection — this service has zero DB dependencies).
unless defined?(Security::WeakKeyDetector)
  require_relative "../../../app/services/security/weak_key_detector"
end

RSpec.describe Security::WeakKeyDetector do
  # NB: every "weak" sample below is a *publicly published* test vector from
  # FIPS-197 / NIST SP 800-38A / RFC 3686 / RFC 4231. They are explicitly
  # NOT secrets — that is the whole point of having them in a blocklist.

  describe ".detect" do
    context "with publicly known test vectors" do
      it "flags FIPS-197 Appendix B (AES-128) — exact hex match" do
        result = described_class.detect("2b7e151628aed2a6abf7158809cf4f3c")
        expect(result).to include("FIPS-197 Appendix B")
      end

      it "flags FIPS-197 Appendix B — raw 16-byte interpretation" do
        raw = [ "2b7e151628aed2a6abf7158809cf4f3c" ].pack("H*")
        expect(described_class.detect(raw)).to include("FIPS-197 Appendix B")
      end

      it "flags FIPS-197 Appendix B as a PREFIX of a 32-byte master (the historical BLOCKER shape)" do
        # First 16 bytes = the published vector, second 16 bytes = CSPRNG noise.
        tail = SecureRandom.hex(16)
        composite = "2b7e151628aed2a6abf7158809cf4f3c" + tail
        result = described_class.detect(composite)
        expect(result).to include("starts with").and include("FIPS-197 Appendix B")
      end

      it "flags FIPS-197 Appendix C.3 (AES-256, 00..1f)" do
        hex = "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"
        expect(described_class.detect(hex)).to include("FIPS-197 Appendix C.3")
      end

      it "flags NIST SP 800-38A F.5 AES-256 CTR sample key" do
        hex = "603deb1015ca71be2b73aef0857d77811f352c073b6108d72d9810a30914dff4"
        expect(described_class.detect(hex)).to include("NIST SP 800-38A F.5")
      end

      it "flags RFC 3686 AES-CTR test vector #1" do
        expect(described_class.detect("ae6852f8121067cc4bf7a5765577f39e"))
          .to include("RFC 3686")
      end

      it "flags RFC 4231 HMAC test case 1 (20×0x0b)" do
        expect(described_class.detect("0b" * 20))
          .to include("RFC 4231")
      end
    end

    context "with degenerate patterns" do
      it "flags an all-zero master" do
        expect(described_class.detect("\x00" * 32)).to include("all-zero")
      end

      it "flags an all-0xFF master" do
        expect(described_class.detect("\xFF" * 32)).to include("all-0xFF")
      end

      it "flags any single-byte repeat" do
        expect(described_class.detect("\x42" * 32)).to include("single-byte repeat")
      end

      it "flags a strictly-monotonic byte run (40 41 42 …)" do
        # Use a range that is NOT a known FIPS vector (00..1f IS C.3) so we
        # exercise the degenerate-pattern check rather than the vector match.
        bytes = (0x40..0x5F).map { |b| b.chr }.join.b
        expect(described_class.detect(bytes)).to include("strictly-monotonic")
      end
    end

    context "with placeholder strings" do
      %w[
        CHANGEME
        change-me
        placeholder
        TODO-replace-me
        secret-here
        your-master-key-here
        default-dev-only-key
        not-a-real-key-yet
      ].each do |needle|
        it "flags placeholder #{needle.inspect}" do
          padded = needle.ljust(32, "x") # pad so it reaches degenerate-min length
          expect(described_class.detect(padded)).to include("placeholder")
        end
      end

      it "flags an unsubstituted <…> template placeholder" do
        expect(described_class.detect("<your-master-key>")).to include("placeholder")
      end

      it "flags the test-suite fixture used by spec/rails_helper.rb" do
        expect(described_class.detect("silken-net-test-master-key-32b!!"))
          .to include("placeholder")
      end
    end

    context "with a strong, randomly-generated master key" do
      it "returns nil for SecureRandom.hex(32)" do
        50.times do
          key = SecureRandom.hex(32)
          expect(described_class.detect(key)).to(
            be_nil,
            "Expected CSPRNG key #{key} not to be flagged (false positive)"
          )
        end
      end

      it "returns nil for SecureRandom.bytes(32) raw" do
        50.times do
          expect(described_class.detect(SecureRandom.bytes(32))).to be_nil
        end
      end
    end

    context "with edge cases" do
      it "returns nil for nil" do
        expect(described_class.detect(nil)).to be_nil
      end

      it "returns nil for empty string" do
        expect(described_class.detect("")).to be_nil
      end

      it "decorates the reason with the hint when provided" do
        result = described_class.detect("\x00" * 32, hint: "PROVISIONING_MASTER_KEY")
        expect(result).to start_with("PROVISIONING_MASTER_KEY: ")
      end

      it "catches a hex-encoded FIPS vector even when value also looks like ASCII" do
        # All-hex ASCII string — checked both raw AND hex-decoded.
        expect(described_class.detect("000102030405060708090a0b0c0d0e0f"))
          .to include("FIPS-197 Appendix C.1")
      end

      it "does not crash on non-ASCII binary noise" do
        expect { described_class.detect((0..255).map(&:chr).join.b) }.not_to raise_error
      end
    end
  end

  describe ".weak?" do
    it "is true for known vectors" do
      expect(described_class.weak?("2b7e151628aed2a6abf7158809cf4f3c")).to be true
    end

    it "is false for a CSPRNG key" do
      expect(described_class.weak?(SecureRandom.hex(32))).to be false
    end
  end
end
