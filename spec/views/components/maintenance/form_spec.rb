# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# [UI.6] Лише блоб-стаби — маршрут-хелпер справжній (див. `photo_card_spec`).
unless Views::Shared::UI::PhotoCard.method_defined?(:_test_blob_helpers_stubbed)
  Views::Shared::UI::PhotoCard.prepend(Module.new do
    def _test_blob_helpers_stubbed = true
    def rails_blob_path(*, **) = "/rails/blobs/mock"
    def rails_representation_path(*, **) = "/rails/representations/mock"
  end)
end

RSpec.describe Maintenance::Form do
  def render_component(record:, existing_photos: [], current_user: nil)
    ApplicationController.renderer.render(
      component_class.new(record: record, existing_photos: existing_photos, current_user: current_user),
      layout: false
    )
  end

  # 🔴 [UI.3] Найбільша форма дерева — одинадцять `field_container`, і кожен
  # прокидає ARIA окремо, тож дротування доводиться тут, а не в еталоні.
  describe "per-field error indication" do
    let(:invalid_record) do
      record = MaintenanceRecord.new
      record.valid?
      record
    end
    let(:fragment) { Nokogiri::HTML5.fragment(render_component(record: invalid_record)) }

    it "позначає невалідні поля й веде кожне до ЖИВОГО вузла з причиною" do
      expect(LabelAssociation.invalid_fields(fragment)).not_to be_empty
      expect(LabelAssociation.unexplained_invalid_fields(fragment)).to be_empty
      expect(LabelAssociation.dangling_descriptions(fragment)).to be_empty
    end

    it "не лишає НЕПОЗНАЧЕНИМ жодного поля, яке модель вважає невалідним" do
      # 🔴 Дериваційна половина, без якої пін вище не падає на найправдоподібнішій
      # регресії: зняття `**aria` з ОДНОГО `field_container` лишає множину
      # позначених непорожньою. Тут звіряються дві незалежні сторони — `errors`
      # моделі ⊥ атрибути в HTML, — і промах називає поле поіменно.
      expect(LabelAssociation.unmarked_error_fields(fragment, invalid_record, "maintenance_record")).to be_empty
    end
  end

  describe "new record form" do
    let(:record) { build(:maintenance_record) }
    let(:html) { render_component(record: record) }

    # [UI.3] Асоціація мітка↔контрол — форма з `sessions/new_spec`. Найбільша
    # форма дерева: одинадцять полів ішли через `field_container`, і жодне не
    # мало `for=`. ⚠️ Чекбокс `hardware_verified` тут теж рахується — він єдиний
    # звʼязаний РУКОПИСНО, і саме такий звʼязок пін і мусить бачити: він
    # правильний сьогодні й нічим не захищений завтра.
    it "associates every label with a real form control" do
      doc = Nokogiri::HTML5.fragment(html)
      labels = doc.css("label")
      control_ids = doc.css("input, select, textarea").filter_map { |n| n["id"] }

      expect(labels.size).to be >= 11, "мало міток — пін вакуумний"
      orphans = labels.reject { |l| l["for"].present? && control_ids.include?(l["for"]) }
      expect(orphans.map { |l| l.text.strip }).to be_empty
    end

    it "renders the form action URL for new record" do
      expect(html).to include("/maintenance_records")
    end

    it "renders the form heading for new record" do
      expect(html).to include("Register Intervention Ritual")
    end

    it "renders the target type select field" do
      expect(html).to include('name="maintenance_record[maintainable_type]"')
    end

    it "renders Tree and Gateway as select options" do
      expect(html).to include("Tree")
      expect(html).to include("Gateway")
    end

    it "renders the action_type select field" do
      expect(html).to include('name="maintenance_record[action_type]"')
    end

    # 🔴 [I18N.1] У `select`ʼі обидва роди вжитку стоять в ОДНОМУ літералі: мітка
    # для ока ⊥ значення для сабміту. Доти мітка йшла `.humanize`, тобто форма, де
    # лісівник ОБИРАЄ дію, лишалась англійською в усіх локалях — третій сайт тієї
    # самої родини після `index` і `show`. Пін тримає обидві половини одразу.
    it "localizes the action_type option labels while keeping raw values" do
      uk_html = I18n.with_locale(:uk) { render_component(record: record) }

      expect(uk_html).to include('value="repair"')
      expect(uk_html).to include(">Ремонт</option>")
      expect(uk_html).not_to include(">Repair</option>")
    end

    it "renders the performed_at datetime field" do
      expect(html).to include('name="maintenance_record[performed_at]"')
    end

    it "renders the notes textarea" do
      expect(html).to include('name="maintenance_record[notes]"')
    end

    it "renders the labor_hours field in OpEx section" do
      expect(html).to include('name="maintenance_record[labor_hours]"')
    end

    it "renders the parts_cost field in OpEx section" do
      expect(html).to include('name="maintenance_record[parts_cost]"')
    end

    it "renders OpEx Financial Tracking label" do
      expect(html).to include("OpEx Financial Tracking")
    end

    it "renders the GPS coordinates section" do
      expect(html).to include("Intervention Coordinates")
    end

    it "renders latitude and longitude fields" do
      expect(html).to include('name="maintenance_record[latitude]"')
      expect(html).to include('name="maintenance_record[longitude]"')
    end

    it "renders the photo upload section" do
      expect(html).to include("Evidence Protocol")
    end

    it "renders the file upload field" do
      expect(html).to include('name="maintenance_record[photos][]"')
    end

    it "renders Commit to Matrix as submit text for new record" do
      expect(html).to include("Commit to Matrix")
    end

    it "does not render hardware verified checkbox for new record" do
      expect(html).not_to include("Hardware Verified")
    end

    it "shows PENDING when maintainable_type is not yet chosen (blank new record)" do
      blank_record = MaintenanceRecord.new
      rendered = render_component(record: blank_record)
      expect(rendered).to include("PENDING")
    end
  end

  describe "edit record form" do
    let(:record) { create(:maintenance_record) }
    let(:html) { render_component(record: record) }

    it "renders the edit heading with record ID" do
      expect(html).to include("Edit Intervention Record")
      expect(html).to include("##{record.id}")
    end

    it "renders Update Record as submit text" do
      expect(html).to include("Update Record")
    end

    it "renders hardware verified checkbox in edit mode" do
      expect(html).to include("Hardware Verified")
    end

    it "renders a cancel link back to the show page" do
      expect(html).to include("Cancel")
    end
  end

  describe "error display" do
    let(:record) do
      rec = build(:maintenance_record, notes: "")
      rec.validate
      rec
    end

    # [SEC.25] Пін на ФОРМУ, не лише на присутність тексту: доти цей блок був
    # третьою власною реалізацією зведення — без `role="alert"`, з власним ключем
    # заголовка й нижче кнопки сабміту. Тепер спільний `ErrorSummary`, тож
    # перевіряємо і те, що причина видима, і те, що вона оголошується.
    it "renders the shared error summary with the message and an alert role" do
      html = html_with_errors(record)

      expect(html).to include("Validation Failed")
      expect(html).to include("can&#39;t be blank")
      expect(html).to include('role="alert"')
    end

    def html_with_errors(rec)
      rec.errors.add(:notes, "can't be blank") if rec.errors[:notes].empty?
      render_component(record: rec)
    end
  end

  describe "edit form with existing photos" do
    let(:record) { create(:maintenance_record) }

    def render_with_photo(current_user: nil)
      photo = OpenStruct.new(
        filename: ActiveStorage::Filename.new("existing.jpg"),
        byte_size: 500_000,
        representable?: true
      )
      photo.define_singleton_method(:variant) { |_style| "variant_thumb" }

      # [TEST.12] Доти тут підмінявся САМ КОНСТРУКТОР гема — `Pagy.define_singleton_method(:new)`
      # з `**kwargs`, тоді як у 43.x `Pagy.new` не приймає аргументів узагалі. Тобто спека
      # дописувала гему API, якого той не має, і рівно тому провал міграції на `Pagy::Offset`
      # був невидимий: компонент валив 500 на кожному записі з фото, а приклад лишався зелений.
      render_component(record: record, existing_photos: [ photo ], current_user: current_user)
    end

    # 🔴 [UI.6] ПАРА, без якої фікс невидимий: доти галерея діставала `editable: true`
    # ЛІТЕРАЛОМ, тобто право на НЕЗВОРОТНЕ видалення фотодоказу ([SEC.28]) деривувалось
    # із маршруту викликача, а не з власного контракту компонента. Жоден приклад цього
    # файлу не пінив `editable` взагалі — тож заміна літерала на предикат не червонила
    # нічого, і фікс лишався б без свідка.
    # ⚠️ Пін цілить у сам ЕЛЕМЕНТ (форма на photo-шлях із `_method=delete`), а не в
    # рядок: `include("×")` чи клас кнопки проходили б через сусідні вузли (§Guard-craft #17).
    def delete_forms(html)
      Nokogiri::HTML5(html).css("form").select { |f| f["action"].to_s.match?(%r{/photos/}) }
    end

    it "hides the delete affordance when it does not know the actor (fail-closed)" do
      expect(delete_forms(render_with_photo)).to be_empty
    end

    it "shows it to the record's author" do
      expect(delete_forms(render_with_photo(current_user: record.user))).not_to be_empty
    end

    it "renders existing photo gallery in edit mode" do
      html = render_with_photo
      expect(html).to include("Edit Intervention Record")
      # Доти приклад із ЦІЄЮ назвою асертив лише заголовок форми — тобто лишався
      # зеленим і з галереєю, і без неї.
      expect(html).to include("existing.jpg")
    end

    # 🔴 Інваріант, не компонування: галерея мусить стояти ПОЗА формою запису.
    # Вкладений `<form>` (кожне фото — `button_to`) HTML5-парсер викидає, а його
    # `_method=delete` переносить у ЗОВНІШНЮ форму, де при Rack-парсингу виграє
    # ОСТАННЄ значення — і «Update» летить у `DELETE`, якого в маршрутах немає.
    # Міряємо тим самим spec-сумісним парсером, яким дефект і знайдено; звичайний
    # `include`-асерт цього класу не бачить у принципі.
    it "keeps the photo gallery outside the record form (no nested <form> hijacking _method)" do
      doc = Nokogiri::HTML5(render_with_photo)

      record_form = doc.css("form").find { |f| f["action"].to_s.match?(%r{/maintenance_records/\d+\z}) }
      expect(record_form).to be_present
      expect(record_form.css('input[name="_method"]').map { |i| i["value"] }).to eq([ "patch" ])
    end
  end
end
