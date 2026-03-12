# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::BaseController, type: :request do
  describe "RBAC helpers" do
    let(:controller) { described_class.new }

    before do
      allow(controller).to receive(:render)
      allow(controller).to receive(:render_forbidden)
    end

    describe "authorize_admin! when current_user is nil" do
      it "calls render_forbidden" do
        allow(controller).to receive(:current_user).and_return(nil)
        allow(controller).to receive(:render_forbidden).and_call_original
        allow(controller).to receive(:render)
        controller.send(:authorize_admin!)
        expect(controller).to have_received(:render_forbidden)
      end
    end

    describe "authorize_super_admin! when current_user is nil" do
      it "calls render_forbidden" do
        allow(controller).to receive(:current_user).and_return(nil)
        allow(controller).to receive(:render_forbidden).and_call_original
        allow(controller).to receive(:render)
        controller.send(:authorize_super_admin!)
        expect(controller).to have_received(:render_forbidden)
      end
    end

    describe "authorize_forester! when current_user is nil" do
      it "calls render_forbidden" do
        allow(controller).to receive(:current_user).and_return(nil)
        allow(controller).to receive(:render_forbidden).and_call_original
        allow(controller).to receive(:render)
        controller.send(:authorize_forester!)
        expect(controller).to have_received(:render_forbidden)
      end
    end

    describe "authorize_admin! with admin user" do
      it "does not call render_forbidden" do
        admin = create(:user, :admin)
        allow(controller).to receive(:current_user).and_return(admin)
        controller.send(:authorize_admin!)
        expect(controller).not_to have_received(:render_forbidden)
      end
    end

    describe "authorize_forester! with forester user" do
      it "does not call render_forbidden" do
        forester = create(:user, :forester)
        allow(controller).to receive(:current_user).and_return(forester)
        controller.send(:authorize_forester!)
        expect(controller).not_to have_received(:render_forbidden)
      end
    end
  end

  describe "render_internal_server_error" do
    it "logs and renders 500 error" do
      controller = described_class.new
      allow(controller).to receive(:render)
      exception = StandardError.new("test failure")
      exception.set_backtrace([ "line1", "line2" ])

      controller.send(:render_internal_server_error, exception)
      expect(controller).to have_received(:render).with(
        hash_including(json: hash_including(:error), status: :internal_server_error)
      )
    end
  end

  describe "signed_in? helper" do
    it "returns false when no user is authenticated" do
      controller = described_class.new
      allow(controller).to receive(:current_user).and_return(nil)
      expect(controller.send(:signed_in?)).to be false
    end

    it "returns true when user is authenticated" do
      organization = create(:organization)
      user_for_test = create(:user, organization: organization, password: "password12345")
      controller = described_class.new
      allow(controller).to receive(:current_user).and_return(user_for_test)
      expect(controller.send(:signed_in?)).to be true
    end
  end
end
