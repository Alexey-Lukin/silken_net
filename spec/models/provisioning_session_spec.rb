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

    it "requires atecc_serial_hex when gilka is B" do
      session = build(:provisioning_session, gilka: "B", atecc_serial_hex: nil)
      expect(session).not_to be_valid
      expect(session.errors[:atecc_serial_hex]).to be_present
    end

    it "accepts atecc_serial_hex when gilka is B" do
      session = build(:provisioning_session, :gilka_b)
      expect(session).to be_valid
    end

    it "rejects atecc_serial_hex that is not 9 bytes hex" do
      session = build(:provisioning_session, :gilka_b, atecc_serial_hex: "ABCD")
      expect(session).not_to be_valid
      expect(session.errors[:atecc_serial_hex]).to be_present
    end

    it "enforces the 2-Person Rule — supervisor must differ from operator" do
      user = create(:user, :super_admin)
      session = build(:provisioning_session, operator: user, supervisor: user)
      expect(session).not_to be_valid
      expect(session.errors[:supervisor_id].first).to include("2-Person Rule")
    end

    it "rejects rdp_level outside {0, 1, 2}" do
      expect(build(:provisioning_session, rdp_level: 3)).not_to be_valid
    end
  end

  describe "AASM transitions" do
    let(:session) { create(:provisioning_session) }

    it "starts in :pending" do
      expect(session).to be_pending
    end

    describe "#approve!" do
      it "transitions pending → supervisor_approved and stamps timestamp" do
        expect { session.approve! }.to change(session, :state).from("pending").to("supervisor_approved")
        expect(session.supervisor_approved_at).to be_within(2.seconds).of(Time.current)
      end

      it "refuses to approve when supervisor is absent" do
        session.update_columns(supervisor_id: nil)
        expect { session.approve! }.to raise_error(AASM::InvalidTransition)
      end
    end

    describe "#approve_with_credentials! [SEC.3]" do
      let(:sup) { create(:user) } # user factory password = "password12345"
      let(:cred_session) { create(:provisioning_session, operator: create(:user), supervisor: sup) }

      it "approves when the supervisor password is correct" do
        expect { cred_session.approve_with_credentials!("password12345") }
          .to change(cred_session, :state).from("pending").to("supervisor_approved")
      end

      it "raises and stays pending on a wrong supervisor password" do
        expect { cred_session.approve_with_credentials!("wrong-password") }
          .to raise_error(ProvisioningSession::SupervisorAuthError, /authentication failed/)
        expect(cred_session.reload).to be_pending
      end

      it "raises when no supervisor is assigned" do
        cred_session.update_columns(supervisor_id: nil)
        expect { cred_session.approve_with_credentials!("password12345") }
          .to raise_error(ProvisioningSession::SupervisorAuthError, /no supervisor/)
      end
    end

    describe "#start!" do
      it "transitions supervisor_approved → active and stamps started_at" do
        session.approve!
        expect { session.start! }.to change(session, :state).from("supervisor_approved").to("active")
        expect(session.started_at).to be_within(2.seconds).of(Time.current)
      end

      it "cannot start without supervisor approval" do
        expect { session.start! }.to raise_error(AASM::InvalidTransition)
      end
    end

    describe "#complete!" do
      it "transitions active → completed and stamps completed_at" do
        session.approve!
        session.start!
        expect { session.complete! }.to change(session, :state).from("active").to("completed")
        expect(session.completed_at).to be_within(2.seconds).of(Time.current)
      end
    end

    describe "#fail_with!" do
      it "captures error_message and transitions to :failed" do
        session.approve!
        session.start!
        expect { session.fail_with!("HSM unreachable") }
          .to change(session, :state).from("active").to("failed")
        expect(session.error_message).to eq("HSM unreachable")
        expect(session.completed_at).to be_within(2.seconds).of(Time.current)
      end

      it "is reachable from supervisor_approved (fail before execution)" do
        session.approve!
        expect { session.fail_with!("operator aborted") }
          .to change(session, :state).from("supervisor_approved").to("failed")
      end
    end
  end
end
