# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::MaintenanceRecordPhotosController, type: :request do
  let(:organization) { create(:organization) }
  let(:other_organization) { create(:organization) }
  let(:forester) { create(:user, :forester, organization: organization) }
  let(:investor) { create(:user, :investor, organization: organization) }
  let(:api_token) { forester.generate_token_for(:api_access) }
  let(:investor_token) { investor.generate_token_for(:api_access) }
  let(:headers) { { "Authorization" => "Bearer #{api_token}" } }
  let(:investor_headers) { { "Authorization" => "Bearer #{investor_token}" } }

  let!(:own_cluster) { create(:cluster, organization: organization) }
  let!(:other_cluster) { create(:cluster, organization: other_organization) }

  let(:own_tree) { create(:tree, cluster: own_cluster) }
  let(:other_tree) { create(:tree, cluster: other_cluster) }

  before do
    allow_any_instance_of(Tree).to receive(:broadcast_map_update)
    allow(EcosystemHealingWorker).to receive(:perform_async)
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

    # [SEC.28] ⚖️ Присуд founder: доказ не має СТРОКУ зберігання — він має ГАРД
    # (доктрина `Wallet#guard_mrv_evidence!`). Дві половини дефекту, обидві виміряні:
    # `purge_later` запис не зберігає, тож зняте останнє фото лишало `repair` НАЗАВЖДИ
    # невалідним (валідація без `on:`), а `critical_unmaintained?` тим часом бачив той
    # самий запис і далі гасив `PF_NO_MAINTENANCE` — економічний ефект «обслуговування
    # відбулося» переживав знищення власного доказу.
    #
    # ⚠️ GREEN-половину пари СВІДОМО не дублюю: усі решта прикладів цього файлу стоять
    # на `action_type: :inspection`, тобто над-широкий гард почервонить їх сам. Тут —
    # рівно червона половина.
    context "when the record's photos ARE its evidence (repair / installation)" do
      let(:evidence_record) do
        MaintenanceRecord.create!(
          maintainable: own_tree,
          user: forester,
          action_type: :repair,
          performed_at: 1.hour.ago,
          notes: "Anchor re-seated after a storm; both frames captured on site.",
          photos: [ { io: StringIO.new("fake-image-data"), filename: "repair.jpg", content_type: "image/jpeg" } ]
        )
      end

      it "відмовляє в знищенні, лишає фото на місці й НЕ пише слід про purge" do
        photo = evidence_record.photos.first

        expect {
          delete "/maintenance_records/#{evidence_record.id}/photos/#{photo.id}",
                 headers: headers, as: :json
        }.not_to change { AuditLog.where(action: "maintenance_photo_purged").count }

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body["error"]).to be_present
        expect(evidence_record.reload.photos.count).to eq(1), "доказ мусить пережити спробу"
      end

      it "відмовляє редиректом у HTML, а не JSON-блобом" do
        photo = evidence_record.photos.first

        delete "/maintenance_records/#{evidence_record.id}/photos/#{photo.id}", headers: headers

        expect(response).to have_http_status(:see_other)
        expect(response).to redirect_to(maintenance_record_path(evidence_record))
        expect(evidence_record.reload.photos.count).to eq(1)
      end
    end

    context "when as JSON" do
      it "purges the photo and returns ok" do
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

      # 🔴 [SEC.28] Пін на ІДЕНТИЧНІСТЬ у сліді, не на факт. Підстава: після
      # `purge_later` блоба не існує, тож запис «фото видалено» дає нуль для
      # розслідування — чим саме він був, установити вже нічим. Тому ассерт
      # цілить у `checksum`/`filename`, а не в наявність рядка: слід без них
      # виглядав би написаним і не був би придатним.
      #
      # ⚠️ Ліхтар обовʼязковий: `record_audit_trail!` мовчки виходить, коли
      # актора не знайдено (WARN-skip) — тобто «нуль записів» могло б означати
      # «гілка не дійшла», а не «слід не пишеться».
      it "лишає слід, придатний для розслідування знищеного доказу" do
        record.photos.attach(
          io: StringIO.new("fake-image-data"), filename: "evidence.jpg", content_type: "image/jpeg"
        )
        photo = record.photos.first
        checksum = photo.blob.checksum

        expect {
          delete "/maintenance_records/#{record.id}/photos/#{photo.id}", headers: headers, as: :json
        }.to change { AuditLog.where(action: "maintenance_photo_purged").count }.by(1)

        trail = AuditLog.where(action: "maintenance_photo_purged").last
        expect(trail.user_id).to eq(forester.id), "слід мусить називати АКТОРА, не систему"
        expect(trail.metadata["filename"]).to eq("evidence.jpg")
        expect(trail.metadata["checksum"]).to eq(checksum)
        expect(trail.metadata["byte_size"]).to be_positive
      end

      it "returns 404 for a non-existent photo" do
        delete "/maintenance_records/#{record.id}/photos/999999",
               headers: headers, as: :json

        expect(response).to have_http_status(:not_found)
      end

      # [SEC.25 Ф4] Той самий 404 із браузера. Тригер буденний: `purge_later`
      # асинхронний, тож подвійний клік по «×» (або друга відкрита вкладка)
      # приходить на вже знятий доказ — і доти бачив сирий JSON. Пін на ФОРМУ,
      # бо статус не змінювався.
      it "redirects instead of blobbing JSON when the photo is already gone" do
        delete "/maintenance_records/#{record.id}/photos/999999",
               headers: headers.merge("Accept" => "text/html")

        expect(response).to have_http_status(:see_other)
        expect(response).to redirect_to(maintenance_record_path(record))
        # Без цього рядка `error:` можна зняти — статус і ціль не змінились би.
        expect(flash[:error]).to be_present
        expect(response.media_type).not_to eq("application/json")
      end
    end

    context "when as HTML" do
      # ⚠️ Доти тут стояло `have_http_status(:redirect)`, тобто БУДЬ-ЯКИЙ 3xx — і воно
      # лишалось зеленим при 302, на якому `fetch` перевидає DELETE на сторінку запису
      # (там лише GET). Найгірша форма симптому: фото вже знищене незворотно, а
      # користувач бачить помилку. Пінимо конкретний код. [UI.7]
      it "redirects with 303 See Other after purging the photo" do
        record.photos.attach(
          io: StringIO.new("fake-image-data"),
          filename: "evidence.jpg",
          content_type: "image/jpeg"
        )
        photo = record.photos.first

        delete "/maintenance_records/#{record.id}/photos/#{photo.id}",
               headers: headers

        expect(response).to have_http_status(:see_other)
        expect(response).to redirect_to(maintenance_record_path(record))
      end
    end

    it "returns 404 for a record from another organization" do
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

    it "returns 403 for non-forester users" do
      test_record = MaintenanceRecord.create!(
        maintainable: own_tree,
        user: forester,
        action_type: :inspection,
        performed_at: 1.hour.ago,
        notes: "Test inspection for auth check."
      )
      test_record.photos.attach(
        io: StringIO.new("fake-image-data"),
        filename: "evidence.jpg",
        content_type: "image/jpeg"
      )
      photo = test_record.photos.first

      delete "/maintenance_records/#{test_record.id}/photos/#{photo.id}",
             headers: investor_headers, as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it "returns 401 without authentication" do
      delete "/maintenance_records/#{record.id}/photos/999", as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    # [UI.6] Дзеркало `authorize_record_mutation!` із батьківського контролера, якого
    # тут бракувало: коміт `52bae82b` закрив «Forester #2 within the same org» на
    # `edit`/`update`/`verify` і не торкнувся вкладеного photos-шляху, що мутує ТОЙ
    # САМИЙ запис. Наслідок був важчий за батьківський: там посадка мʼяка (403), тут
    # дія ПРОХОДИЛА — безповоротно (`purge_later` → S3) і безслідно
    # (`MaintenanceRecord` не `Auditable`).
    #
    # 🔴 Пін на ЕНКВЬЮ, не на `photos.count`: `queue_adapter = :test`, тож
    # `ActiveStorage::PurgeJob` у сюїті не виконується — лічильник лишався б `1` і
    # при 200, тобто був би зеленим на зламаній поведінці.
    it "forbids deleting another forester's evidence photo (same org)" do
      other_forester = create(:user, :forester, organization: organization)
      other_record = MaintenanceRecord.create!(
        maintainable: own_tree,
        user: other_forester,
        action_type: :inspection,
        performed_at: 1.hour.ago,
        notes: "Inspection authored by a different forester in the same org."
      )
      other_record.photos.attach(
        io: StringIO.new("fake-image-data"),
        filename: "evidence.jpg",
        content_type: "image/jpeg"
      )
      photo = other_record.photos.first

      expect do
        delete "/maintenance_records/#{other_record.id}/photos/#{photo.id}",
               headers: headers, as: :json
      end.not_to have_enqueued_job(ActiveStorage::PurgeJob)

      expect(response).to have_http_status(:forbidden)
    end

    # 🔴 Дзеркало прикладу вище В HTML, і саме воно несуче: кнопка «×» — це `button_to`
    # з браузера, тож відмова йде HTML-шляхом. Пін на JSON лишався б зеленим, навіть якби
    # гард віддавав форестеру сирий блоб замість сторінки ([SEC.25]-клас). Перевіряємо
    # ЦІЛЬ редиректу — на запис, не на index: кнопка живе на `show`, і викидати з неї
    # того, кому просто відмовили, було б регресом.
    it "відмовляє в HTML-форматі редиректом на сам запис, а не JSON-блобом" do
      other_forester = create(:user, :forester, organization: organization)
      other_record = MaintenanceRecord.create!(
        maintainable: own_tree,
        user: other_forester,
        action_type: :inspection,
        performed_at: 1.hour.ago,
        notes: "Inspection authored by a different forester in the same org."
      )
      other_record.photos.attach(
        io: StringIO.new("fake-image-data"),
        filename: "evidence.jpg",
        content_type: "image/jpeg"
      )
      photo = other_record.photos.first

      delete "/maintenance_records/#{other_record.id}/photos/#{photo.id}",
             headers: headers.merge("Accept" => "text/html")

      expect(response).to redirect_to(maintenance_record_path(other_record))
      expect(response.media_type).not_to eq("application/json")
    end

    it "lets an admin delete any record's photo within the organization" do
      other_forester = create(:user, :forester, organization: organization)
      other_record = MaintenanceRecord.create!(
        maintainable: own_tree,
        user: other_forester,
        action_type: :inspection,
        performed_at: 1.hour.ago,
        notes: "Inspection that an administrator needs to curate afterwards."
      )
      other_record.photos.attach(
        io: StringIO.new("fake-image-data"),
        filename: "evidence.jpg",
        content_type: "image/jpeg"
      )
      photo = other_record.photos.first

      admin = create(:user, :admin, organization: organization)
      admin_headers = { "Authorization" => "Bearer #{admin.generate_token_for(:api_access)}" }

      # Файл прискіпливий у доведенні ВІДМОВИ (кожен заборонений шлях пінить
      # `not_to have_enqueued_job`) і доти мовчазний у доведенні самого ДОЗВОЛУ —
      # тобто `:ok` переживав би адміна, якому нічого не видалили.
      expect do
        delete "/maintenance_records/#{other_record.id}/photos/#{photo.id}",
               headers: admin_headers, as: :json
      end.to have_enqueued_job(ActiveStorage::PurgeJob)

      expect(response).to have_http_status(:ok)
      expect(other_record.reload.photos.count).to eq(0)
    end
  end
end
