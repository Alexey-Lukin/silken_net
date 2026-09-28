# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProvisioningSession do
  describe "validations" do
    it "is valid with the factory defaults" do
      expect(build(:provisioning_session)).to be_valid
    end

    it "rejects gilka outside the allow-list" do
      session = build(:provisioning_session, gilka: "Z")
      expect(session).not_to be_valid
      expect(session.errors[:gilka]).to be_present
    end

    it "requires se_serial_hex when gilka is B" do
      session = build(:provisioning_session, gilka: "B", se_serial_hex: nil)
      expect(session).not_to be_valid
      expect(session.errors[:se_serial_hex]).to be_present
    end

    it "accepts se_serial_hex when gilka is B" do
      session = build(:provisioning_session, :gilka_b)
      expect(session).to be_valid
    end

    it "rejects se_serial_hex that is not 9 bytes hex" do
      session = build(:provisioning_session, :gilka_b, se_serial_hex: "ABCD")
      expect(session).not_to be_valid
      expect(session.errors[:se_serial_hex]).to be_present
    end

    it "enforces the 2-Person Rule — supervisor must differ from operator" do
      user = create(:user, :super_admin)
      session = build(:provisioning_session, operator: user, supervisor: user)
      expect(session).not_to be_valid
      expect(session.errors[:supervisor_id].first).to include("2-Person Rule")
    end

    # [SEC.2] L2 палять поза конвеєром (03_05 §3.6, ⚖️ founder 2026-09-28) — сесія його не приймає.
    it "rejects rdp_level outside {0, 1} — L2 included" do
      expect(build(:provisioning_session, rdp_level: 2)).not_to be_valid
      expect(build(:provisioning_session, rdp_level: 3)).not_to be_valid
    end
  end

  describe "AASM transitions" do
    let(:session) { create(:provisioning_session) }

    it "starts in :pending" do
      expect(session).to be_pending
    end

    describe "#approve! (raw event — credential-gated) [SEC.3]" do
      it "refuses a bare approve! — credentials not verified (no console self-approve)" do
        # The session has a valid supervisor, but no password was verified this call,
        # so the credentials_verified? guard refuses the transition. Only
        # #approve_with_credentials! (Argon2id) can reach :supervisor_approved.
        expect { session.approve! }.to raise_error(AASM::InvalidTransition)
        expect(session.reload).to be_pending
      end

      it "refuses to approve when supervisor is absent" do
        session.update_columns(supervisor_id: nil)
        expect { session.approve! }.to raise_error(AASM::InvalidTransition)
      end
    end

    describe "#approve_with_credentials! [SEC.3]" do
      # user factory password = "password12345"; MFA — як після активації S6.21
      let(:sup) { create(:user, otp_secret: ROTP::Base32.random, otp_required_for_login: true) }
      let(:cred_session) { create(:provisioning_session, operator: create(:user), supervisor: sup) }
      let(:code) { ROTP::TOTP.new(sup.otp_secret).now }

      it "approves when the supervisor password and TOTP are correct" do
        expect { cred_session.approve_with_credentials!("password12345", otp: code) }
          .to change(cred_session, :state).from("pending").to("supervisor_approved")
      end

      it "raises and stays pending on a wrong supervisor password" do
        expect { cred_session.approve_with_credentials!("wrong-password", otp: code) }
          .to raise_error(ProvisioningSession::SupervisorAuthError, /authentication failed/)
        expect(cred_session.reload).to be_pending
      end

      it "raises when no supervisor is assigned" do
        cred_session.update_columns(supervisor_id: nil)
        expect { cred_session.approve_with_credentials!("password12345", otp: code) }
          .to raise_error(ProvisioningSession::SupervisorAuthError, /no supervisor/)
      end

      # ⚖️ делеговано 2026-09-28: пароль — один фактор, тож без MFA не схвалює
      # ЖОДНА роль (рекомендація називала лише super_admin; supervisor_id — будь-який User).
      %i[admin super_admin].each do |role|
        it "refuses a #{role} supervisor without MFA — password alone is one factor" do
          plain = create(:user, role)
          session = create(:provisioning_session, operator: create(:user), supervisor: plain)
          expect { session.approve_with_credentials!("password12345", otp: "123456") }
            .to raise_error(ProvisioningSession::SupervisorAuthError, /no MFA/)
          expect(session.reload).to be_pending
        end
      end

      # Предмет гарда `mfa_enabled?`: секрет видано setup-флоу (S6.21), активацію кинуто —
      # валідний код від такого секрета `verify_totp!` прийняв би, а MFA в людини немає.
      it "refuses a half-activated MFA — secret provisioned, login MFA never switched on" do
        sup.update!(otp_required_for_login: false)
        expect { cred_session.approve_with_credentials!("password12345", otp: code) }
          .to raise_error(ProvisioningSession::SupervisorAuthError, /no MFA/)
        expect(cred_session.reload).to be_pending
      end

      it "refuses a blank or wrong TOTP code" do
        expect { cred_session.approve_with_credentials!("password12345", otp: "") }
          .to raise_error(ProvisioningSession::SupervisorAuthError, /TOTP/)
        wrong = code == "000000" ? "111111" : "000000"
        expect { cred_session.approve_with_credentials!("password12345", otp: wrong) }
          .to raise_error(ProvisioningSession::SupervisorAuthError, /TOTP/)
        expect(cred_session.reload).to be_pending
      end

      it "refuses the code already spent on the supervisor's login (shared otp_last_used_at)" do
        expect(sup.verify_totp!(code)).to be(true) # вхід супервайзера тим самим кодом
        expect { cred_session.approve_with_credentials!("password12345", otp: code) }
          .to raise_error(ProvisioningSession::SupervisorAuthError, /TOTP/)
        expect(cred_session.reload).to be_pending
      end

      it "does not leak credential verification — a later bare approve! still fails [SEC.3]" do
        expect { cred_session.approve_with_credentials!("wrong-password", otp: code) }
          .to raise_error(ProvisioningSession::SupervisorAuthError)
        expect { cred_session.approve! }.to raise_error(AASM::InvalidTransition)
        expect(cred_session.reload).to be_pending
      end
    end

    describe "#start!" do
      it "transitions supervisor_approved → active and stamps started_at" do
        approved = create(:provisioning_session, :supervisor_approved)
        expect { approved.start! }.to change(approved, :state).from("supervisor_approved").to("active")
        expect(approved.started_at).to be_within(2.seconds).of(Time.current)
      end

      it "cannot start without supervisor approval" do
        expect { session.start! }.to raise_error(AASM::InvalidTransition)
      end
    end

    describe "#complete!" do
      it "transitions active → completed and stamps completed_at" do
        active = create(:provisioning_session, :active)
        expect { active.complete! }.to change(active, :state).from("active").to("completed")
        expect(active.completed_at).to be_within(2.seconds).of(Time.current)
      end
    end

    describe "#fail_with!" do
      it "captures error_message and transitions to :failed" do
        active = create(:provisioning_session, :active)
        expect { active.fail_with!("HSM unreachable") }
          .to change(active, :state).from("active").to("failed")
        expect(active.error_message).to eq("HSM unreachable")
        expect(active.completed_at).to be_within(2.seconds).of(Time.current)
      end

      it "is reachable from supervisor_approved (fail before execution)" do
        approved = create(:provisioning_session, :supervisor_approved)
        expect { approved.fail_with!("operator aborted") }
          .to change(approved, :state).from("supervisor_approved").to("failed")
      end
    end
  end
end
