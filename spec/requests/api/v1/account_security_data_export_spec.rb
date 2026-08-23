# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# [SEC.18] DSAR self-service: субʼєкт качає ВЛАСНІ дані файлом (Art.15/20).
RSpec.describe "GET /account_security/data_export", type: :request do
  let(:organization) { create(:organization) }
  let(:user) do
    create(:user, :forester,
           organization: organization,
           first_name: "Дарина",
           password: "Str0ng!Passw0rd", password_confirmation: "Str0ng!Passw0rd")
  end

  # [TEST.16] Ліхтар успіху — інакше невдалий логін лишає приклад на АНОНІМІ.
  def sign_in!(u) = sign_in_via_form(u, password: "Str0ng!Passw0rd")

  it "returns the subject's data as a JSON attachment" do
    sign_in!(user)
    get "/account_security/data_export"

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("application/json")
    expect(response.headers["Content-Disposition"]).to include("attachment")
    expect(response.headers["Content-Disposition"]).to include("silkennet-data-export-")

    body = JSON.parse(response.body)
    expect(body["user"]["email_address"]).to eq(user.email_address)
    expect(body["user"]["first_name"]).to eq("Дарина")
  end

  it "never includes credentials and never leaks a foreign subject" do
    stranger = create(:user, organization: organization, email_address: "stranger@example.com",
                             password: "Str0ng!Passw0rd", password_confirmation: "Str0ng!Passw0rd")
    stranger.sessions.create!(ip_address: "192.0.2.99", user_agent: "OtherBrowser")

    sign_in!(user)
    get "/account_security/data_export"

    expect(response.body).not_to include("password_digest")
    expect(response.body).not_to include("stranger@example.com")
    expect(response.body).not_to include("192.0.2.99")
  end

  it "refuses an unauthenticated request" do
    get "/account_security/data_export"
    expect(response).to have_http_status(:unauthorized)
  end
end
