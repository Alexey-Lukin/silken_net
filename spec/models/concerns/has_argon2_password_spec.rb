# frozen_string_literal: true

require "rails_helper"

RSpec.describe HasArgon2Password, type: :model do
  subject(:user) { create(:user, password: "password12345") }

  describe "#password=" do
    it "stores an argon2id hash in password_digest" do
      expect(user.password_digest).to start_with("$argon2id$")
    end

    it "sets password_digest to nil when given nil" do
      user.password = nil
      expect(user.password_digest).to be_nil
    end

    it "does not change password_digest when given an empty string" do
      original_digest = user.password_digest
      user.password = ""
      expect(user.password_digest).to eq(original_digest)
    end

    it "generates different hashes for the same password (unique salt)" do
      user2 = create(:user, password: "password12345")
      expect(user.password_digest).not_to eq(user2.password_digest)
    end
  end

  describe "#authenticate" do
    it "returns the user with correct password" do
      expect(user.authenticate("password12345")).to eq(user)
    end

    it "returns false with incorrect password" do
      expect(user.authenticate("wrong_password")).to be false
    end

    it "returns false when password_digest is blank" do
      user.password_digest = nil
      expect(user.authenticate("password12345")).to be false
    end
  end

  describe "#authenticate_password" do
    it "is aliased to authenticate" do
      expect(user.method(:authenticate_password)).to eq(user.method(:authenticate))
    end
  end

  describe "#password_salt" do
    it "returns a hex-encoded salt string" do
      salt = user.password_salt
      expect(salt).to be_a(String)
      expect(salt).to match(/\A[0-9a-f]+\z/)
    end

    it "returns nil when password_digest is blank" do
      user.password_digest = nil
      expect(user.password_salt).to be_nil
    end

    it "changes when password is changed" do
      old_salt = user.password_salt
      user.update!(password: "new_password_12345")
      expect(user.password_salt).not_to eq(old_salt)
    end

    it "is safe for JSON serialization (UTF-8 compatible)" do
      expect { user.password_salt.to_json }.not_to raise_error
    end
  end
end
