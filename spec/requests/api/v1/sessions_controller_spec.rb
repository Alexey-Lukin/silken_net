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
      first_token = response.parsed_body["token"]

      # Second login should reset the old session and create a new one
      expect {
        post "/api/v1/login", params: { email: user.email_address, password: "password12345" }, as: :json
      }.to change(user.sessions, :count).by(1)
      expect(response).to have_http_status(:created)
      expect(response.parsed_body["token"]).not_to eq(first_token)
    end
  end

  describe "DELETE /api/v1/logout" do
    let(:api_token) { user.generate_token_for(:api_access) }
    let(:headers) { { "Authorization" => "Bearer #{api_token}" } }

    it "logs out the user and returns success message" do
      delete "/api/v1/logout", headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["message"]).to be_present
    end

    it "returns 401 without authentication" do
      delete "/api/v1/logout", as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
