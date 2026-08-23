# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# [ARCH.61] /sidekiq за admin-only route-constraint — єдиний шлюз до
# Sidekiq::Web (Rack-app, BaseController-auth не діє). Unmatched → 404.
RSpec.describe "Sidekiq Web UI mount", type: :request do
  let(:organization) { create(:organization) }

  # 🔴 [TEST.16] Через `sign_in_via_form` (ліхтар успіху), НЕ через голий
  # `post "/login"`. Доти три з чотирьох прикладів нижче чекали `404` — рівно
  # те, що віддає АНОНІМНИЙ запит на admin-only маршрут, — тож невдалий логін
  # лишав їх зеленими. Серед них пін на salt-bound відкликання (`SEC.16`):
  # найгостріший приклад файлу доводив нуль.
  def login_as(user)
    sign_in_via_form(user, password: "password12345")
  end

  it "returns 404 for anonymous visitors (path not revealed)" do
    get "/sidekiq"
    expect(response).to have_http_status(:not_found)
  end

  it "returns 404 for a non-admin session" do
    login_as create(:user, :forester, organization: organization, password: "password12345")
    get "/sidekiq"
    expect(response).to have_http_status(:not_found)
  end

  it "serves the dashboard to an admin session" do
    login_as create(:user, :admin, organization: organization, password: "password12345")
    get "/sidekiq"
    expect(response).to have_http_status(:ok)
  end

  it "rejects an admin cookie staled by a password change (SEC.16 salt-bound)" do
    admin = create(:user, :admin, organization: organization, password: "password12345")
    login_as admin
    admin.update!(password: "rotated-strong-pass-99")

    get "/sidekiq"
    expect(response).to have_http_status(:not_found)
  end
end
