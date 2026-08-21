# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# [I18N.1] Гейт класу «generic-повідомлення валідації не узгоджується з іменем поля».
#
# `errors.full_messages` = «%{attribute} %{message}» — тобто ОДНЕ повідомлення
# дописується до імен полів усіх родів і чисел. Англійська до цього байдужа
# («Name can't be blank» / «Notes can't be blank»), флективні мови — ні: доки
# `errors.messages.blank` був гемовим, форма друкувала «Публічна крипто-адреса
# не може бути **пустим**» і «Польові нотатки занадто **короткий**». Лік — не
# зміна `errors.format`, а перекриття generic-ключів формою, ІНВАРІАНТНОЮ до
# роду й числа (тире + іменникова група): `config/locales/errors/{uk,lv,lt}.yml`.
#
# 🔴 Чому це не покривав жоден наявний гейт: ключі мають дім у гемі `rails-i18n`,
# тож `i18n-tasks missing` бачить ідеальну парність (в наших каталогах їх не було
# взагалі), а `attribute_name_localization_spec` судить ДРУГУ половину рядка —
# наявність імені поля, ніколи його узгодження з рештою.
#
# 🔴 Чому негативні половини нижче НЕ вакуумні: гемова форма кожної мови була
# виміряна рантаймом ПЕРЕД перекриттям, тобто предмет `not_to include` доказово
# міг бути присутнім (`blank`: uk «не може бути пустим» · lv «ir jābūt
# aizpildītam» · lt «negali būti tuščias» — усі три чоловічого роду). Негативний
# пін без такого базлайну однаково зелений на чистому світі й на зламаному
# приладі, тож саме вимір ДО правки робить його твердженням.
#
# 🔒 Стеля названа:
#   * Судиться ФОРМА (інваріантність до роду/числа), ніколи якість фрази —
#     «живе слово» лишається за нативним ревʼю (👤-нога I18N.1).
#   * Периметр — три ОСІ узгодження, не перелік моделей: жіночий рід ⊥ множина
#     ⊥ плюралізований ключ. Модель тут інструмент, яким вісь пред'являється.
#   * `en` свідомо НЕ перекривається: англійська до роду байдужа, тож перекриття
#     було б другим домом чужого значення без жодної осі, яку воно лікує.
RSpec.describe "generic validation messages agree with any attribute name" do # rubocop:disable RSpec/DescribeClass
  # Кожен рядок — одна флективна локаль. `gem_blank`/`gem_short` = ФРАГМЕНТ
  # гемової форми, яку перекриття мусить витіснити; він і є базлайном
  # негативної половини.
  {
    uk: {
      feminine: "Назва — потрібне значення",
      plural: "Польові нотатки — потрібне значення",
      short: /\AПольові нотатки — мінімум \d+ знак/,
      blank: "— потрібне значення",
      gem_blank: "пустим",
      gem_short: "короткий"
    },
    lv: {
      feminine: "Nosaukums — nepieciešama vērtība",
      plural: "Lauka piezīmes — nepieciešama vērtība",
      short: /\ALauka piezīmes — minimums \d+ zīme/,
      blank: "— nepieciešama vērtība",
      gem_blank: "aizpildītam",
      gem_short: "par īsu"
    },
    lt: {
      feminine: "Pavadinimas — reikalinga reikšmė",
      plural: "Lauko pastabos — reikalinga reikšmė",
      short: /\ALauko pastabos — mažiausiai \d+ ženkl/,
      blank: "— reikalinga reikšmė",
      gem_blank: "tuščias",
      gem_short: "per trumpas"
    }
  }.each do |locale, expected|
    context "with the #{locale} locale" do
      around do |example|
        I18n.with_locale(locale) { example.run }
      end

      # Вісь 1 — ЖІНОЧИЙ РІД (uk «Назва») / чоловічий однини (lv/lt). Гемова
      # форма несла чоловічий рід і не узгоджувалась із жіночим підметом.
      it "agrees with a singular attribute name" do
        org = Organization.new(name: nil)
        org.valid?

        expect(org.errors.full_messages).to include(expected[:feminine])
        expect(org.errors.full_messages.join(" ")).not_to include(expected[:gem_blank])
      end

      # Вісь 2 — МНОЖИНА. Те саме повідомлення дописується до множинного імені
      # поля (lv `Lauka piezīmes` і lt `Lauko pastabos` — ще й жіночого роду),
      # тож будь-яка форма, що узгоджується з підметом, тут ламається. Саме тому
      # лік іменниковий, а не дієслівний/дієприкметниковий.
      it "agrees with a plural attribute name" do
        record = MaintenanceRecord.new(notes: nil)
        record.valid?

        expect(record.errors.full_messages).to include(expected[:plural])
      end

      # Вісь 3 — ПЛЮРАЛІЗОВАНИЙ ключ. `too_short` у гемі — Hash, і набір категорій
      # РІЗНИЙ за мовами (uk one/few/many/other · lv one/other · lt one/few/other),
      # тож перекриття рядком тихо зламало б вибір форми. Число НЕ пінимо (воно
      # властивість валідації) — пінимо, що обрана плюральна форма приїхала разом
      # із тире.
      it "keeps plural forms while overriding a pluralized key" do
        record = MaintenanceRecord.new(notes: "закоротко")
        record.valid?

        notes_error = record.errors.full_messages.find { |m| m.match?(expected[:short]) }

        expect(notes_error).to match(expected[:short])
        expect(record.errors.full_messages.join(" ")).not_to include(expected[:gem_short])
      end

      # Вісь 4 — ЖИВІСТЬ. Приклади вище стверджують про конкретну локаль; якщо
      # вона мовчки відкотиться в базову, кожен із них упаде на іншому рядку й
      # діагноз читався б як «переклад зник», а не «локаль не та».
      it "is measuring the intended locale, not the base one" do
        expect(I18n.locale).to eq(locale)
        expect(I18n.t("errors.messages.blank")).to eq(expected[:blank])
      end
    end
  end
end
