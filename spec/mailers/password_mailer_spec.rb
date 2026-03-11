# frozen_string_literal: true

require "rails_helper"

RSpec.describe PasswordMailer, type: :mailer do
  describe "#reset_instructions" do
    subject(:mail) { described_class.with(user: user).reset_instructions }

    let(:user) { create(:user) }


    it "sends to the user email address" do
      expect(mail.to).to eq([ user.email_address ])
    end

    it "includes the reset password subject" do
      expect(mail.subject).to include("Скидання пароля")
    end

    it "renders the body" do
      expect(mail.body.encoded).to be_present
    end
  end
end
