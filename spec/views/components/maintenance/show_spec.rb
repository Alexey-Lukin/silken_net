# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# [UI.6] Стаби МАРШРУТ-ХЕЛПЕРІВ знято — вони підміняли справжню поверхню й через це
# ховали живий дефект. Два різні випадки однієї шкоди:
#   · `edit_maintenance_record_path` — існує (`only: [… :edit …]`), тобто стаб
#     маскував РЕАЛЬНИЙ маршрут, а його коментар стверджував протилежне;
#   · `maintenance_record_photo_path` — НЕ існував, бо зайвий `as:` подвоював
#     префікс, і стаб дописував застосунку метод, якого в ньому не було: сторінка
#     запису з фото падала в 500, а компонентні спеки лишались зелені.
# Стаби ActiveStorage лишаються — вони підміняють БЛОБИ (мок-об'єкти замість файлів),
# а не наші маршрути.
unless Views::Shared::UI::PhotoCard.method_defined?(:_test_blob_helpers_stubbed)
  Views::Shared::UI::PhotoCard.prepend(Module.new do
    def _test_blob_helpers_stubbed = true
    def rails_blob_path(*, **) = "/rails/blobs/mock"
    def rails_representation_path(*, **) = "/rails/representations/mock"
  end)
end

RSpec.describe Maintenance::Show do
  def mock_pagy_photos(count: 0, page: 1)
    pg = OpenStruct.new(
      count: count, page: page, last: 1, from: 1, to: count,
      previous: nil, next: nil, vars: { items: 6 }
    )
    pg.define_singleton_method(:series) { [ 1 ] }
    pg
  end

  # [TEST.12] Реальний незбережений `User`: `role` тепер справжній enum, тож роль поза
  # набором тут неможлива. `password_digest` знято — його не читає ні компонент, ні
  # `has_secure_password` на незбереженому записі; у моці він був спадком форми, не потребою.
  def build_user(first_name: "Ivan", last_name: "Koval", role: :forester)
    User.new(first_name: first_name, last_name: last_name, role: role)
  end

  # 🔴 [TEST.12] Найтихіша форма цієї осі: фікстура несла ПРАВИЛЬНІ дані під
  # ПРАВИЛЬНИМИ іменами колонок (`did`/`uid`) — і рендер усе одно був мертвий.
  # `display_identifier` не метод, а `alias_attribute` (Tree→`did`, Gateway→`uid`),
  # тобто ланка, яка ці два імені зв'язує, існує ЛИШЕ в реальної моделі. Компонент
  # читав `maintainable&.display_identifier`, `OpenStruct` віддавав `nil`, і рядок
  # «ціль» у метаданих у КОЖНОМУ прикладі друкував прочерк. Мок виглядав максимально
  # сумлінним саме тому, що автор знав справжні колонки.
  def build_maintainable(did: "SNET-00000042", uid: "QUEEN-01", maintainable_type: "Tree")
    maintainable_type == "Gateway" ? Gateway.new(uid: uid) : Tree.new(did: did)
  end

  def build_record(id: 7, action_type: "inspection", performed_at: 1.hour.ago,
                  hardware_verified: false, labor_hours: nil, parts_cost: nil,
                  notes: "Routine check of the node connections.",
                  latitude: nil, longitude: nil, maintainable_type: "Tree",
                  maintainable: nil, user: nil, ews_alert_id: nil,
                  created_at: 2.hours.ago, updated_at: 1.hour.ago, mutable: true)
    rec_user = user || build_user
    rec_maintainable = maintainable || build_maintainable

    r = MaintenanceRecord.new(
      id: id,
      action_type: action_type,
      performed_at: performed_at,
      hardware_verified: hardware_verified,
      labor_hours: labor_hours,
      parts_cost: parts_cost,
      notes: notes,
      latitude: latitude,
      longitude: longitude,
      maintainable: rec_maintainable,
      user: rec_user,
      ews_alert_id: ews_alert_id,
      created_at: created_at,
      updated_at: updated_at
    )
    # Поліморфний тип тепер ПОХІДНИЙ від об'єкта, і саме тому ставиться після нього:
    # мок тримав два незалежні поля, тож був представний світ `type: "Gateway"` з
    # Tree-подібним об'єктом, якого БД не допускає. Явне присвоєння лишається рівно
    # для оберненого — реального стану «FK занулено, тип лишився».
    r.maintainable_type = maintainable_type
    # [UI.6] Предикат — ВХІД компонентної спеки, а не її копія формули. Три шари пінять
    # різне й не заміняють одне одного: формулу «автор-або-admin» — `spec/models`,
    # послух компонента предикату — тут, а те, що актор реально доїжджає з контролера, —
    # request-спека. Дублювати тут формулу означало б, що компонент і спека розійдуться
    # з моделлю разом і тихо.
    r.define_singleton_method(:mutable_by?) { |_actor| mutable }
    r
  end

  def render_component(record:, photos:, pagy_photos:, current_user: build_user)
    ApplicationController.renderer.render(
      component_class.new(
        record: record, photos: photos, pagy_photos: pagy_photos, current_user: current_user
      ),
      layout: false
    )
  end

  let(:record) { build_record }
  let(:html) { render_component(record: record, photos: [], pagy_photos: mock_pagy_photos) }

  describe "header" do
    it "renders the record id" do
      expect(html).to include("Record // #7")
    end

    # [I18N.1] Не-базова локаль: в англійській мітка «Inspection» відрізняється від
    # токена лише регістром, тож пін не розрізняв би їх на регресії.
    it "renders the action type badge as a human label" do
      expect(I18n.with_locale(:uk) { render_component(record: record, photos: [], pagy_photos: mock_pagy_photos) })
        .to include("ОГЛЯД")
    end

    it "renders the hardware badge as Pending Verify when not verified" do
      expect(html).to include("Pending Verify")
    end

    it "renders the hardware badge as HW Verified when hardware_verified" do
      verified_record = build_record(hardware_verified: true)
      html = render_component(record: verified_record, photos: [], pagy_photos: mock_pagy_photos)
      expect(html).to include("HW Verified")
    end

    it "shows verify button when hardware_verified is false" do
      expect(html).to include("Verify Hardware")
    end

    it "does not show verify button when already verified" do
      verified_record = build_record(hardware_verified: true)
      html = render_component(record: verified_record, photos: [], pagy_photos: mock_pagy_photos)
      expect(html).not_to include("Verify Hardware →")
    end
  end

  describe "evidence gallery" do
    it "renders Evidence Protocol heading" do
      expect(html).to include("Evidence Protocol")
    end

    it "renders No Photos Attached placeholder when no photos" do
      expect(html).to include("No Photos Attached")
    end
  end

  describe "notes panel" do
    it "renders Field Notes heading" do
      expect(html).to include("Field Notes")
    end

    it "renders the notes content" do
      expect(html).to include("Routine check of the node connections.")
    end

    it "applies whitespace-pre-wrap for multi-line notes" do
      expect(html).to include("whitespace-pre-wrap")
    end
  end

  describe "cost breakdown" do
    it "renders OpEx Breakdown heading" do
      expect(html).to include("OpEx Breakdown")
    end

    it "renders Labor card" do
      expect(html).to include("Labor")
    end

    it "renders Parts card" do
      expect(html).to include("Parts")
    end

    it "renders Total Cost card" do
      expect(html).to include("Total Cost")
    end

    # 🔴 [TEST.12] Доти фікстура САМА обчислювала `total_cost` синглтоном
    # `(labor_hours * 50) + parts_cost` — тобто спека пінила результат власної
    # арифметики, а не модельної, і робила це зашитою ставкою проти
    # `ENV.fetch("PATROL_LABOR_RATE", 50)`. Іронія в тому, що правило вже стояло
    # в цьому файлі — коментар про `mutable_by?` рядком нижче забороняє рівно це;
    # анотація стереже лише те, до чого дотягується.
    #
    # Ставка тепер береться з КОНСТАНТИ (один дім), а не з літерала: інакше пін
    # ламався б у середовищі, де `PATROL_LABOR_RATE` виставлено. Саму формулу
    # тримає `spec/models` — тут лише те, що компонент друкує СУМУ, а не доданок.
    it "prints the record's own total, not one of its components" do
      record_with_cost = build_record(labor_hours: 2.5, parts_cost: 100.0)
      expected = (2.5 * MaintenanceRecord::LABOR_RATE_PER_HOUR) + 100.0

      html = render_component(record: record_with_cost, photos: [], pagy_photos: mock_pagy_photos)
      expect(html).to include("$#{expected.round(2)}")
    end
  end

  describe "target metadata" do
    # 🔴 Пін, який доти НЕ МІГ спрацювати: `display_identifier` — аліас реальної
    # моделі, тож на моці рядок «ціль» друкував прочерк у КОЖНОМУ прикладі, і
    # жоден із них цього не бачив. Обидва боки несучі: без `not_to` приклад
    # лишається зеленим і тоді, коли ідентифікатор поруч із прочерком.
    it "renders the maintainable's identifier, not the em-dash fallback" do
      expect(html).to include("Tree // SNET-00000042")
      expect(html).not_to include("Tree // —")
    end

    it "renders the gateway identifier when the maintainable is a Gateway" do
      rec = build_record(maintainable_type: "Gateway", maintainable: build_maintainable(maintainable_type: "Gateway"))
      out = render_component(record: rec, photos: [], pagy_photos: mock_pagy_photos)

      expect(out).to include("Gateway // QUEEN-01")
    end
  end

  describe "GPS drift section" do
    context "when GPS coordinates are present for a Tree maintainable" do
      let(:tree_with_coords) do
        t = build_maintainable
        t.define_singleton_method(:latitude) { 49.4285 }
        t.define_singleton_method(:longitude) { 32.0620 }
        t
      end

      it "renders coordinates" do
        record_with_gps = build_record(latitude: 49.4286, longitude: 32.0621,
                                      maintainable: tree_with_coords)
        html = render_component(record: record_with_gps, photos: [], pagy_photos: mock_pagy_photos)
        expect(html).to include("49.4286")
      end
    end

    context "when GPS is not present" do
      it "renders No GPS recorded message" do
        expect(html).to include("No GPS recorded")
      end
    end
  end

  describe "hardware verification panel" do
    it "renders Hardware State heading" do
      expect(html).to include("Hardware State")
    end

    it "shows STM32 Verified as PENDING when unverified" do
      expect(html).to include("PENDING")
    end

    it "shows STM32 Verified as YES when hardware_verified" do
      verified_record = build_record(hardware_verified: true)
      html = render_component(record: verified_record, photos: [], pagy_photos: mock_pagy_photos)
      expect(html).to include("YES")
    end
  end

  describe "evidence gallery with photos" do
    it "renders PhotoGallery when photos are present" do
      photo = OpenStruct.new(
        filename: ActiveStorage::Filename.new("evidence.jpg"),
        byte_size: 1_024_000,
        representable?: true
      )
      photo.define_singleton_method(:variant) { |_style| "variant_thumb" }
      pagy = mock_pagy_photos(count: 1)
      html = render_component(record: record, photos: [ photo ], pagy_photos: pagy)
      expect(html).to include("Evidence Protocol")
      expect(html).not_to include("No Photos Attached")
    end
  end

  describe "no photos placeholder with trust protocol warning" do
    it "shows trust protocol warning for repair action_type" do
      repair_record = build_record(action_type: "repair")
      html = render_component(record: repair_record, photos: [], pagy_photos: mock_pagy_photos)
      expect(html).to include("Trust Protocol requires photos for Repair")
    end

    it "shows trust protocol warning for installation action_type" do
      install_record = build_record(action_type: "installation")
      html = render_component(record: install_record, photos: [], pagy_photos: mock_pagy_photos)
      expect(html).to include("Trust Protocol requires photos for Installation")
    end

    it "does not show trust protocol warning for inspection" do
      expect(html).not_to include("Trust Protocol requires photos")
    end
  end

  describe "metadata panel with ews_alert_id" do
    it "renders EWS Alert reference when ews_alert_id present" do
      record_with_ews = build_record(ews_alert_id: 99)
      html = render_component(record: record_with_ews, photos: [], pagy_photos: mock_pagy_photos)
      expect(html).to include("EWS Alert")
      expect(html).to include("#99")
    end
  end

  describe "GPS drift colors" do
    let(:tree_with_coords) do
      t = build_maintainable
      t.define_singleton_method(:latitude) { 49.4285 }
      t.define_singleton_method(:longitude) { 32.0620 }
      t
    end

    before do
      allow(SilkenNet::GeoUtils).to receive(:haversine_distance_m).and_return(drift)
    end

    context "when drift is between 50 and 500 meters" do
      let(:drift) { 200.0 }

      it "renders warning color for moderate drift" do
        record_with_gps = build_record(latitude: 49.43, longitude: 32.07, maintainable: tree_with_coords)
        html = render_component(record: record_with_gps, photos: [], pagy_photos: mock_pagy_photos)
        expect(html).to include("text-status-warning-accent")
      end
    end

    context "when drift is over 500 meters" do
      let(:drift) { 800.0 }

      it "renders danger color for large drift" do
        record_with_gps = build_record(latitude: 49.50, longitude: 32.20, maintainable: tree_with_coords)
        html = render_component(record: record_with_gps, photos: [], pagy_photos: mock_pagy_photos)
        expect(html).to include("text-status-danger-accent")
      end
    end
  end

  describe "GPS drift — close range (< 50 m)" do
    let(:tree_with_coords) do
      t = build_maintainable
      t.define_singleton_method(:latitude) { 49.4285 }
      t.define_singleton_method(:longitude) { 32.0620 }
      t
    end

    it "renders the close-range drift value (emerald branch)" do
      allow(SilkenNet::GeoUtils).to receive(:haversine_distance_m).and_return(30.0)
      rec = build_record(latitude: 49.4285, longitude: 32.0620, maintainable: tree_with_coords)
      html = render_component(record: rec, photos: [], pagy_photos: mock_pagy_photos)
      expect(html).to include("30 m")
    end
  end

  describe "GPS drift-check guards" do
    it "skips the drift calc when the maintainable is not a Tree" do
      allow(SilkenNet::GeoUtils).to receive(:haversine_distance_m)
      gw = build_maintainable
      gw.define_singleton_method(:latitude) { 49.0 }
      gw.define_singleton_method(:longitude) { 32.0 }
      rec = build_record(latitude: 49.0, longitude: 32.0, maintainable_type: "Gateway", maintainable: gw)
      render_component(record: rec, photos: [], pagy_photos: mock_pagy_photos)

      expect(SilkenNet::GeoUtils).not_to have_received(:haversine_distance_m)
    end

    it "skips the drift calc when the Tree has no coordinates" do
      allow(SilkenNet::GeoUtils).to receive(:haversine_distance_m)
      bare = build_maintainable # реальний Tree: latitude/longitude порожні самі, без підпірки
      rec = build_record(latitude: 49.0, longitude: 32.0, maintainable_type: "Tree", maintainable: bare)
      render_component(record: rec, photos: [], pagy_photos: mock_pagy_photos)

      expect(SilkenNet::GeoUtils).not_to have_received(:haversine_distance_m)
    end

    it "skips the drift calc when the maintainable Tree record itself is gone (nullified FK)" do
      allow(SilkenNet::GeoUtils).to receive(:haversine_distance_m)
      rec = build_record(latitude: 49.0, longitude: 32.0, maintainable_type: "Tree")
      rec.maintainable = nil
      # 🔴 Без цього рядка приклад тихо міняє гілку: занулення поліморфної асоціації
      # зчищає й `maintainable_type`, тож гард виходив би на «тип не Tree», а не на
      # «Tree є, запису немає» — тобто ім'я прикладу лишалось би, а предмет зникав.
      rec.maintainable_type = "Tree"
      render_component(record: rec, photos: [], pagy_photos: mock_pagy_photos)

      expect(SilkenNet::GeoUtils).not_to have_received(:haversine_distance_m)
    end
  end

  describe "action badge fallback" do
    # ⚠️ Вхід досяжний ЛИШЕ стабом ридера: `action_type` — справжній enum, тож
    # `MaintenanceRecord.new(action_type: "calibration")` кидає `ArgumentError` просто
    # в конструкторі. Доти цю гілку «перевіряло» значення, якого в проді не буває —
    # фолбек лишається носієм, але тепер видно, що дійти до нього даними неможливо.
    it "uses the gray default color for an unknown action_type" do
      rec = build_record
      allow(rec).to receive(:action_type).and_return("calibration")
      html = render_component(record: rec, photos: [], pagy_photos: mock_pagy_photos)
      expect(html).to include("border-gaia-border text-gaia-text-muted")
    end

    # 🔴 [I18N.1] ПОЗИТИВНА половина, якої не існувало — і без неї фолбек-пін вище
    # проходив вакуумно: він однаково зелений, коли сіріє ЛИШЕ невідомий тип і коли
    # сіріє КОЖЕН. Саме друге й сталося, щойно рядок виклику перевели на локалізовану
    # мітку: мапа кольорів ключується СИРИМ токеном, тож «Ремонт» у неї не влучає
    # ніколи (мутація: подати `action_type_label` замість `action_type` → RED тут).
    it "carries the family colour for a known action_type (not the gray fallback)" do
      html = render_component(record: build_record(action_type: "repair"), photos: [], pagy_photos: mock_pagy_photos)

      # [UI.1] Родина repair = -accent-контур (шоста порція: -text поза пастеллю
      # = токен поза роллю, а пастельна рамка на світлій поверхні невидима).
      expect(html).to include("border-status-warning-accent text-status-warning-accent")
      expect(html).not_to include("border-gaia-border text-gaia-text-muted")
    end

    # `biomass_extraction` — найнаслідковіший тип (тягне EcosystemHealingWorker →
    # declare_deceased! → слешинг), і саме його в мапі не було: він малювався як
    # невалідне значення. Колір ВЛАСНИЙ, не спільний із `decommissioning`: то дія
    # над ЗАЛІЗОМ, а це над ДЕРЕВОМ, і злиття двох станів в один вигляд — дефект.
    it "gives biomass_extraction its own colour, distinct from decommissioning" do
      biomass = render_component(record: build_record(action_type: "biomass_extraction"), photos: [], pagy_photos: mock_pagy_photos)
      decom   = render_component(record: build_record(action_type: "decommissioning"), photos: [], pagy_photos: mock_pagy_photos)

      expect(biomass).not_to include("border-gaia-border text-gaia-text-muted")
      expect(biomass).to include("text-status-danger-accent")
      expect(decom).not_to include("text-status-danger-accent")
    end
  end

  describe "nil-safe rendering of optional fields" do
    it "renders the metadata panel when user, maintainable, performed_at and timestamps are nil" do
      rec = build_record(
        performed_at: nil, user: nil, maintainable: nil,
        created_at: nil, updated_at: nil
      )
      # Override the let(:user) fallback inside build_record by giving an explicit nil sentinel.
      rec.user = nil
      rec.maintainable = nil

      out = render_component(record: rec, photos: [], pagy_photos: mock_pagy_photos)
      expect(out).to include("Record // #7")
      expect(out).to include("—") # display_identifier fallback for nil maintainable
    end

    it "renders the EWS alert metadata row when ews_alert_id is present" do
      rec = build_record(ews_alert_id: 99)
      out = render_component(record: rec, photos: [], pagy_photos: mock_pagy_photos)
      expect(out).to include("#99")
    end
  end

  describe "GPS drift check" do
    it "skips the drift comparison when the maintainable Tree has no coordinates" do
      # ⚠️ Доти тут стояв інлайн-`OpenStruct`, якому автор ВРУЧНУ дописував
      # `display_identifier` — тобто відсутність аліаса вже була помічена й залатана
      # рівно в одному місці, а фабрика лишалась дірявою. Латка на екземплярі стереже
      # тільки той екземпляр; на реальному записі `latitude`/`longitude` порожні самі.
      tree = Tree.new(did: "SNET-NOCOORD")
      rec = build_record(
        latitude: 49.0, longitude: 32.0,
        maintainable_type: "Tree", maintainable: tree
      )

      out = render_component(record: rec, photos: [], pagy_photos: mock_pagy_photos)
      # The drift row should be absent (no "drift" copy rendered).
      expect(out).not_to match(/drift_m|drift\s*[:=]/i)
    end
  end

  # [UI.6] Гейтовані дії: сторінку бачить будь-який форестер організації, а мутації
  # стоять за `authorize_record_mutation!` — тобто гард ГЛИБШЕ за дію, якою сторінка
  # відкривається. Тут пінимо, що компонент СЛУХАЄТЬСЯ предиката; що предикат каже
  # правду — `spec/models`, що актор доїжджає з контролера — request-спека.
  # [E.20] «Атестатор ≠ бенефіціар». 🔴 Напрямок гарда тут ПРОТИЛЕЖНИЙ до сусіднього
  # `mutable_by?`: той пускає автора, а тут автор — саме той, кого треба відсікти.
  # ⚠️ Обидва актори несуть ЯВНІ id: `build_user` віддає `User.new` без id, тож на
  # дефолтній фікстурі `nil != nil` хибне — і всі піни нижче були б зелені на
  # порожній множині, ніколи не відрендеривши кнопки.
  describe "атестація [E.20]" do
    def render_as(actor, rec)
      render_component(record: rec, photos: [], pagy_photos: mock_pagy_photos, current_user: actor)
    end

    let(:author)  { build_user.tap { |u| u.id = 11 } }
    let(:auditor) { build_user(first_name: "Olena", last_name: "Sydor").tap { |u| u.id = 22 } }
    let(:unattested) { build_record(user: author) }

    it "пропонує дію другій парі очей" do
      expect(render_as(auditor, unattested)).to include(attest_path)
    end

    it "ховає дію від АВТОРА запису — самозвіт і є предметом присуду" do
      out = render_as(author, unattested)

      # Рядок стану відрендерився → «немає кнопки» не вакуумне.
      expect(out).to include(I18n.t("maintenance.show.metadata.not_attested"))
      expect(out).not_to include(attest_path)
    end

    it "називає ВІДСУТНІСТЬ засвідчення, а не малює прочерк" do
      expect(render_as(auditor, unattested)).to include(I18n.t("maintenance.show.metadata.not_attested"))
    end

    it "показує атестатора й прибирає дію, коли запис уже засвідчено" do
      attested = build_record(user: author)
      attested.attestor = auditor
      attested.attested_at = Time.zone.local(2026, 8, 24, 12, 0, 0)

      out = render_as(auditor, attested)

      expect(out).to include("Olena")
      expect(out).not_to include(attest_path)
    end
  end

  describe "мутаційні дії за предикатом запису" do
    it "показує verify/edit/attach тому, кому запис підвладний" do
      out = render_component(record: build_record(mutable: true), photos: [], pagy_photos: mock_pagy_photos)

      expect(out).to include(verify_path, edit_path)
    end

    it "ховає їх від глядача, якому запис не підвладний" do
      out = render_component(record: build_record(mutable: false), photos: [], pagy_photos: mock_pagy_photos)

      expect(out).not_to include(verify_path)
      expect(out).not_to include(edit_path)
    end

    # 🔴 `editable:` галереї — не оформлення: воно вмикає кнопку видалення фотодоказу,
    # дію за тим самим гардом. Доти стояло літеральне `true`, тож «×» бачив і МІГ
    # натиснути кожен форестер організації — а видалення незворотне ([SEC.28]).
    #
    # ⚠️ Фото тут СПРАВЖНЄ (не лише `pagy.count`): із порожнім `photos:` галерея не має
    # по чому ітерувати, жодної `PhotoCard` не виникає — і `not_to include` стає істинним
    # при будь-якому `editable`. Перша редакція цього приклада була саме такою й пережила
    # мутацію фільтра зеленою; тобто пін вимірював не те, чого стосувалась його назва.
    it "не пропонує видалення фотодоказу тому, кому запис не підвладний" do
      out = render_component(
        record: build_record(mutable: false), photos: [ mock_photo ],
        pagy_photos: mock_pagy_photos(count: 1)
      )

      expect(out).not_to include("/photos/")
    end

    it "пропонує видалення фотодоказу тому, кому запис підвладний" do
      out = render_component(
        record: build_record(mutable: true), photos: [ mock_photo ],
        pagy_photos: mock_pagy_photos(count: 1)
      )

      expect(out).to include("/photos/")
    end
  end

  def mock_photo
    photo = OpenStruct.new(
      id: 99,
      filename: ActiveStorage::Filename.new("evidence.jpg"),
      byte_size: 1_024_000,
      representable?: true
    )
    photo.define_singleton_method(:variant) { |_style| "variant_thumb" }
    photo
  end

  def verify_path = "/maintenance_records/7/verify"
  def edit_path   = "/maintenance_records/7/edit"
  def attest_path = "/maintenance_records/7/attest"
end
