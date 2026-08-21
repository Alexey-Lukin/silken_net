# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# [I18N.1] Гейт класу «generic-повідомлення валідації не узгоджується з іменем поля».
#
# `errors.full_messages` = «%{attribute} %{message}» — тобто ОДНЕ повідомлення
# дописується до імен полів усіх родів і чисел. Англійська до цього байдужа
# («Name can't be blank» / «Notes can't be blank»), українська — ні: доки
# `errors.messages.blank` був гемовим «не може бути пустим», форма друкувала
# «Публічна крипто-адреса не може бути **пустим**» і «Польові нотатки занадто
# **короткий**». Лік — не зміна `errors.format`, а перекриття generic-ключів
# формою, ІНВАРІАНТНОЮ до роду й числа (тире + іменникова група):
# `config/locales/errors/uk.yml`.
#
# 🔴 Чому це не покривав жоден наявний гейт: ключі мають дім у гемі `rails-i18n`,
# тож `i18n-tasks missing` бачить ідеальну парність (в наших каталогах їх не було
# взагалі), а `attribute_name_localization_spec` судить ДРУГУ половину рядка —
# наявність імені поля, ніколи його узгодження з рештою.
#
# 🔒 Стеля названа:
#   * Судиться ФОРМА (інваріантність до роду/числа), ніколи якість фрази —
#     «живе слово» лишається за нативним ревʼю (👤-нога I18N.1).
#   * Перевіряється ЛИШЕ uk. lv/lt несуть той самий дефект у своїх гемових
#     каталогах («ir jābūt aizpildītam» · «negali būti tuščias» — обидва
#     чоловічого роду), і лік там потребує носія мови, а не цього файлу.
#   * Периметр — три ОСІ узгодження, не перелік моделей: жіночий рід ⊥ множина
#     ⊥ плюралізований ключ. Модель тут інструмент, яким вісь пред'являється.
RSpec.describe "generic validation messages agree with any attribute name" do # rubocop:disable RSpec/DescribeClass
  around do |example|
    I18n.with_locale(:uk) { example.run }
  end

  # Вісь 1 — ЖІНОЧИЙ РІД. `blank` дописується до жіночого підмета; гемова форма
  # («не може бути пустим») давала чоловічий орудний і не узгоджувалась.
  it "agrees with a feminine attribute name" do
    org = Organization.new(name: nil)
    org.valid?

    expect(org.errors.full_messages).to include("Назва — потрібне значення")
    # Негативна половина: гемова форма не повернулась мовчки. Без неї приклад
    # лишається зеленим, якщо перекриття зникне, а `include` вище перестане
    # бути єдиним твердженням про рядок.
    expect(org.errors.full_messages.join(" ")).not_to include("пустим")
  end

  # Вісь 2 — МНОЖИНА. Те саме повідомлення дописується до множинного імені поля,
  # тож будь-яка дієслівна форма 3-ї особи однини («потребує», «має бути») теж
  # зламалася б — саме тому лік іменниковий, а не дієслівний.
  it "agrees with a plural attribute name" do
    record = MaintenanceRecord.new(notes: nil)
    record.valid?

    expect(record.errors.full_messages).to include("Польові нотатки — потрібне значення")
  end

  # Вісь 3 — ПЛЮРАЛІЗОВАНИЙ ключ. `too_short` у гемі — Hash (`one`/`few`/`many`/
  # `other`), тож перекриття рядком тихо зламало б вибір форми. Число НЕ пінимо
  # (воно властивість валідації, не цієї осі) — пінимо, що обрана плюральна
  # форма приїхала разом із тире.
  it "keeps plural forms while overriding a pluralized key" do
    record = MaintenanceRecord.new(notes: "закоротко")
    record.valid?

    notes_error = record.errors.full_messages.find { |m| m.start_with?("Польові нотатки") }

    expect(notes_error).to match(/\AПольові нотатки — мінімум \d+ знак/)
    expect(notes_error).not_to include("короткий")
  end

  # Вісь 4 — ЖИВІСТЬ. Приклади вище стверджують про uk; якщо локаль мовчки
  # відкотиться в базову, кожен із них упаде на іншому рядку й діагноз читався б
  # як «переклад зник», а не «локаль не та». Цей приклад називає причину прямо.
  it "is measuring the Ukrainian locale, not the base one" do
    expect(I18n.locale).to eq(:uk)
    expect(I18n.t("errors.messages.blank")).to eq("— потрібне значення")
  end
end
