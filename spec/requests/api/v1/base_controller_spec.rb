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

  describe "CSRF bypass for Bearer-token requests" do
    let(:controller) { described_class.new }

    it "lets Bearer-token requests through (CSRF check skipped)" do
      request = instance_double(ActionDispatch::Request, authorization: "Bearer abc.def.ghi")
      allow(controller).to receive(:request).and_return(request)
      expect { controller.send(:handle_unverified_request) }.not_to raise_error
    end

    it "raises InvalidAuthenticityToken for session-cookie requests" do
      request = instance_double(ActionDispatch::Request, authorization: nil)
      allow(controller).to receive(:request).and_return(request)
      expect { controller.send(:handle_unverified_request) }
        .to raise_error(ActionController::InvalidAuthenticityToken)
    end

    it "raises for non-Bearer auth schemes (Basic)" do
      request = instance_double(ActionDispatch::Request, authorization: "Basic dXNlcjpwYXNz")
      allow(controller).to receive(:request).and_return(request)
      expect { controller.send(:handle_unverified_request) }
        .to raise_error(ActionController::InvalidAuthenticityToken)
    end
  end

  describe "render_parameter_missing" do
    it "returns 400 with the missing param name" do
      controller = described_class.new
      allow(controller).to receive(:render)
      exception = ActionController::ParameterMissing.new(:codex_node_slug)

      controller.send(:render_parameter_missing, exception)
      expect(controller).to have_received(:render).with(
        hash_including(json: hash_including(:error), status: :bad_request)
      )
    end
  end

  describe "render_validation_error" do
    it "returns 422 with all validation messages" do
      controller = described_class.new
      allow(controller).to receive(:render)
      record = OpenStruct.new(errors: OpenStruct.new(full_messages: [ "Name can't be blank", "Email is invalid" ]))

      controller.send(:render_validation_error, record)
      expect(controller).to have_received(:render).with(
        hash_including(
          json: { errors: [ "Name can't be blank", "Email is invalid" ] },
          status: :unprocessable_content
        )
      )
    end
  end

  describe "render_not_found" do
    it "interpolates the model name into the error message" do
      controller = described_class.new
      allow(controller).to receive(:render)
      exception = ActiveRecord::RecordNotFound.new("not found")
      exception.instance_variable_set(:@model, "Tree")

      controller.send(:render_not_found, exception)
      expect(controller).to have_received(:render).with(
        hash_including(status: :not_found)
      )
    end
  end

  describe "render_forbidden_pundit" do
    it "returns 403 regardless of the Pundit policy raised" do
      controller = described_class.new
      allow(controller).to receive(:render)
      controller.send(:render_forbidden_pundit, instance_double(Pundit::NotAuthorizedError))
      expect(controller).to have_received(:render).with(
        hash_including(status: :forbidden)
      )
    end
  end

  describe "pagy_metadata" do
    it "extracts page/limit/count/pages from a Pagy object" do
      controller = described_class.new
      pagy = OpenStruct.new(page: 2, limit: 21, count: 105, last: 5)
      meta = controller.send(:pagy_metadata, pagy)
      expect(meta).to eq(page: 2, limit: 21, count: 105, pages: 5)
    end
  end

  describe "ews_alert_count_cached" do
    before { Rails.cache.delete("ews_alert_count_unresolved") }

    it "returns the unresolved alert count via Rails.cache" do
      controller = described_class.new
      allow(EwsAlert).to receive(:unresolved).and_return(double(count: 7))
      expect(controller.send(:ews_alert_count_cached)).to eq(7)
    end

    it "swallows any backend error and returns 0 so the sidebar never breaks" do
      controller = described_class.new
      allow(Rails.cache).to receive(:fetch).and_raise(StandardError, "redis down")
      expect(controller.send(:ews_alert_count_cached)).to eq(0)
    end
  end

  describe "ensure_organization!" do
    let(:controller) { described_class.new }

    it "is a no-op when current_user has an organization" do
      org = create(:organization)
      user = create(:user, organization: org)
      allow(controller).to receive(:current_user).and_return(user)
      allow(controller).to receive(:render)
      allow(controller).to receive(:render_auth_page)

      controller.send(:ensure_organization!)
      expect(controller).not_to have_received(:render)
      expect(controller).not_to have_received(:render_auth_page)
    end

    it "renders JSON 422 for json-format requests when org is missing" do
      user = build_stubbed(:user, organization: nil)
      allow(controller).to receive(:current_user).and_return(user)
      allow(controller).to receive(:render)

      mime_negotiator = instance_double(ActionController::MimeResponds::Collector)
      allow(mime_negotiator).to receive(:json).and_yield
      allow(mime_negotiator).to receive(:html)
      allow(controller).to receive(:respond_to).and_yield(mime_negotiator)

      controller.send(:ensure_organization!)
      expect(controller).to have_received(:render).with(
        hash_including(
          json: hash_including(:error, code: "no_organization"),
          status: :unprocessable_content
        )
      )
    end

    it "renders an HTML auth page for browser requests when org is missing" do
      user = build_stubbed(:user, organization: nil)
      allow(controller).to receive(:current_user).and_return(user)
      allow(controller).to receive(:render_auth_page)

      mime_negotiator = instance_double(ActionController::MimeResponds::Collector)
      allow(mime_negotiator).to receive(:json)
      allow(mime_negotiator).to receive(:html).and_yield
      allow(controller).to receive(:respond_to).and_yield(mime_negotiator)

      controller.send(:ensure_organization!)
      expect(controller).to have_received(:render_auth_page).with(
        hash_including(component: an_instance_of(Errors::NoOrganization), status: :unprocessable_content)
      )
    end
  end
end
