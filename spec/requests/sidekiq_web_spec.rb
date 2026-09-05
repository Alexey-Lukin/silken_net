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

  # 🔴 [⚖️ founder 2026-09-05] Цей приклад БУВ перевернутий: він звався «serves the
  # dashboard to an admin session» і чекав `200`, тобто ЦЕМЕНТУВАВ периметр, який
  # присуд відкинув. `admin` у нас — роль ОРГАНІЗАЦІЙНА, а `Sidekiq::Web` показує
  # аргументи джоб УСІХ орендарів (`tree_id`/`wallet_id`/DID у Retries та Dead),
  # тобто клієнтський адміністратор діставав вікно повз `acting_organization!`.
  # ⛔ Не повертати `:admin` у дозвіл: збіг із `admin_or_above?` був випадковим.
  it "returns 404 for an ORGANISATION admin — платформенний периметр, не орг-роль" do
    login_as create(:user, :admin, organization: organization, password: "password12345")
    get "/sidekiq"
    expect(response).to have_http_status(:not_found)
  end

  it "serves the dashboard to a super_admin session" do
    login_as create(:user, :super_admin, password: "password12345")
    get "/sidekiq"
    expect(response).to have_http_status(:ok)
  end

  # ⚠️ [guard-craft #134, друга половина] Актор тут ОБОВʼЯЗКОВО `super_admin`:
  # доти приклад брав `:admin`, і після звуження периметра він лишився б ЗЕЛЕНИМ
  # ВАКУУМНО — `404` прийшов би через відмову РОЛІ, а не через протухлий salt,
  # тобто найгостріший пін файлу доводив би нуль, не червонівши.
  it "rejects a super_admin cookie staled by a password change (SEC.16 salt-bound)" do
    admin = create(:user, :super_admin, password: "password12345")
    login_as admin
    admin.update!(password: "rotated-strong-pass-99")

    get "/sidekiq"
    expect(response).to have_http_status(:not_found)
  end
end
