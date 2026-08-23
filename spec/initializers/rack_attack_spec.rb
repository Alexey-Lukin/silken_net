# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Rack::Attack", type: :request do
  # Reset Rack::Attack state between examples so throttle counters and
  # Fail2Ban bans don't leak across tests.
  before do
    # Freeze time so the throttle period-window key (Time.now / period) stays
    # constant across the multi-request loops below. In a slow full-suite run the
    # 300+ requests can straddle a 5-min wall-clock boundary → the counter splits
    # across two windows → 301st request not throttled (flaky 200 instead of 429).
    # Isolated runs are fast enough to stay in one window, hence pass-in-isolation.
    freeze_time

    Rack::Attack.cache.store.clear
    Rack::Attack.reset!

    # Disable N+1 detection — these tests deliberately repeat requests to
    # exercise middleware counters, not to test ActiveRecord query patterns.
    Prosopite.pause if defined?(Prosopite)
  end

  after do
    travel_back
    Prosopite.resume if defined?(Prosopite)
  end

  # -----------------------------------------------------------------------
  # SAFELIST
  # -----------------------------------------------------------------------
  describe "safelist" do
    # 🔴 Доти цей приклад ганяв 301 запит на `/up` — шлях, ВИВЕДЕНИЙ із throttle
    # НЕЗАЛЕЖНО від IP (це доводить сусід нижче з не-safelisted адреси), тож
    # safelist у ньому не брав участі й приклад лишався зеленим навіть із
    # повністю знятим правилом.
    #
    # ⚠️ Поведінкову форму («safelisted адреса не ловить 429 там, де чужа ловить»)
    # на цьому дереві збудувати НЕ ВИЙДЕ, і причина варта запису: єдині шляхи з
    # досяжним лімітом (`/login`, `/forgot_password`) обмежуються Rails-нативним
    # `rate_limit` у самому контролері, а він Rack::Attack не бачить — тобто
    # safelist від нього не звільняє (виміряно: 429 на шостому POST з
    # `127.0.0.1`). Тому пін іде туди, де правило живе.
    it "exempts loopback from every Rack::Attack throttle" do
      loopback = Rack::Attack::Request.new(Rack::MockRequest.env_for("/login", "REMOTE_ADDR" => "127.0.0.1"))
      foreign  = Rack::Attack::Request.new(Rack::MockRequest.env_for("/login", "REMOTE_ADDR" => "1.2.3.4"))

      expect(Rack::Attack.safelists["allow-localhost"].matched_by?(loopback)).to be(true)
      expect(Rack::Attack.safelists["allow-localhost"].matched_by?(foreign)).to be(false)
    end

    # ✅ [SEC.32] ПРИСУД founder 2026-08-14: обмежувачі лишаються ДВОМА
    # незалежними політиками, і safelist свідомо НЕ поширюється на
    # контролерний ліміт.
    #
    # Підстава — різні предмети, а не забутий дріт. Rack::Attack захищає
    # EDGE від ОБСЯГУ (скани, DoS), і там «внутрішня адреса» є осмисленим
    # винятком. Контролерний `rate_limit` захищає КОНКРЕТНИЙ обліковий запис
    # від перебору пароля — а внутрішній брутфорс є таким самим брутфорсом,
    # тож loopback тут виняткам не підлягає: скомпрометований внутрішній хост
    # це рівно той сценарій, проти якого ліміт і стоїть.
    #
    # 🔴 Пін існує, щоб «уніфікувати два лімітери» не сталось МОВЧКИ: у Rails
    # `rate_limit` є `by:`-лямбда, тобто технічно спільний safelist за один
    # рядок — і саме тому рішення потребує носія, а не коментаря.
    it "лишає auth-ліміт чинним для loopback — це присуд, а не недогляд" do
      expect(Api::V1::SessionsController.new).to respond_to(:create)

      loopback = Rack::Attack::Request.new(Rack::MockRequest.env_for("/login", "REMOTE_ADDR" => "127.0.0.1"))
      expect(Rack::Attack.safelists["allow-localhost"].matched_by?(loopback)).to be(true)

      # Контролерний лімітер не консультується з edge-шаром узагалі: у ньому
      # немає жодного посилання на Rack::Attack — саме це й робить дві
      # політики незалежними.
      %w[sessions_controller passwords_controller].each do |controller|
        source = Rails.root.join("app/controllers/api/v1/#{controller}.rb").read
        expect(source).to include("rate_limit"), "#{controller}: контролерний ліміт зник"
        expect(source).not_to match(/Rack::Attack|safelist/),
          "#{controller}: зʼявилось посилання на edge-шар — межу SEC.32 знято без присуду"
      end
    end
  end

  # -----------------------------------------------------------------------
  # GLOBAL THROTTLE (300 req / 5 min per IP)
  # -----------------------------------------------------------------------
  describe "global throttle (req/ip)" do
    it "allows up to 300 requests per IP within 5 minutes" do
      300.times do
        get "/login", headers: { "REMOTE_ADDR" => "1.2.3.4" }
      end

      # 300th request should still succeed (not 429)
      expect(response.status).not_to eq(429)
    end

    it "throttles the 301st request from the same IP" do
      301.times do
        get "/login", headers: { "REMOTE_ADDR" => "1.2.3.5" }
      end

      expect(response).to have_http_status(:too_many_requests)
      body = JSON.parse(response.body)
      expect(body["error"]).to eq("Rate limit exceeded")
      expect(response.headers["Retry-After"]).to be_present
    end

    it "does not throttle requests to /assets or /up" do
      301.times do
        get "/up", headers: { "REMOTE_ADDR" => "1.2.3.6" }
      end

      expect(response.status).not_to eq(429)
    end
  end

  # -----------------------------------------------------------------------
  # TELEMETRY THROTTLE (60 req / 1 min)
  # -----------------------------------------------------------------------
  describe "telemetry throttle (telemetry/uid)" do
    # 🔴 [TEST.10] Доти тут стояла множина з двох кодів (бан і ліміт) під назвою
    # «via throttle or fail2ban» — і хедж ховав те, що названий throttle не
    # спрацьовував НІКОЛИ: неавтентифікований `/telemetry/live` віддає 401,
    # Fail2Ban банить на 15-му, а ліміт цього правила — 60. Тобто `telemetry/uid`
    # можна було зняти з ініціалізатора, і приклад лишався б зеленим (доведено
    # мутацією 2026-08-03). ⚠️ Стару форму тут переказано, а не процитовано,
    # свідомо: літерал у прозі тримає файл грепо-позитивним назавжди й отруює
    # РУЧНИЙ лічильник класу (`04_06 §B.2` #15, пастка 2 — спрацювала вже тричі).
    #
    # Лік — розчепити механізми за їхніми ВЛАСНИМИ дискримінаторами: Fail2Ban
    # рахує по IP, а цей throttle — по `X-Gateway-UID`. Розганяємо IP і тримаємо
    # UID сталим: кожна адреса набирає одну відмову (далеко до 15), а лічильник
    # правила добирає свої 60. Заразом це і є пін на сам дискримінатор — з
    # IP-ключем приклад був би недосяжний за побудовою.
    it "throttles a gateway UID at its own limit even across rotating IPs" do
      limit = Rack::Attack.throttles["telemetry/uid"].limit

      (limit + 1).times do |i|
        get "/telemetry/live", headers: {
          "REMOTE_ADDR" => "5.6.#{i / 250}.#{i % 250 + 1}",
          "HTTP_X_GATEWAY_UID" => "UID-SUSTAINED"
        }
      end

      expect(response).to have_http_status(:too_many_requests)
      expect(response.media_type).to eq("application/json")
      expect(JSON.parse(response.body)).to eq("error" => "Rate limit exceeded")
    end

    it "bans a single IP by Fail2Ban long before the telemetry limit is reached" do
      61.times do
        get "/telemetry/live", headers: { "REMOTE_ADDR" => "5.6.7.8" }
      end

      # 401 з кожного запиту годує Fail2Ban, і той банить на 15-му — тобто на
      # ОДНІЙ адресі до ліміту 60 черга не доходить. Точний код, а не множина:
      # два коди тут означали б два різні механізми, і статус їх не розрізняє.
      expect(response).to have_http_status(:forbidden)
      expect(JSON.parse(response.body)).to eq("error" => "Forbidden")
    end

    it "registers the telemetry throttle rule" do
      throttle = Rack::Attack.throttles["telemetry/uid"]
      expect(throttle).to be_present
    end

    # 🔴 Диференціал «UID-A вичерпав ліміт, UID-B ще проходить» через HTTP
    # недосяжний ЗА ПОБУДОВОЮ: неавтентифіковані запити віддають 401, той годує
    # Fail2Ban, і на одній адресі бан настає на 15-му — тобто до ліміту 60
    # черга не доходить ніколи (це прямо доводить сусідній приклад вище).
    # Тому дискримінатор пінимо там, де він живе, а не по його тіні в статусі.
    it "buckets by X-Gateway-UID when present and falls back to the IP" do
      discriminator = Rack::Attack.throttles["telemetry/uid"].block

      with_uid = Rack::Attack::Request.new(
        "PATH_INFO" => "/telemetry/live", "REMOTE_ADDR" => "5.6.7.9",
        "HTTP_X_GATEWAY_UID" => "SNET-Q-AABB0011", "rack.input" => StringIO.new
      )
      without_uid = Rack::Attack::Request.new(
        "PATH_INFO" => "/telemetry/live", "REMOTE_ADDR" => "5.6.7.9", "rack.input" => StringIO.new
      )
      off_path = Rack::Attack::Request.new(
        "PATH_INFO" => "/up", "REMOTE_ADDR" => "5.6.7.9",
        "HTTP_X_GATEWAY_UID" => "SNET-Q-AABB0011", "rack.input" => StringIO.new
      )

      expect(discriminator.call(with_uid)).to eq("SNET-Q-AABB0011")
      expect(discriminator.call(without_uid)).to eq("5.6.7.9")
      expect(discriminator.call(off_path)).to be_nil
    end
  end

  # -----------------------------------------------------------------------
  # LOGIN THROTTLE (10 req / 1 min)
  # -----------------------------------------------------------------------
  describe "login throttle (logins/ip)" do
    # 🔴 [SEC.32] На POST-шляхах `logins/ip` НЕДОСЯЖНИЙ: контролерний `rate_limit`
    # відповідає раніше (5/хв на `/login`, 3/5хв на `/forgot_password` проти 10),
    # тож будь-який приклад, що ганяє POST'и на `/login`, міряє КОНТРОЛЕР — хай
    # би як він називався. Живий шлях правила один: `PATCH /reset_password`
    # (`passwords#update`, де контролерний ліміт стоїть `only: :create`).
    # Тому тут пін на саму МЕЖУ між двома механізмами, а поведінку самого
    # throttle'а тримає приклад нижче. Заступників у критерію досяжності
    # (§configuration) ДВА, не один: Fail2Ban і контролерний ліміт.
    it "тримає контролерний ліміт /login НИЖЧЕ за поріг logins/ip" do
      6.times do
        post "/login",
          params: { email: "a@b.com", password: "wrong" },
          headers: { "REMOTE_ADDR" => "9.8.7.9" }
      end

      # 6 < 11, тож Rack::Attack тут спрацювати не може за побудовою: 429 на
      # шостому запиті доводить, що відповів КОНТРОЛЕР. Підніми той ліміт вище 10
      # (або зніми його) — приклад почервоніє, і це саме той момент, коли
      # `logins/ip` на цьому шляху стає досяжним і потребує власного приклада.
      # Форму цієї відповіді (HTML-сторінка, не JSON-блоб) пінить
      # `spec/requests/api/v1/sessions_controller_spec.rb` [SEC.25].
      expect(response).to have_http_status(:too_many_requests)
    end

    # 🔴 [SEC.29] Фінальний крок ланцюга зареєстровано як **PATCH** (`routes.rb`), а
    # правило доти читало лише `request.post?` — тобто єдиний крок, що реально
    # МІНЯЄ пароль, не лімітувався взагалі. Пін саме на дієслові: сусідній
    # `account_security`-throttle цю вісь уже знає (його список — `%w[PATCH DELETE]`),
    # тож розходження сиділо в межах одного файла.
    #
    # ⚠️ Цей приклад — не дублікат гейта `spec/security/path_literal_route_consistency`:
    # той доводить, що ШЛЯХ живий, а цей — що ПРАВИЛО на нього реагує. Перший
    # лишався зеленим на цьому дефекті, бо Rack::Attack працює до роутера.
    it "throttles password-reset PATCHes, not just POSTs" do
      11.times do
        patch "/reset_password",
          params: { token: "irrelevant", user: { password: "x" } },
          headers: { "REMOTE_ADDR" => "9.8.7.5" }
      end

      expect(response).to have_http_status(:too_many_requests)
    end
  end

  # -----------------------------------------------------------------------
  # ACCOUNT SECURITY THROTTLE (10 req / 1 min) [SEC.16]
  # -----------------------------------------------------------------------
  # 🔴 [TEST.11] Правило стерегло step-up brute-force (підбір `current_password`
  # на зміні пароля й відв'язуванні ідентичностей) БЕЗ жодного поведінкового
  # приклада — при тому, що сусідній `logins/ip` свій має. Досяжність тут не
  # припущена, а перевірена за критерієм `04_06 §B.2` #17: ліміт (10) МЕНШИЙ за
  # поріг Fail2Ban (15), а обидва механізми ключаться на ту саму IP, тож 429
  # приходить на 11-му запиті — раніше, ніж бан на 15-му. (Саме цією перевіркою
  # `m2m_auth/ip` виявився недосяжним: там ліміт 15 не менший за 15.)
  describe "account security throttle (account_security/ip)" do
    it "throttles password-change PATCHes after 10 per minute" do
      11.times do
        patch "/account_security/password",
          params: { user: { current_password: "wrong", password: "x" } },
          headers: { "REMOTE_ADDR" => "9.8.7.3" }
      end

      expect(response).to have_http_status(:too_many_requests)
    end

    # Друге дієслово списку — і воно не церемоніальне: `%w[PATCH DELETE]` живе
    # в одному рядку, тож приклад лише на PATCH лишався б зеленим, якби DELETE
    # звідти випав, — а єдина DELETE-дія цього периметра НЕЗВОРОТНА (стирання
    # акаунта), тобто саме та, де перебір `current_password` коштує найдорожче.
    it "throttles account-erasure DELETEs on the same rule" do
      11.times do
        delete "/account_security/erase",
          headers: { "REMOTE_ADDR" => "9.8.7.2" }
      end

      expect(response).to have_http_status(:too_many_requests)
    end
  end

  # -----------------------------------------------------------------------
  # M2M AUTH THROTTLE (15 req / 1 min)
  # -----------------------------------------------------------------------
  describe "m2m auth throttle (m2m_auth/ip)" do
    it "registers the m2m_auth throttle rule" do
      throttle = Rack::Attack.throttles["m2m_auth/ip"]
      expect(throttle).to be_present
    end

    # 🔴 [TEST.10] Назва доти обіцяла throttle, а хедж приймав і 403 — тобто приклад
    # не розрізняв двох механізмів і був би зелений зі знятим правилом. Тут ліміт
    # (15) НЕ менший за поріг Fail2Ban (15), а дискримінатор у обох — та сама IP,
    # тож на невдалій автентифікації названий throttle недосяжний У ПРИНЦИПІ:
    # блок-лист у Rack::Attack виконується перед throttle'ами. Приклад тепер
    # тверджує рівно те, що відбувається; сам throttle лишається осмисленим для
    # УСПІШНОЇ автентифікації (200 не годує Fail2Ban) — саме від Ed25519-DoS.
    it "bans a flood of failed m2m auth by Fail2Ban, not by the m2m throttle" do
      16.times do
        post "/api/v1/auth/m2m_token",
          params: { did: "SNET-Q-TEST0001", timestamp: Time.current.iso8601, signature: "a" * 128 },
          headers: { "REMOTE_ADDR" => "203.0.113.40" },
          as: :json
      end

      expect(response).to have_http_status(:forbidden)
      expect(JSON.parse(response.body)).to eq("error" => "Forbidden")
    end
  end

  # -----------------------------------------------------------------------
  # ORACLE CALLBACKS THROTTLE (60 req / 1 min)
  # -----------------------------------------------------------------------
  describe "oracle callbacks throttle (oracle_callbacks/ip)" do
    it "registers the oracle_callbacks throttle rule" do
      throttle = Rack::Attack.throttles["oracle_callbacks/ip"]
      expect(throttle).to be_present
    end

    # 🔴 [TEST.10] Той самий розчеп, що й для m2m: ліміт 60 проти порогу Fail2Ban 15
    # на тому самому IP-ключі — отже сканера відсікає бан, а не це правило.
    it "bans an unauthenticated callback flood by Fail2Ban, not by the oracle throttle" do
      61.times do
        post "/api/v1/oracle_callbacks",
          params: { chainlink_request_id: SecureRandom.uuid, success: true },
          headers: { "REMOTE_ADDR" => "203.0.113.50" },
          as: :json
      end

      expect(response).to have_http_status(:forbidden)
      expect(JSON.parse(response.body)).to eq("error" => "Forbidden")
    end
  end

  # -----------------------------------------------------------------------
  # FAIL2BAN
  # -----------------------------------------------------------------------
  describe "fail2ban (401/404 scanner detection)" do
    it "blocks an IP after accumulating too many 401/404 responses" do
      # Generate 15+ failures (401 from unauthenticated requests)
      16.times do
        get "/users/me", headers: { "REMOTE_ADDR" => "6.6.6.6" }
      end

      # The IP should now be banned — next request gets 403
      get "/users/me", headers: { "REMOTE_ADDR" => "6.6.6.6" }
      expect(response).to have_http_status(:forbidden)

      body = JSON.parse(response.body)
      expect(body["error"]).to eq("Forbidden")
    end
  end

  # -----------------------------------------------------------------------
  # THROTTLED RESPONSE FORMAT
  # -----------------------------------------------------------------------
  describe "throttled response" do
    it "returns JSON with error message and Retry-After header" do
      # Trigger the logins/ip throttle (limit: 10/min, POST only) — 11 requests
      # reliably exceeds the threshold without relying on the global 300-req
      # throttle period timing. Requests 1–10 reach the app (401 each; fail2ban
      # counter stays at 10 < FAIL2BAN_MAXRETRY=15). Request 11 is intercepted
      # by Rack::Attack before reaching the app and returns 429.
      11.times do
        post "/login",
          params: { email: "test@example.com", password: "wrong" },
          headers: { "REMOTE_ADDR" => "2.3.4.5" }
      end

      expect(response).to have_http_status(:too_many_requests)
      expect(response.content_type).to include("application/json")

      body = JSON.parse(response.body)
      expect(body).to eq("error" => "Rate limit exceeded")
      expect(response.headers["Retry-After"]).to be_present
      expect(response.headers["Retry-After"].to_i).to be > 0
    end
  end

  # -----------------------------------------------------------------------
  # MIDDLEWARE PRESENCE
  # -----------------------------------------------------------------------
  describe "middleware stack" do
    it "includes Rack::Attack in the middleware stack" do
      middlewares = Rails.application.middleware.map(&:name)
      expect(middlewares).to include("Rack::Attack")
    end

    it "includes RackAttackFailCounter::Middleware after Rack::Attack" do
      middlewares = Rails.application.middleware.map(&:name)
      rack_attack_idx = middlewares.index("Rack::Attack")
      fail_counter_idx = middlewares.index("RackAttackFailCounter::Middleware")

      expect(rack_attack_idx).to be_present
      expect(fail_counter_idx).to be_present
      expect(fail_counter_idx).to be > rack_attack_idx
    end
  end

  # -----------------------------------------------------------------------
  # CONFIGURATION
  # -----------------------------------------------------------------------
  describe "configuration" do
    # 🔴 [TEST.10] Правила нижче не мають поведінкового приклада на власний ліміт,
    # і причина записана прозою: на неавтентифікованому трафіку їх заступає
    # Fail2Ban, бо дискримінатор у них той самий (IP), а поріг бану нижчий. Проза
    # про МЕХАНІЗМ мусить бути фальсифіковною — інакше хтось опустить ліміт нижче
    # порогу, пояснення стане хибним, і нічого не почервоніє. Цей приклад і є та
    # фальсифіковність: щойно ліміт опускається під поріг, названий throttle стає
    # досяжним, і йому потрібен СВІЙ поведінковий приклад, а не пояснення.
    #
    # ⚠️ Критерій членства (щоб наступний throttle класифікували, а не вгадали):
    # дискримінатор = IP **І** ліміт ≥ порогу бану **І** шлях на невдалій спробі
    # віддає 401/404, тобто сам годує Fail2Ban. `logins/ip` і `account_security/ip`
    # сюди не входять (ліміт 10 < 15 — досяжні), `telemetry/uid` теж ні: він
    # ключиться на `X-Gateway-UID`, і саме тому має власний поведінковий приклад.
    #
    # 🔴 [SEC.32] Але сам цей критерій знає лише ОДНОГО заступника, а їх ДВА:
    # другий — Rails-нативний `rate_limit` У КОНТРОЛЕРІ, і він не має жодної з
    # трьох ознак вище (порогу бану немає, статус на невдалій спробі байдужий),
    # тобто критерій відсіював би його завжди. Заступає він за іншим правилом:
    # менший ліміт на тому самому шляху відповідає РАНІШЕ. У дереві таких лімітів
    # рівно два (`sessions#create` 5/хв, `passwords#create` 3/5хв — обидва в
    # auth-ланцюзі), тож із десяти інших throttle'ів жоден не зачеплений, а
    # вердикт «`logins/ip` досяжний» правдивий лише на ОДНОМУ з трьох його шляхів
    # (`PATCH /reset_password`). Класифікуючи наступний throttle, питай не лише
    # «чи годує він Fail2Ban», а «який ЩЕ механізм на цьому шляху відповість
    # раніше» — носій цієї межі стоїть у describe `logins/ip` вище.
    # 🔴 `helium_sos/ip` доданий 2026-08-03 після adversarial-проходу: він підпадає
    # під усі три умови (30 ≥ 15, IP-keyed, невдалий HMAC → 401), а список без
    # нього суперечив власній назві «every» — рівно той розрив назви й твердження,
    # який цей пункт і полює.
    let(:shadowed_by_fail2ban) { %w[m2m_auth/ip oracle_callbacks/ip helium_sos/ip] }

    it "registers all expected throttle rules" do
      # Order doesn't matter — `contain_exactly` is set-equality.
      expect(Rack::Attack.throttles.keys).to contain_exactly(
        "req/ip", "telemetry/uid", "logins/ip", "m2m_auth/ip", "oracle_callbacks/ip",
        "helium_sos/ip", "account_security/ip"
      )
    end

    it "uses MemoryStore for cache in test environment" do
      expect(Rack::Attack.cache.store).to be_a(ActiveSupport::Cache::MemoryStore)
    end


    it "keeps every Fail2Ban-shadowed throttle at or above the ban threshold" do
      shadowed_by_fail2ban.each do |name|
        limit = Rack::Attack.throttles.fetch(name).limit
        expect(limit).to be >= FAIL2BAN_MAXRETRY,
          "#{name}: ліміт #{limit} тепер нижчий за поріг Fail2Ban #{FAIL2BAN_MAXRETRY}, " \
          "отже правило СТАЛО досяжним — напиши йому поведінковий приклад на 429 " \
          "замість пояснення, чому його немає (`04_06 §B.2` #17)"
      end
    end
  end
end
