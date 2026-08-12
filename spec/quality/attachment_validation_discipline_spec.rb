# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# Гейт ДЕКЛАРАЦІЇ на вкладеннях: кожне наше Active-Storage-вкладення мусить
# оголосити тип і розмір, а колекційне — ще й стелю кількості (`04_01 §5`).
#
# 🔴 Чому саме гейт, а не три правки: дефект тут — ВІДСУТНІСТЬ рядка, тож ані
# греп, ані ревʼю його не бачать (`SEC.27`). Голий `has_one_attached` виглядає
# нормально й читається як завершений код — доки хтось не покладе у сховище
# довільний блоб довільного розміру. Єдина форма, що це ловить, — перелічити
# РЕАЛЬНУ множину й вимагати декларації на кожного її члена.
#
# ⚠️ Стелі, названі тут, бо зелений колір без них читатиметься ширше, ніж є:
#   · гейт судить НАЯВНІСТЬ валідатора, ніколи його ЗМІСТ — allow-list із
#     десяти типів пройде так само, як із трьох; доречність списку лишається
#     на ревʼю;
#   · периметр — `app/models`, тобто вкладення, оголошене в гемі чи концерні
#     поза цим деревом, для гейта не існує (виміряно: фреймворк везе пʼять
#     власних — ActionText ×2, ActiveStorage ×2, ActionMailbox — і жодне з них
#     не наше, тож вони свідомо поза множиною).
RSpec.describe "Вкладення оголошують тип і розмір", type: :model do
  # 🔴 Множина береться з РАНТАЙМУ (`attachment_reflections`), не з рукописного
  # переліку: нове вкладення входить у периметр саме тим, що його оголосили.
  def our_attachments
    @our_attachments ||= begin
      Rails.application.eager_load!
      models_root = Rails.root.join("app/models").to_s

      ActiveRecord::Base.descendants.reject(&:abstract_class?).flat_map do |model|
        next [] unless model.respond_to?(:attachment_reflections)
        next [] if model.attachment_reflections.empty?
        next [] unless Object.const_source_location(model.name)&.first.to_s.start_with?(models_root)

        model.attachment_reflections.map { |name, reflection| [ model, name, reflection.macro ] }
      end
    end
  end

  def validator_kinds(model, name)
    model.validators_on(name).map { |v| v.class.name.demodulize }
  end

  it "перелічує вкладення з рантайму, а не з рукописного списку" do
    # Liveness: без цього прикладу порожня множина зробила б гейт вакуумним —
    # «нуль порушень» означало б «нуль перевірок».
    pairs = our_attachments.map { |model, name, _| "#{model.name}##{name}" }
    expect(pairs).to include("Organization#logo", "MaintenanceRecord#photos", "Codex::Node#gallery")
  end

  it "не лишає жодного вкладення без типу й розміру" do
    missing = our_attachments.filter_map do |model, name, _macro|
      kinds = validator_kinds(model, name)
      lacking = %w[ContentTypeValidator SizeValidator] - kinds
      "#{model.name}##{name} — бракує: #{lacking.join(', ')}" if lacking.any?
    end

    expect(missing).to be_empty, <<~MSG
      Вкладення без оголошеного типу/розміру приймає у сховище довільний блоб:

      #{missing.join("\n      ")}

      Лік — дзеркаль `MaintenanceRecord#photos`:
        validates :name, content_type: { in: %w[image/jpeg …] },
                         size: { less_than: N.megabytes }
      Дім → `04_01 §5`.
    MSG
  end

  it "не лишає колекційне вкладення без стелі кількості" do
    # `has_one_attached` стелі не потребує — там кількість завжди одна.
    missing = our_attachments.filter_map do |model, name, macro|
      next unless macro == :has_many_attached
      next if validator_kinds(model, name).include?("LimitValidator")

      "#{model.name}##{name}"
    end

    expect(missing).to be_empty, <<~MSG
      Колекційне вкладення без `limit:` приймає необмежену кількість файлів:

      #{missing.join("\n      ")}

      Лік: `limit: { max: N }` поруч із `content_type`/`size`. Дім → `04_01 §5`.
    MSG
  end
end
