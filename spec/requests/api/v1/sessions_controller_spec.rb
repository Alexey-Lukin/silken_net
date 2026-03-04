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
      # First login to establish a session
      post "/api/v1/login", params: { email: user.email_address, password: "password12345" }, as: :json
      expect(response).to have_http_status(:created)

      # Second login should reset the old session and create a new one
      expect_any_instance_of(Api::V1::SessionsController).to receive(:reset_session).and_call_original
      post "/api/v1/login", params: { email: user.email_address, password: "password12345" }, as: :json
      expect(response).to have_http_status(:created)
    end
  end
end
