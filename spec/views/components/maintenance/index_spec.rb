# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Maintenance::Index do
  def mock_pagy(count: 2, page: 1)
    pg = OpenStruct.new(
      count: count, page: page, last: 1, from: 1, to: count,
      previous: nil, next: nil, vars: { items: 50 }
    )
    pg.define_singleton_method(:series) { [ 1 ] }
    pg
  end

  def build_user(first_name: "Ivan", last_name: "Koval")
    User.new(first_name: first_name, last_name: last_name)
  end

  # [TEST.12] `display_identifier` тут мок оголошував ЯВНО, тож рядок «ціль» рендерився —
  # це слабший випадок, ніж у `show_spec`, і так його й треба читати. Реальним він стає
  # заради самого зв'язку: на `Tree` ідентифікатор ПОХІДНИЙ від `did`, тож розійтись
  # із моделлю більше нема чому.
  def build_maintainable(did: "SNET-00000042")
    Tree.new(did: did)
  end

  # 🔴 Вартість тепер ПОХІДНА: доти фікстура подавала `total_cost` числом, тобто
  # компонент форматував значення, якого модель не обчислювала. Ставку не дублюємо —
  # вхід задається годинами й запчастинами, як у справжньому записі.
  def build_record(id: 1, action_type: :inspection, performed_at: 2.hours.ago,
                   hardware_verified: false, labor_hours: nil, parts_cost: nil,
                   photos_count: 0, maintainable_type: "Tree",
                   user: nil, maintainable: nil, notes: "Routine check")
    rec_user = user || build_user
    rec_maintainable = maintainable || build_maintainable

    # photos_attachments mock
    photos_mock = double("photos_attachments", size: photos_count)

    r = MaintenanceRecord.new(
      id: id,
      action_type: action_type,
      performed_at: performed_at,
      hardware_verified: hardware_verified,
      labor_hours: labor_hours,
      parts_cost: parts_cost,
      user: rec_user,
      maintainable: rec_maintainable,
      notes: notes
    )
    r.maintainable_type = maintainable_type
    # Стаб ActiveStorage лишається — він підміняє БЛОБИ, а не наш запис (та сама межа,
    # що в `show_spec`: підмінюємо сховище файлів, не поведінку моделі).
    r.define_singleton_method(:photos_attachments) { photos_mock }
    r
  end

  def render_component(records:, pagy:)
    ApplicationController.renderer.render(
      component_class.new(records: records, pagy: pagy),
      layout: false
    )
  end

  let(:record) { build_record }
  let(:html) { render_component(records: [ record ], pagy: mock_pagy) }

  describe "header" do
    it "renders the Maintenance Records heading" do
      expect(html).to include("Maintenance Records")
    end

    it "renders the record count from pagy" do
      expect(html).to include("2 interventions")
    end

    it "renders Register Intervention link" do
      expect(html).to include("Register Intervention")
    end
  end

  describe "action type filters" do
    it "renders filter links for each action type" do
      expect(html).to include("inspection")
      expect(html).to include("repair")
      expect(html).to include("installation")
    end

    it "renders a verified-only filter" do
      expect(html).to include("Verified Only")
    end

    it "renders a clear filter link" do
      expect(html).to include("Clear")
    end
  end

  describe "table rows" do
    it "renders technician name" do
      expect(html).to include("Ivan Koval")
    end

    # 🔴 [I18N.1] Доти цей приклад пінив СИРИЙ токен — тобто вимагав неперекладеної
    # мітки в рядку. Пін мусить жити в НЕ-базовій локалі: в англійській мітка
    # («Inspection») від токена відрізняється лише регістром, тож база до дефекту
    # сліпа. Негативна половина ловить регресію назад на enum.
    it "renders the localized action label in the row, never the raw enum token" do
      uk_html = I18n.with_locale(:uk) { render_component(records: [ record ], pagy: mock_pagy) }

      expect(uk_html).to include("Огляд")
      expect(uk_html).not_to include(">inspection<")
    end

    it "renders the maintainable type" do
      expect(html).to include("Tree")
    end

    it "renders the DID of the maintainable" do
      expect(html).to include("SNET-00000042")
    end

    it "renders a timestamp for performed_at" do
      # performed_at is 2.hours.ago, formatted as dd.mm.yy // HH:MM
      expect(html).to match(/\d{2}\.\d{2}\.\d{2} \/\/ \d{2}:\d{2}/)
    end
  end

  describe "hardware verified indicator" do
    it "renders the verified checkmark for hardware_verified records" do
      verified_record = build_record(hardware_verified: true)
      html = render_component(records: [ verified_record ], pagy: mock_pagy)
      expect(html).to include("✓")
    end

    it "renders the pending indicator for unverified records" do
      html = render_component(records: [ build_record(hardware_verified: false) ], pagy: mock_pagy)
      expect(html).to include("◌")
    end
  end

  describe "photo count" do
    it "renders photo count when photos are attached" do
      record_with_photos = build_record(photos_count: 3)
      html = render_component(records: [ record_with_photos ], pagy: mock_pagy)
      expect(html).to include("📷 3")
    end

    it "renders em dash when no photos attached" do
      html = render_component(records: [ build_record(photos_count: 0) ], pagy: mock_pagy)
      expect(html).to include("—")
    end
  end

  describe "cost display" do
    it "renders cost in dollars when total_cost is positive" do
      record_with_cost = build_record(labor_hours: 2.0, parts_cost: 175.50)
      expected = (2.0 * MaintenanceRecord::LABOR_RATE_PER_HOUR) + 175.50

      html = render_component(records: [ record_with_cost ], pagy: mock_pagy)
      expect(html).to include("$#{expected.round(2)}")
    end
  end

  describe "empty state" do
    it "renders no interventions message when records are empty" do
      html = render_component(records: [], pagy: mock_pagy(count: 0))
      expect(html).to include("No interventions recorded")
    end
  end

  describe "action badge fallback" do
    # ⚠️ Досяжно ЛИШЕ стабом ридера — `action_type` справжній enum (див. `show_spec`).
    it "uses the gray fallback color for an unknown action_type" do
      rec = build_record
      allow(rec).to receive(:action_type).and_return("calibration")

      html = render_component(records: [ rec ], pagy: mock_pagy)
      expect(html).to include("text-gaia-text-subtle")
    end
  end

  describe "row with missing user, maintainable and timestamp" do
    it "renders gracefully when those fields are nil" do
      rec = build_record(performed_at: nil)
      rec.user = nil
      rec.maintainable = nil
      # 🔴 Порядок несучий: занулення поліморфної асоціації зчищає Й `maintainable_type`,
      # тож без цього рядка приклад перевіряв би вже іншу гілку — «типу немає» замість
      # реального стану «FK занулено, тип лишився». Мок цього не показував: у ньому два
      # поля були незалежні, і рядок «Tree //» виживав випадково.
      rec.maintainable_type = "Tree"
      html = render_component(records: [ rec ], pagy: mock_pagy)
      expect(html).to include("Tree //") # maintainable_type still renders
      expect(html).to include("—")        # maintainable&.display_identifier || "—"
    end
  end
end
