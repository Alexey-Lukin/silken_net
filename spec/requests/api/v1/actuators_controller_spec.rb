# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::ActuatorsController, type: :request do
  let(:organization) { create(:organization) }
  let(:other_organization) { create(:organization) }
  let(:user) { create(:user, :forester, organization: organization) }
  let(:api_token) { user.generate_token_for(:api_access) }
  let(:headers) { { "Authorization" => "Bearer #{api_token}" } }

  let(:own_cluster) { create(:cluster, organization: organization) }
  let(:other_cluster) { create(:cluster, organization: other_organization) }
  let(:own_gateway) { create(:gateway, :online, cluster: own_cluster) }
  let(:other_gateway) { create(:gateway, :online, cluster: other_cluster) }
  let!(:own_actuator) { create(:actuator, gateway: own_gateway) }
  let!(:other_actuator) { create(:actuator, gateway: other_gateway) }

  describe "GET /clusters/:cluster_id/actuators" do
    it "returns actuators for the user's organization cluster" do
      get "/clusters/#{own_cluster.id}/actuators", headers: headers, as: :json
      expect(response).to have_http_status(:ok)

      ids = response.parsed_body["data"].map { |a| a["id"] }
      expect(ids).to include(own_actuator.id)
    end

    it "returns 404 for a cluster from another organization" do
      get "/clusters/#{other_cluster.id}/actuators", headers: headers, as: :json
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /actuators/:id" do
    it "returns an actuator belonging to the user's organization" do
      get "/actuators/#{own_actuator.id}", headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["actuator"]["id"]).to eq(own_actuator.id)
    end

    it "returns 404 for an actuator from another organization" do
      get "/actuators/#{other_actuator.id}", headers: headers, as: :json
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /actuators/:id/execute" do
    before do
      silence_side_effects!(:actuator_dispatch)
    end

    # 🔴 [UI.14] Пін на ЖИВИЙ вхід, і саме його бракувало роками. Кожен приклад
    # нижче подає власний рукописний літерал ВЕЛИКИМИ (`OPEN_VALVE`, `STOP`) —
    # тобто сюїта ходила входом, якого UI не виробляв ЖОДНОГО разу, поки картка
    # слала `open`/`close` і кожен клік по пожежному клапану давав 500. Тут
    # вантаж береться з розмітки, яку віддає САМА сторінка, тож приклад
    # червоніє на будь-якому майбутньому розходженні UI ⟷ модель, а не лише
    # на регістрі. Компонентна спека це половину не закриває: вона рендерить
    # повз маршрутизатор (`04_06 §B.2` BP #14).
    it "accepts the whole payload the actuator page actually renders" do
      get "/actuators/#{own_actuator.id}", headers: headers
      expect(response).to have_http_status(:ok)

      # Береться ВЕСЬ query кнопки, не одне поле: саме неповнота вантажу й була
      # другою ногою дефекту (`duration_seconds` не слався зовсім, а модель
      # вимагає його `presence: true` → `create!` → 500). Пін на самий
      # `action_payload` її б не побачив.
      query = CGI.unescapeHTML(response.body[%r{/actuators/#{own_actuator.id}/execute\?([^"']+)}, 1].to_s)
      params = Rack::Utils.parse_nested_query(query)

      # Ліхтар: без нього приклад лишався б зеленим на сторінці ЗОВСІМ без кнопки.
      expect(params).to include("action_payload")

      post "/actuators/#{own_actuator.id}/execute", params: params, headers: headers

      expect(response).to have_http_status(:see_other)
      expect(own_actuator.commands.reload.last.command_payload).to eq(params["action_payload"])
    end

    it "creates and returns a command for the actuator" do
      post "/actuators/#{own_actuator.id}/execute",
           params: { action_payload: "OPEN_VALVE", duration_seconds: 30 },
           headers: headers.merge("Idempotency-Key" => SecureRandom.uuid), as: :json

      expect(response).to have_http_status(:accepted)
      expect(response.parsed_body["command_id"]).to be_present
    end

    it "returns conflict when actuator already has pending command" do
      silence_side_effects!(:actuator_dispatch)
      own_actuator.commands.create!(
        user: user,
        command_payload: "TEST",
        duration_seconds: 10,
        status: :issued
      )

      post "/actuators/#{own_actuator.id}/execute",
           params: { action_payload: "OPEN_VALVE", duration_seconds: 30 },
           headers: headers.merge("Idempotency-Key" => SecureRandom.uuid), as: :json

      expect(response).to have_http_status(:conflict)
    end

    # [SEC.25 Ф4] Той самий 409, але з браузера — і саме цей шлях буденний:
    # `button_to` в картці не дебаунситься жодним Stimulus, а звичайний клік не
    # несе `Idempotency-Key`, тож 400-гард його не перехоплює. Пін на ФОРМУ:
    # статус не змінювався, тож пін на нього лишався б зеленим і на блобі.
    it "redirects instead of blobbing JSON when the browser double-submits" do
      silence_side_effects!(:actuator_dispatch)
      own_actuator.commands.create!(
        user: user, command_payload: "TEST", duration_seconds: 10, status: :issued
      )

      post "/actuators/#{own_actuator.id}/execute",
           params: { action_payload: "OPEN_VALVE", duration_seconds: 30 },
           headers: headers.merge("Accept" => "text/html")

      expect(response).to have_http_status(:see_other)
      expect(response).to redirect_to(actuator_path(own_actuator))
      # Без цього рядка `error:` можна зняти — статус і ціль не змінились би.
      expect(flash[:error]).to be_present
      expect(response.media_type).not_to eq("application/json")
    end

    # 🔴 [SEC.25] Дзеркало приклада вище з боку УСПІХУ — саме його й бракувало.
    # Гілка відмови відповідала браузеру, а успішна оголошувала лише json і
    # turbo_stream, тож клік без JS не матчив жодного формату й давав 500 ПІСЛЯ
    # того, як наказ уже створено. Пін на форму + на КАТЕГОРІЮ: `pending`, бо
    # команда тут лише поставлена в чергу, а не виконана.
    it "відповідає редиректом, коли браузер шле звичайний text/html" do
      silence_side_effects!(:actuator_dispatch)

      expect {
        post "/actuators/#{own_actuator.id}/execute",
             params: { action_payload: "OPEN_VALVE", duration_seconds: 30 },
             headers: headers.merge("Accept" => "text/html")
      }.to change(ActuatorCommand, :count).by(1)

      expect(response).to have_http_status(:see_other)
      expect(response).to redirect_to(actuator_path(own_actuator))
      expect(response.media_type).not_to eq("application/json")
      # Категорія несуча: `success` стверджував би виконання, якого ще не було.
      expect(flash[:pending]).to be_present
      expect(flash[:success]).to be_blank
    end

    # [ARCH.58] Протермінований наказ матеріалізує свій кінець лише при
    # poll-видачі, тож на мертвому шлюзі він лежить у `.pending` вічно — і без
    # `live_pending` тримав би 409 для всіх нових наказів назавжди. Сам TTL цього
    # НЕ лікує: гард його просто не бачив.
    it "протермінований наказ більше не тримає 409" do
      cmd = own_actuator.commands.create!(
        user: user, command_payload: "OPEN_VALVE", duration_seconds: 10,
        status: :issued, expires_at: 5.minutes.from_now
      )
      cmd.update_columns(expires_at: 1.minute.ago)

      post "/actuators/#{own_actuator.id}/execute",
           params: { action_payload: "OPEN_VALVE", duration_seconds: 30 },
           headers: headers.merge("Idempotency-Key" => SecureRandom.uuid), as: :json

      expect(response).to have_http_status(:accepted)
    end

    # [ARCH.58] In-flight гард НЕ сміє блокувати аварійну зупинку: інакше
    # оператор не може подати STOP саме тоді, коли в черзі щось є — тобто в
    # єдиному сценарії, заради якого override існує. Модельний виняток
    # (`dispatch_to_edge!`) без цього лишався б недосяжним із API.
    it "override-STOP проходить попри pending-наказ у черзі" do
      own_actuator.commands.create!(
        user: user, command_payload: "OPEN_VALVE", duration_seconds: 10, status: :issued
      )

      post "/actuators/#{own_actuator.id}/execute",
           params: { action_payload: "STOP", duration_seconds: 1 },
           headers: headers.merge("Idempotency-Key" => SecureRandom.uuid), as: :json

      expect(response).to have_http_status(:accepted)
      expect(ActuatorCommand.find(response.parsed_body["command_id"]).priority).to eq("override")
    end

    it "STOP з аргументом (STOP:5) теж розпізнається як override" do
      own_actuator.commands.create!(
        user: user, command_payload: "OPEN_VALVE", duration_seconds: 10, status: :issued
      )

      post "/actuators/#{own_actuator.id}/execute",
           params: { action_payload: "STOP:5", duration_seconds: 1 },
           headers: headers.merge("Idempotency-Key" => SecureRandom.uuid), as: :json

      expect(response).to have_http_status(:accepted)
    end

    context "with idempotency key" do
      it "returns 400 when Idempotency-Key header is missing for JSON requests" do
        post "/actuators/#{own_actuator.id}/execute",
             params: { action_payload: "OPEN_VALVE", duration_seconds: 30 },
             headers: headers, as: :json

        expect(response).to have_http_status(:bad_request)
        expect(response.parsed_body["error"]).to include("Idempotency-Key")
      end

      it "returns cached response on duplicate request with same Idempotency-Key" do
        idempotency_key = SecureRandom.uuid

        post "/actuators/#{own_actuator.id}/execute",
             params: { action_payload: "OPEN_VALVE", duration_seconds: 30 },
             headers: headers.merge("Idempotency-Key" => idempotency_key), as: :json

        expect(response).to have_http_status(:accepted)
        first_command_id = response.parsed_body["command_id"]

        # Simulate rack.response_finished callbacks with the real Rack SPEC arity —
        # Puma invokes them after flush as (env, status, headers, error).
        Array(request.env["rack.response_finished"]).each { |cb| cb.call(request.env, response.status, response.headers, nil) }

        # Retry with same Idempotency-Key — should return cached response
        post "/actuators/#{own_actuator.id}/execute",
             params: { action_payload: "OPEN_VALVE", duration_seconds: 30 },
             headers: headers.merge("Idempotency-Key" => idempotency_key), as: :json

        expect(response).to have_http_status(:accepted)
        expect(response.parsed_body["command_id"]).to eq(first_command_id)
      end

      it "writes idempotency cache via rack.response_finished callback" do
        idempotency_key = SecureRandom.uuid
        cache_key = "idempotency:actuator:#{own_actuator.id}:#{Digest::SHA256.hexdigest(idempotency_key)}"

        post "/actuators/#{own_actuator.id}/execute",
             params: { action_payload: "OPEN_VALVE", duration_seconds: 30 },
             headers: headers.merge("Idempotency-Key" => idempotency_key), as: :json

        expect(response).to have_http_status(:accepted)

        # In test env, rack.response_finished callbacks are collected but not
        # automatically invoked. Execute them manually with the real Rack SPEC
        # arity (env, status, headers, error) — the exact call Puma makes.
        callbacks = request.env["rack.response_finished"]
        expect(callbacks).to be_present

        callbacks.each { |cb| cb.call(request.env, response.status, response.headers, nil) }

        cached = Rails.cache.read(cache_key)
        expect(cached).to be_present
        expect(cached[:command_id]).to eq(response.parsed_body["command_id"])
        expect(cached[:status]).to eq("accepted")
      end

      it "creates separate commands for different Idempotency-Keys" do
        post "/actuators/#{own_actuator.id}/execute",
             params: { action_payload: "OPEN_VALVE", duration_seconds: 30 },
             headers: headers.merge("Idempotency-Key" => SecureRandom.uuid), as: :json

        expect(response).to have_http_status(:accepted)
        first_id = response.parsed_body["command_id"]

        # Clear the pending command so second request doesn't get conflict
        own_actuator.commands.update_all(status: :delivered)

        post "/actuators/#{own_actuator.id}/execute",
             params: { action_payload: "CLOSE_VALVE", duration_seconds: 15 },
             headers: headers.merge("Idempotency-Key" => SecureRandom.uuid), as: :json

        expect(response).to have_http_status(:accepted)
        expect(response.parsed_body["command_id"]).not_to eq(first_id)
      end
    end
  end

  context "with format.html responses" do
    let(:html_headers) do
      { "Authorization" => "Bearer #{api_token}", "Accept" => "text/html" }
    end

    it "renders HTML for actuator index" do
      get "/clusters/#{own_cluster.id}/actuators", headers: html_headers
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("text/html")
    end

    it "renders HTML for actuator show" do
      get "/actuators/#{own_actuator.id}", headers: html_headers
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("text/html")
    end
  end

  describe "GET /actuator_commands/:id" do
    let(:own_command) do
      silence_side_effects!(:actuator_dispatch)
      own_actuator.commands.create!(
        user: user,
        command_payload: "OPEN_VALVE",
        duration_seconds: 30,
        status: :issued
      )
    end

    let(:other_command) do
      silence_side_effects!(:actuator_dispatch)
      other_actuator.commands.create!(
        user: create(:user, :forester, organization: other_organization),
        command_payload: "OPEN_VALVE",
        duration_seconds: 30,
        status: :issued
      )
    end

    it "returns the command status when the actuator belongs to the user's org" do
      get "/actuator_commands/#{own_command.id}", headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["id"]).to eq(own_command.id)
      expect(body["actuator_id"]).to eq(own_actuator.id)
      expect(body["status"]).to eq("issued")
      expect(body).to have_key("command_payload")
      expect(body).to have_key("issued_at")
    end

    it "returns 404 for a command from another organization" do
      get "/actuator_commands/#{other_command.id}", headers: headers, as: :json
      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 for an unknown command id" do
      get "/actuator_commands/9999999", headers: headers, as: :json
      expect(response).to have_http_status(:not_found)
    end

    it "requires forester role" do
      subscriber = create(:user, organization: organization, role: :subscriber)
      token = subscriber.generate_token_for(:api_access)
      get "/actuator_commands/#{own_command.id}",
          headers: { "Authorization" => "Bearer #{token}" }, as: :json
      expect(response).to have_http_status(:forbidden)
    end

    # [I18N.2 · клас 2] HTML-гілки тут не існувало взагалі — запит із
    # `Accept: text/html` (а саме такий шле `<turbo-frame src=...>`) падав у
    # `UnknownFormat`. Це друга половина контракту: броадкаст несе locale-вільну
    # заглушку, і саме цей ендпоінт віддає кожному глядачеві фрагмент ЙОГО мовою.
    describe "html branch (turbo-frame pull)" do
      # Без `src`, бо self-referencing src Turbo не зациклює, а ГАСИТЬ: пише
      # `references itself` у консоль і лишає фрейм порожнім. Симптом тихий.
      it "renders the frame WITHOUT src" do
        get "/actuator_commands/#{own_command.id}", headers: headers

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("command_status_frame_#{own_command.id}")
        expect(response.body).not_to include("src=")
      end

      it "renders the badge in the VIEWER's locale, not the producer's" do
        get "/actuator_commands/#{own_command.id}?locale=uk", headers: headers

        expect(response.body).to include("видано")
      end

      # Той самий org-scope, що й у JSON-гілці: обидві їдуть через `set_command`.
      it "keeps the tenant guard on the html branch too" do
        get "/actuator_commands/#{other_command.id}", headers: headers

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  context "with turbo_stream format" do
    before do
      silence_side_effects!(:actuator_dispatch)
    end

    # 🔴 Тут статус приймався множиною {200, 202, 406, 500} під скопійованою
    # підставою «Phlex-компонент може не дорендеритись у тестовому середовищі,
    # зате шлях виконано». Твердження, що приймає 500, не може впасти в принципі
    # — і сама підстава виявилась ХИБНОЮ: виміряно, шлях стабільно віддає 200 з
    # `text/vnd.turbo-stream.html`. Тобто це був coverage-заради-coverage.
    # ⚠️ Підстава переказана, а НЕ процитована дослівно: англійський літерал у
    # прозі і копіюється в наступний файл, і тримає його грепо-позитивним, тобто
    # засліплює рівно ту перевірку, якою цей клас себе й міряє ([TEST.10]).
    #
    # 🧱 І заразом тут пінується інваріант ОСІ target-id, яку в асинхронному
    # тракті не тримає жоден гейт (`00_07` UI.4): у синхронній відповіді обидві
    # половини пари приїжджають РАЗОМ, тож їхню згоду можна порівняти самою
    # відповіддю, без машинерії. Саме розходження цих двох рядків дало три
    # історичні баги цієї осі, і `actuator_{id}` — вижила половина третього.
    it "renders a turbo_stream whose target matches the id it actually renders" do
      post "/actuators/#{own_actuator.id}/execute",
           params: { action_payload: "OPEN_VALVE", duration_seconds: 30 },
           headers: headers.merge("Accept" => "text/vnd.turbo-stream.html")

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/vnd.turbo-stream.html")

      target = response.body[/<turbo-stream[^>]*\btarget="([^"]+)"/, 1]
      expect(target).to eq("actuator_#{own_actuator.id}")
      expect(response.body).to include(%(id="#{target}"))
    end
  end
end
