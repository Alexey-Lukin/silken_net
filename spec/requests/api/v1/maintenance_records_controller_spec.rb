# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::MaintenanceRecordsController, type: :request do
  let(:organization) { create(:organization) }
  let(:other_organization) { create(:organization) }
  let(:forester) { create(:user, :forester, organization: organization) }
  let(:api_token) { forester.generate_token_for(:api_access) }
  let(:headers) { { "Authorization" => "Bearer #{api_token}" } }

  let!(:own_cluster) { create(:cluster, organization: organization) }
  let!(:other_cluster) { create(:cluster, organization: other_organization) }
  let(:own_tree) { create(:tree, cluster: own_cluster) }
  let(:other_tree) { create(:tree, cluster: other_cluster) }

  before do
    allow_any_instance_of(Tree).to receive(:broadcast_map_update)
    allow(EcosystemHealingWorker).to receive(:perform_async)
  end

  describe "GET /maintenance_records" do
    let!(:own_record) do
      MaintenanceRecord.create!(
        maintainable: own_tree,
        user: forester,
        action_type: :inspection,
        performed_at: 1.hour.ago,
        notes: "Routine inspection of the node completed successfully."
      )
    end

    let!(:other_record) do
      other_user = create(:user, :forester, organization: other_organization)
      MaintenanceRecord.create!(
        maintainable: other_tree,
        user: other_user,
        action_type: :cleaning,
        performed_at: 2.hours.ago,
        notes: "Cleaned the solar panels and sensors properly."
      )
    end

    it "returns only maintenance records from the user's organization" do
      get "/maintenance_records", headers: headers, as: :json
      expect(response).to have_http_status(:ok)

      record_ids = response.parsed_body["data"].map { |r| r["id"] }
      expect(record_ids).to include(own_record.id)
      expect(record_ids).not_to include(other_record.id)
    end

    it "includes pagination metadata" do
      get "/maintenance_records", headers: headers, as: :json
      expect(response).to have_http_status(:ok)

      expect(response.parsed_body).to have_key("pagy")
      expect(response.parsed_body["pagy"]).to include("page", "count", "pages")
      # 🔴 [TEST.12] `limit` тут несучий, а не четвертий ключ для повноти: у Pagy 43
      # `OPTIONS` містить РІВНО `[:limit]`, тож застаріле `items:` не кидає нічого —
      # воно мовчки лишає дефолтні 20 (виміряно: `items: 6` → `limit == 20`).
      # Перелік ключів через `include` цього не бачить за побудовою: він питає про
      # наявність, а підміна міняє ЗНАЧЕННЯ. Саме так три виклики контролера
      # переживали мажорний бамп гема.
      expect(response.parsed_body["pagy"]["limit"]).to eq(50)
    end

    # 🔴 Доти пін був `types.uniq == ["inspection"]` — і тримався БЕЗ фільтра:
    # єдиний свій запис і був інспекцією, а `other_record` (cleaning) прибирав
    # тенант-скоуп. Форма твердження тут ні до чого — доводить лише склад
    # фікстури, тож у неї додано СВІЙ запис, що мусить відпасти.
    it "filters by action_type" do
      own_cleaning = MaintenanceRecord.create!(
        maintainable: own_tree, user: forester, action_type: :cleaning,
        performed_at: 90.minutes.ago, notes: "Cleaned the enclosure and sensor window."
      )

      get "/maintenance_records", params: { action_type: "inspection" },
                                         headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      ids = response.parsed_body["data"].map { |r| r["id"] }
      expect(ids).to include(own_record.id)
      expect(ids).not_to include(own_cleaning.id)
    end

    it "filters by hardware_verified" do
      own_record.update!(hardware_verified: true)
      unverified = MaintenanceRecord.create!(
        maintainable: own_tree, user: forester, action_type: :inspection,
        performed_at: 30.minutes.ago, notes: "Inspection still awaiting hardware verification."
      )

      get "/maintenance_records", params: { verified: "1" },
                                         headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      ids = response.parsed_body["data"].map { |r| r["id"] }
      expect(ids).to include(own_record.id)
      expect(ids).not_to include(unverified.id)
    end

    # Пара «лишається ⊥ відпадає», і обидва записи СВОЇ: `other_record` живе в
    # чужій організації, тож його прибирає тенант-скоуп, а не фільтр — ним
    # фільтр не доведеш (`04_06 §B.2` BP 21).
    it "filters by maintainable_type and maintainable_id" do
      sibling_tree = create(:tree, cluster: own_cluster)
      sibling_record = MaintenanceRecord.create!(
        maintainable: sibling_tree, user: forester, action_type: :inspection,
        performed_at: 1.hour.ago, notes: "Inspection of the neighbouring node completed."
      )

      get "/maintenance_records",
          params: { maintainable_type: "Tree", maintainable_id: own_tree.id },
          headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      ids = response.parsed_body["data"].map { |r| r["id"] }
      expect(ids).to include(own_record.id)
      expect(ids).not_to include(sibling_record.id)
    end

    # [ARCH.92] Сюїта сліпа до зони ЗА ПОБУДОВОЮ: усі фікстури йдуть через
    # `.iso8601`, тобто ЗАВЖДИ несуть `Z`, а браузер шле рядок без суфікса.
    # 🔴 Зсуваємо зону ЗАСТОСУНКУ, не процесу — на CI процес уже UTC, тож пін на
    # ній був би зеленим там і не доводив би нічого.
    it "reads a zone-less filter bound in the APPLICATION zone" do
      # Арифметика тут несуча, бо саме вона робить пін здатним упасти.
      # Зона застосунку Tokyo = UTC+9, тож межа "10:00" означає 01:00 UTC;
      # зона ПРОЦЕСУ (UTC на CI, EEST локально) дала б 10:00 / 07:00 UTC.
      # Запис о 05:00 UTC лежить МІЖ цими прочитаннями: під зоною застосунку
      # він у діапазоні, під зоною процесу — випадає.
      record = MaintenanceRecord.create!(
        maintainable: own_tree, user: forester, action_type: :inspection,
        performed_at: Time.utc(2026, 5, 23, 5, 0, 0),
        notes: "Inspection at 05:00 UTC — between the two readings of the bound."
      )

      Time.use_zone("Asia/Tokyo") do
        get "/maintenance_records",
            params: { from: "2026-05-23T10:00:00", to: "2026-05-24T00:00:00" },
            headers: headers, as: :json

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["data"].map { |r| r["id"] }).to include(record.id)
      end
    end

    it "accepts a date-only filter bound" do
      # `Time.iso8601` кидав на `2026-05-23` → 400, тобто фільтр за ДНЕМ не працював
      # ніколи, попри те що коментар методу обіцяв протилежне.
      get "/maintenance_records",
          params: { from: 2.days.ago.strftime("%Y-%m-%d") },
          headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["data"].map { |r| r["id"] }).to include(own_record.id)
    end

    it "filters by date range (from/to)" do
      stale_record = MaintenanceRecord.create!(
        maintainable: own_tree, user: forester, action_type: :inspection,
        performed_at: 10.days.ago, notes: "Older inspection well outside the window."
      )

      get "/maintenance_records",
          params: { from: 2.days.ago.iso8601, to: Time.current.iso8601 },
          headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      ids = response.parsed_body["data"].map { |r| r["id"] }
      expect(ids).to include(own_record.id)
      expect(ids).not_to include(stale_record.id)
    end

    # =========================================================================
    # ISO8601 DATE GUARD: an unparseable date used to surface as
    # PG::InvalidDatetimeFormat (HTTP 500). Now it fails fast with 400.
    # =========================================================================
    it "rejects malformed `from` date with 400" do
      get "/maintenance_records",
          params: { from: "yesterday" }, headers: headers, as: :json
      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body["error"]).to include("yesterday")
    end

    it "rejects malformed `to` date with 400" do
      get "/maintenance_records",
          params: { to: "next-tuesday" }, headers: headers, as: :json
      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body["error"]).to include("next-tuesday")
    end
  end

  # [ARCH.91] `system_generated` звільняє запис від Evidence Protocol, тож воно
  # є ознакою ПРОВЕНАНСУ, а не полем форми: щойно воно потрапить у permit-список,
  # будь-який лісник зніме з себе вимогу фотодоказів одним ключем у payload'і.
  describe "POST /maintenance_records (Evidence Protocol не обходиться payload'ом)" do
    let(:params) do
      {
        maintenance_record: {
          maintainable_type: "Tree", maintainable_id: own_tree.id,
          action_type: "installation", performed_at: 1.hour.ago.iso8601,
          notes: "Installed new titanium anchor and LoRa sensor unit on node.",
          system_generated: true
        }
      }
    end

    it "ignores a client-supplied system_generated and still demands photos" do
      expect { post "/maintenance_records", params: params, headers: headers, as: :json }
        .not_to change(MaintenanceRecord, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["errors"].join).to include("required for 'repair' and 'installation'")
    end

    it "persists an installation record as forester-authored, never system-generated" do
      params[:maintenance_record][:action_type] = "inspection"
      post "/maintenance_records", params: params, headers: headers, as: :json

      expect(response).to have_http_status(:created).or have_http_status(:ok)
      expect(MaintenanceRecord.order(:id).last.system_generated).to be false
    end
  end

  describe "PATCH /maintenance_records/:id/verify" do
    let(:record) do
      MaintenanceRecord.create!(
        maintainable: own_tree,
        user: forester,
        action_type: :inspection,
        performed_at: 1.hour.ago,
        notes: "Checking all sensor connectors for corrosion damage."
      )
    end

    it "marks the record as hardware_verified when the unit pulsed AFTER the maintenance" do
      # [UI.7] Пульс ПІСЛЯ performed_at — єдиний канал, якого технік не контролює.
      own_tree.update!(last_seen_at: 10.minutes.ago)
      patch "/maintenance_records/#{record.id}/verify",
            headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["hardware_verified"]).to be true
      expect(record.reload.hardware_verified).to be true
    end

    # [UI.7, ⚖️ 2026-08-20] Доти verify був БЕЗУМОВНИЙ — самоатестація другим
    # кліком того самого актора, що вписує GPS руками. Пара нижче — обидві
    # половини guard-гілки; пін на НАСЛІДОК (прапорець не мутував), не лише на
    # статус, і на ТОЧНИЙ ключ `error` (контракт §25a: рядок = guard-гілка).
    it "refuses verification when the unit never pulsed after the maintenance" do
      own_tree.update!(last_seen_at: 2.hours.ago)
      patch "/maintenance_records/#{record.id}/verify",
            headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body).to have_key("error")
      expect(response.parsed_body).not_to have_key("errors")
      expect(record.reload.hardware_verified).to be false
    end

    it "refuses verification over HTML with the reason in the error flash" do
      own_tree.update!(last_seen_at: nil)
      patch "/maintenance_records/#{record.id}/verify",
            headers: headers.except("Accept").merge("Accept" => "text/html")
      expect(response).to redirect_to(maintenance_record_path(record))
      expect(flash[:error]).to eq(I18n.t("flash.maintenance.hardware_pulse_missing"))
      expect(record.reload.hardware_verified).to be false
    end

    it "returns 404 for a record outside the user's organization" do
      other_user = create(:user, :forester, organization: other_organization)
      other_record = MaintenanceRecord.create!(
        maintainable: other_tree,
        user: other_user,
        action_type: :inspection,
        performed_at: 1.hour.ago,
        notes: "External inspection outside the organization boundary."
      )

      patch "/maintenance_records/#{other_record.id}/verify",
            headers: headers, as: :json
      expect(response).to have_http_status(:not_found)
    end

    # =========================================================================
    # AUTHZ FIX: only the author OR admin+ may verify/update/edit a record.
    # Forester #2 within the same org used to slip through `authorize_forester!`.
    # =========================================================================
    it "forbids verifying another forester's record (same org)" do
      other_forester = create(:user, :forester, organization: organization)
      other_record = MaintenanceRecord.create!(
        maintainable: own_tree,
        user: other_forester,
        action_type: :inspection,
        performed_at: 1.hour.ago,
        notes: "Inspection authored by a different forester in the same org."
      )

      patch "/maintenance_records/#{other_record.id}/verify",
            headers: headers, as: :json
      expect(response).to have_http_status(:forbidden)
      expect(other_record.reload.hardware_verified).to be_falsey
    end

    # [SEC.25] Та сама відмова, але з БРАУЗЕРА. Доти `authorize_record_mutation!`
    # віддавав голий `render_forbidden` (JSON) незалежно від формату, тож форестер
    # діставав на дашборді JSON-блоб замість сторінки. Пін перевіряє САМЕ формат —
    # інакше він був би зеленим і на старій, зламаній поведінці.
    it "відмовляє в HTML-форматі сторінкою, а не JSON-блобом" do
      other_forester = create(:user, :forester, organization: organization)
      other_record = MaintenanceRecord.create!(
        maintainable: own_tree,
        user: other_forester,
        action_type: :inspection,
        performed_at: 1.hour.ago,
        notes: "Inspection authored by a different forester in the same org."
      )

      patch "/maintenance_records/#{other_record.id}/verify",
            headers: headers.merge("Accept" => "text/html")

      expect(response).to redirect_to(maintenance_records_path)
      expect(response.media_type).not_to eq("application/json")
      expect(other_record.reload.hardware_verified).to be_falsey
    end

    it "lets admins override and verify any record in their org" do
      other_forester = create(:user, :forester, organization: organization)
      other_record = MaintenanceRecord.create!(
        maintainable: own_tree,
        user: other_forester,
        action_type: :inspection,
        performed_at: 1.hour.ago,
        notes: "Routine inspection that needs admin verification override."
      )

      admin = create(:user, :admin, organization: organization)
      admin_headers = { "Authorization" => "Bearer #{admin.generate_token_for(:api_access)}" }

      # [UI.7] Admin-override минає лише гард АВТОРСТВА — пульс-звірку не минає
      # ніхто: без ефіру після обслуговування «залізне підтвердження» лишилось
      # би самоатестацією, тільки вищої ролі.
      own_tree.update!(last_seen_at: 5.minutes.ago)
      patch "/maintenance_records/#{other_record.id}/verify",
            headers: admin_headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(other_record.reload.hardware_verified).to be true
    end
  end

  describe "DELETE /maintenance_records/:maintenance_record_id/photos/:id" do
    let(:record) do
      MaintenanceRecord.create!(
        maintainable: own_tree,
        user: forester,
        action_type: :inspection,
        performed_at: 1.hour.ago,
        notes: "Routine inspection of the node completed successfully."
      )
    end

    it "purges the photo and returns ok" do
      # Attach a test photo using Active Storage test service
      record.photos.attach(
        io: StringIO.new("fake-image-data"),
        filename: "evidence.jpg",
        content_type: "image/jpeg"
      )
      photo = record.photos.first

      delete "/maintenance_records/#{record.id}/photos/#{photo.id}",
             headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["message"]).to be_present
    end

    it "returns 404 for a photo on another organization's record" do
      other_user = create(:user, :forester, organization: other_organization)
      other_record = MaintenanceRecord.create!(
        maintainable: other_tree,
        user: other_user,
        action_type: :inspection,
        performed_at: 1.hour.ago,
        notes: "Inspection in a different organizational forest sector."
      )

      delete "/maintenance_records/#{other_record.id}/photos/999",
             headers: headers, as: :json
      expect(response).to have_http_status(:not_found)
    end
  end

  # [UI.6] Єдиний приклад у дереві, що рендерить сторінку запису З ФОТО справжнім HTTP.
  # Доти галерея існувала лише в компонентних спеках, а ті `prepend`-ять модуль, який
  # ВИЗНАЧАЄ маршрут-хелпер кнопки видалення — тобто дописують застосунку метод, якого
  # в ньому немає. Через це `NoMethodError` на живому шляху лишався невидимим: спеки
  # перевіряли світ, у якому баг неможливий.
  describe "GET /maintenance_records/:id (HTML, запис із фотодоказом)" do
    let(:record) do
      MaintenanceRecord.create!(
        maintainable: own_tree,
        user: forester,
        action_type: :inspection,
        performed_at: 1.hour.ago,
        notes: "Routine inspection with photographic evidence attached."
      )
    end

    # 🔴 Пін на ПРОВОДКУ актора, і він мусить бути ПОЗИТИВНИЙ. Дефолт `current_user: nil`
    # fail-closed, тож забута проводка ховає кнопки від УСІХ — і негативний приклад
    # («чужому не видно») лишається зеленим на зламаному дроті. Компонентна спека теж
    # безсила: вона конструює компонент повз контролер, тобто проводки не бачить.
    it "проводить актора у сторінку: автор бачить свої мутаційні дії" do
      get "/maintenance_records/#{record.id}",
          headers: { "Authorization" => "Bearer #{api_token}", "Accept" => "text/html" }

      expect(response.body).to include(verify_maintenance_record_path(record))
      expect(response.body).to include(edit_maintenance_record_path(record))
    end

    # Найпідступніший сайт проводки: `editable:` тут окремий kwarg із дефолтом `false`,
    # тож без нього автор мовчки втрачав би кнопку видалення на сторінках 2+ після
    # «Load more» — fail-closed бив би саме по тому, хто має право.
    it "проводить право у Turbo-фрейм пагінації фото" do
      record.photos.attach(
        io: StringIO.new("fake-image-data"),
        filename: "evidence.jpg",
        content_type: "image/jpeg"
      )

      get "/maintenance_records/#{record.id}/photos",
          headers: { "Authorization" => "Bearer #{api_token}", "Accept" => "text/html" }

      expect(response.body).to include("/photos/")
    end

    # 🔴 Дзеркало позитивних пінів, і воно НЕ зайве — вони покривають рівно одну мутацію
    # (забутий kwarg), а не клас. Проводка НЕ ТОГО актора — `current_user: @record.user`
    # замість `current_user` — повністю відновлює вихідну вразливість і лишає обидва
    # позитивні приклади зеленими, бо ті дивляться очима автора. Так само `editable: true`
    # літералом у `photos` — рівно той літерал, який цей пакет викорінює з `show.rb`.
    # Тобто позитив стереже ДРІТ, негатив — те, що по дроту їде правильний актор.
    it "не пропонує мутаційних дій іншому форестеру тієї ж організації" do
      other_forester = create(:user, :forester, organization: organization)
      other_token = other_forester.generate_token_for(:api_access)
      record.photos.attach(
        io: StringIO.new("fake-image-data"),
        filename: "evidence.jpg",
        content_type: "image/jpeg"
      )

      get "/maintenance_records/#{record.id}",
          headers: { "Authorization" => "Bearer #{other_token}", "Accept" => "text/html" }

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include(verify_maintenance_record_path(record))
      expect(response.body).not_to include(edit_maintenance_record_path(record))
      expect(response.body).not_to include("/photos/")
    end

    it "не пропонує видалення у Turbo-фреймі пагінації іншому форестеру" do
      other_forester = create(:user, :forester, organization: organization)
      other_token = other_forester.generate_token_for(:api_access)
      record.photos.attach(
        io: StringIO.new("fake-image-data"),
        filename: "evidence.jpg",
        content_type: "image/jpeg"
      )

      get "/maintenance_records/#{record.id}/photos",
          headers: { "Authorization" => "Bearer #{other_token}", "Accept" => "text/html" }

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("/photos/")
    end

    it "рендерить галерею доказів, а не падає на маршрут-хелпері" do
      record.photos.attach(
        io: StringIO.new("fake-image-data"),
        filename: "evidence.jpg",
        content_type: "image/jpeg"
      )

      get "/maintenance_records/#{record.id}",
          headers: { "Authorization" => "Bearer #{api_token}", "Accept" => "text/html" }

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/html")
    end
  end

  context "with format.html responses" do
    let(:html_headers) do
      { "Authorization" => "Bearer #{api_token}", "Accept" => "text/html" }
    end

    let!(:record) do
      MaintenanceRecord.create!(
        maintainable: own_tree,
        user: forester,
        action_type: :inspection,
        performed_at: 1.hour.ago,
        notes: "Routine inspection for HTML format test."
      )
    end

    it "renders HTML for index" do
      get "/maintenance_records", headers: html_headers
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("text/html")
    end

    it "renders HTML for show" do
      get "/maintenance_records/#{record.id}", headers: html_headers
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("text/html")
    end

    it "renders photos pagination page" do
      get "/maintenance_records/#{record.id}/photos", headers: html_headers
      expect(response).to have_http_status(:ok)
    end

    # [TEST.10] Три приклади нижче приймали множину зі `500` під підставою, що
    # Phlex «може не дорендеритись у тесті». Вимір її спростував: сторінки
    # віддають 200/422 і повний HTML. Тому тверджувати треба те, заради чого ця
    # гілка існує ([SEC.25]) — форма доїхала, і причина відмови ВИДНА в ній.
    # ⚠️ Повідомлення валідації екрановані (`can't` → `can&#39;t`), тож рівняння
    # на сирий `full_messages` дає хибний негатив — звідси `CGI.escapeHTML`.
    it "renders the new-record form with the action_type field" do
      get "/maintenance_records/new", headers: html_headers

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/html")
      expect(response.body).to include("maintenance_record[action_type]")
      expect(response.body).not_to include("Validation Errors")
    end

    it "re-renders the form with visible reasons when create fails" do
      post "/maintenance_records",
           params: { maintenance_record: { maintainable_type: "Tree", maintainable_id: own_tree.id, action_type: nil, performed_at: nil } },
           headers: html_headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.media_type).to eq("text/html")
      expect(response.body).to include("maintenance_record[action_type]")
      expect(response.body).to include(CGI.escapeHTML("can't be blank"))
    end

    it "re-renders the form with visible reasons when update fails" do
      patch "/maintenance_records/#{record.id}",
            params: { maintenance_record: { action_type: nil } },
            headers: html_headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.media_type).to eq("text/html")
      expect(response.body).to include("maintenance_record[action_type]")
      expect(response.body).to include(CGI.escapeHTML("can't be blank"))
    end

    it "rejects creating a record against another organization's tree (IDOR)" do
      expect {
        post "/maintenance_records", headers: headers, as: :json, params: {
          maintenance_record: {
            maintainable_type: "Tree", maintainable_id: other_tree.id,
            action_type: :inspection, performed_at: Time.current
          }
        }
      }.not_to change(MaintenanceRecord, :count)
      expect(response).to have_http_status(:not_found)
    end

    # =========================================================================
    # [SEC IDOR] `maintainable_type` is client-supplied mass-assignment with no
    # inclusion validation at the strong-params layer. A polymorphic type outside
    # {Tree, Gateway} must default-deny (case/else in
    # `verify_maintainable_within_organization!`), not just wrong-org Tree/Gateway.
    # =========================================================================
    it "rejects a maintainable_type outside {Tree, Gateway} (IDOR default-deny)" do
      expect {
        post "/maintenance_records", headers: headers, as: :json, params: {
          maintenance_record: {
            maintainable_type: "User", maintainable_id: forester.id,
            action_type: :inspection, performed_at: Time.current
          }
        }
      }.not_to change(MaintenanceRecord, :count)
      expect(response).to have_http_status(:not_found)
    end

    # =========================================================================
    # [SEC IDOR] `ews_alert_id` is client-supplied mass-assignment too — a
    # forester in org A must not be able to silence org B's ews alert by
    # attaching it to a maintenance record on their OWN (org A) tree.
    # =========================================================================
    it "rejects an ews_alert_id belonging to another organization" do
      foreign_alert = create(:ews_alert, cluster: other_cluster, tree: other_tree)

      expect {
        post "/maintenance_records", headers: headers, as: :json, params: {
          maintenance_record: {
            maintainable_type: "Tree", maintainable_id: own_tree.id,
            ews_alert_id: foreign_alert.id,
            action_type: :inspection, performed_at: Time.current
          }
        }
      }.not_to change(MaintenanceRecord, :count)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /maintenance_records/:id/edit (HTML)" do
    let(:record) do
      MaintenanceRecord.create!(
        maintainable: own_tree, user: forester, action_type: :inspection,
        performed_at: 1.hour.ago,
        notes: "Routine inspection with photographic evidence attached."
      )
    end

    # [TEST.12] Єдиний приклад у дереві, що ВІДКРИВАЄ сторінку редагування. Компонентна
    # спека рендерить повз роутер і доти ще й підміняла САМ конструктор гема, тож провал
    # міграції на `Pagy::Offset` був невидимий обабіч: форма валила 500 на кожному записі
    # з фото. Пін на ВМІСТ, не на статус — 200 тут був би чесний і марний.
    it "renders the edit page of a record that HAS photos" do
      record.photos.attach(
        io: StringIO.new("fake-image-data"),
        filename: "evidence.jpg",
        content_type: "image/jpeg"
      )

      get "/maintenance_records/#{record.id}/edit", headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("evidence.jpg")
    end
  end
end
