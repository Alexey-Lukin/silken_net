# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# [TEST.16] Cookie-логін для request-специв — із ЛІХТАРЕМ успіху.
#
# 🔴 Навіщо ліхтар, і чому його відсутність коштує саме на безпекових пінах.
# `SessionsController#create` на хибний пароль НЕ кидає — він рендерить
# `401` зі сторінкою логіну. Тож рукописний `post "/login", …` без перевірки
# лишає наступний запит АНОНІМНИМ, і кожен приклад, чиє очікування збігається
# з поведінкою анонімного відвідувача, проходить вакуумно.
#
# Виміряно 2026-08-23 на `spec/requests/sidekiq_web_spec.rb`: ТРИ з чотирьох
# прикладів там чекають `404` — рівно те, що віддає анонімний запит на
# admin-only маршрут. Серед них пін на salt-bound відкликання сесії
# (`SEC.16`), тобто найгостріший приклад файлу доводив нуль. Єдиним, що
# взагалі вимагало живої сесії, був приклад, який чекає `:ok` — випадковий
# ліхтар на весь файл.
#
# ⊥ Це НЕ дублікат `feature_helper#sign_in_as`: там браузерний шар (Capybara,
# `page.status_code`), тут — request-шар. Спільна в них лише ідея ліхтаря, і
# саме її бракувало другому.
#
# ⚠️ ОГОЛОШЕНА СТЕЛЯ:
#   1. Хелпер НЕ придатний для акаунтів з увімкненим MFA: там `create`
#      редиректить на MFA-challenge, а не на дашборд. Такий флоу має власний
#      дім — `spec/requests/api/v1/mfa_flow_spec.rb`.
#   2. Ліхтар доводить, що сесію ВИДАНО, а не що наступний запит авторизований
#      під потрібну роль — це вже предмет самого прикладу.
module RequestLoginHelper
  # `password:` обовʼязковий і явний: у дереві співіснують три різні паролі
  # фікстур, і мовчазний дефолт тут повертав би рівно ту тишу, проти якої
  # хелпер написаний.
  # `as:` несучий, а не косметичний: гілки успіху РІЗНІ за формою — браузерна
  # редиректить на дашборд, JSON-гілка віддає `200` з тілом. Спільна в них лише
  # невдача (`401`), тож ліхтар мусить знати, яку саме перемогу очікувати.
  def sign_in_via_form(user, password:, as: nil)
    post "/login", params: { email: user.email_address, password: password }, as: as

    expect(response).not_to have_http_status(:unauthorized),
                            "невірний пароль — сесію не видано, і далі приклад міряв би АНОНІМА"

    if as == :json
      # ⚠️ Саме `:success` (2xx), а не `:ok`: `render_api_login_success` віддає
      # **201 Created** — виміряно, не вгадано (перша редакція цього ліхтаря
      # пінила 200 і чесно почервоніла).
      expect(response).to have_http_status(:success),
                          "JSON-логін віддав #{response.status} — сесії немає"
    else
      expect(response).to have_http_status(:redirect),
                          "логін не редиректнув (#{response.status}) — сесії немає"
      expect(response.location.to_s).to include("dashboard"),
                                        "логін повів не на дашборд (#{response.location}) — " \
                                        "імовірно MFA-challenge; для MFA-флоу є власний спек-дім"
    end

    response
  end
end

RSpec.configure do |config|
  config.include RequestLoginHelper, type: :request
end
