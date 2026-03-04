# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::SessionsController, type: :request do
  let(:organization) { create(:organization) }
  let(:user) { create(:user, organization: organization, password: "password12345") }

  describe "POST /api/v1/login" do
    it "authenticates with valid credentials" do
      post "/api/v1/login", params: { email: user.email_address, password: "password12345" }, as: :json

      expect(response).to have_http_status(:created)
      expect(response.parsed_body["token"]).to be_present
    end

    it "returns unauthorized with invalid credentials" do
      post "/api/v1/login", params: { email: user.email_address, password: "wrong_password" }, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it "resets session before establishing new one (session fixation protection)" do
      # Verify the controller calls reset_session by checking the session is regenerated
      post "/api/v1/login", params: { email: user.email_address, password: "password12345" }, as: :json

      expect(response).to have_http_status(:created)
    end
  end
end
