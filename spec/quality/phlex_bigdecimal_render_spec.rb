# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# Гейт ЯВНОГО ФОРМАТУ — дві осі, кожна зі своїм прикладом:
#   1. `decimal`-колонка (або аліас над нею) не сміє потрапляти в Phlex-блок
#      голою — там вона друкується сирою точністю схеми, а не тим форматом,
#      який обрав дизайн (`04_04 §2`).
#   2. рукописна пара `.to_f.round(` у view-дереві — це друга копія формули
#      дому форматування; формат кличуть домом (`formatted_points` — бали,
#      `formatted_amount` — гроші), ніколи не пишуть на місці.
#
# 🔴 ПІДСТАВА МІНЯЛАСЬ ДВІЧІ — читай, перш ніж посилатись на цей гейт.
# Народився він як гейт РЕНДЕРОВНОСТІ: Phlex друкував `BigDecimal` ПОРОЖНІМ
# рядком, тож `Trees::Show` малював порожнім `text-6xl` Z-координату і баланс.
# Ту причину знято в корені — `ApplicationComponent` заповнив Phlex-хук
# `format_object` для всього роду `Numeric` (носій — `spec/views/components/
# application_component_spec.rb`), і зникнення значення перестало бути режимом
# відмови. Далі гейт стеріг «будь-яке перетворення» — і присуд founder
# 2026-08-14 зафіксував, що це мандатує нейтральне-або-шкідливе: `.to_f` на
# звичайних значеннях не змінює нічого, а на краях втрачає точність
# (`12345678901234.567891` → `…4.568`) і скочується в наукову нотацію
# (`0.000001` → «1.0e-06») — гейт, що вимагає гіршого, гірший за відсутність
# гейта. ✅ ПЕРЕОРІЄНТОВАНО [ARCH.89]: тепер гейт веде до ДОМУ формату.
# Розблокувала переорієнтацію архівація ARCH.103 — питання «чи існує величина»
# (`emitted_tokens`) закрилось зняттям колонки, а точність показу грошей
# вирівнялась на 2; дім `formatted_amount` заведено з ВЛАСНИМ обґрунтуванням
# (вибір дизайну показу), окремим від балового (крок джерела) — два різні
# обґрунтування і є причиною двох домів (`ApplicationComponent`).
#
# ⚠️ Що НЕ рятує від сирої точності: `.round(2)` — на BigDecimal він повертає
# BigDecimal. Голий `.to_f` БЕЗ округлення лишається чесною формою для
# БЕЗРОЗМІРНИХ величин (z_value — координата атрактора; lat/lng у data-хеші
# для JS) — і рівно тому перша вісь його пропускає, а друга судить лише пару.
#
# 🔴 Стелі, названі бо вже коштували живих сайтів:
#   · перша вісь стереже «КОЛОНКА в голому блоці» — множина береться з
#     `columns_hash`/`attribute_aliases`, тож вираз без імені колонки (kwarg
#     компонента, результат арифметики) для неї невидимий ЗА ПОБУДОВОЮ; цю
#     половину закриває рантайм-хук `format_object` (гучний у не-prod);
#   · друга вісь судить ФОРМУ `.to_f.round(` — `.round(N)` без `.to_f` вона
#     свідомо не чіпає: єдиний живий клас цієї форми — гео-координати
#     (`round(4)` ≈ 11 м, точність семантична, не грошова), і гейт на них
#     народився б із реєстром винятків; нову грошову форму без `.to_f`
#     тримає ревʼю;
#   · JSON-гілки контролерів (`/.round(4)/`) поза периметром СВІДОМО — їхню
#     точність вирівнював ARCH.103 окремим рішенням, а `WalletBlueprint`
#     віддає сиру `numeric(24,6)` навмисно.
#
# ⚠️ Компонентна спека сліпа до класу, поки фікстура — `OpenStruct`: той віддає
# Ruby-`Float`, тож сюїта бачить число там, де прод малює порожнечу (`04_06 §B.2` BP #14).
RSpec.describe "Phlex не друкує BigDecimal", type: :model do
  # 🔴 Множини беруться з РАНТАЙМУ, не з рукописного переліку: інакше нова
  # `decimal`-колонка чи новий аліас випадуть із периметра мовчки.
  def decimal_names
    @decimal_names ||= begin
      Rails.application.eager_load!
      cols = ActiveRecord::Base.descendants.flat_map do |m|
        begin
          next [] if m.abstract_class?
          next [] unless m.table_exists?

          m.columns_hash.filter_map { |n, c| n if c.type == :decimal } +
            m.attribute_aliases.filter_map { |from, to| from if m.columns_hash[to]&.type == :decimal }
        rescue StandardError
          []
        end
      end
      cols.uniq
    end
  end

  # Конвертори, після яких у блок їде вже НЕ BigDecimal. `\.round\b(?!\()` —
  # саме без аргументу: `round` дає Integer, `round(2)` лишає BigDecimal.
  #
  # 🔴 `formatted_(points|amount)\(` — це НЕ послаблення, а перенесення ключа
  # на ЦЕНТРАЛІЗАТОР (§Guard-craft #23): One-Home зробив `.to_f.round(2)`
  # внутрішньою справою домів, тож гейт, ключований на літеральній формі,
  # червонив би рівно ті вузли, які щойно стали правильними. Ключ на імені
  # методу строгіший: метод ГАРАНТУЄ тип і має власних носіїв
  # (`points_precision_home_spec` + пін дому нижче), тоді як `.to_f` посеред
  # виразу нічого про решту виразу не обіцяє.
  def safe_conversion = /\.to_f|\.to_i|\.to_s|\.round\b(?!\()|sprintf|format\(|number_|formatted_(points|amount)\(/

  def bare_decimal_renders
    re_col = Regexp.union(decimal_names)

    Dir.glob(Rails.root.join("app/views/**/*.rb")).flat_map { |file|
      File.readlines(file).each_with_index.flat_map { |line, idx|
        line.to_enum(:scan, /\{([^{}]*)\}/).filter_map do
          match = Regexp.last_match
          expr  = match[1]

          # `#{…}` — інтерполяція, вона кличе `to_s`, тож безпечна.
          next if match.pre_match.end_with?("#")
          # `t(".key", amount: x)` — i18n теж інтерполює значення.
          next if expr.match?(/\A\s*t\(/)
          next unless expr.match?(/(?:^|[.\s(])(#{re_col})\b/)
          next if expr.match?(safe_conversion)

          "#{file.sub("#{Rails.root}/", '')}:#{idx + 1} → #{expr.strip}"
        end
      }
    }
  end

  # Друга вісь [ARCH.89]: рукописна пара `.to_f.round(` = друга копія формули
  # дому. Судить ФОРМУ, не імʼя колонки — тому бачить і kwarg-сайти
  # (`@cluster_emission`), до яких перша вісь сліпа за побудовою.
  # Прозу (коментарі) зрізаємо — інакше гейт червонів би на власній історії
  # (§Guard-craft #10a).
  def handwritten_rounding
    home = "app/views/components/application_component.rb"

    Dir.glob(Rails.root.join("app/views/**/*.rb")).flat_map { |file|
      rel = file.sub("#{Rails.root}/", "")
      next [] if rel == home

      File.readlines(file).each_with_index.filter_map { |line, idx|
        next if line.lstrip.start_with?("#")

        "#{rel}:#{idx + 1} → #{line.strip}" if line.match?(/\.to_f\.round\(/)
      }
    }
  end

  it "перелічує decimal-колонки з рантайму, а не з рукописного списку" do
    # Liveness: без цього прикладу порожній перелік зробив би головний гейт
    # вакуумним — «нуль порушень» означало б «нуль перевірок».
    expect(decimal_names).to include("balance", "z_value", "total_funding")
    expect(decimal_names).to include("scc_balance", "total_value") # аліаси
  end

  it "тримає обидва доми формату оголошеними (liveness другої осі)" do
    # Зняття дому лишило б сайти падати NoMethodError у рендері — цей пін
    # червоніє раніше й називає, ЩО зникло.
    expect(ApplicationComponent::POINTS_PRECISION).to eq(2)
    expect(ApplicationComponent::AMOUNT_PRECISION).to eq(2)
    expect(ApplicationComponent.instance_method(:formatted_points)).to be_present
    expect(ApplicationComponent.instance_method(:formatted_amount)).to be_present
  end

  it "не має жодного голого decimal у Phlex-блоці" do
    expect(bare_decimal_renders).to be_empty, <<~MSG
      `decimal` у голому блоці друкується СИРОЮ точністю схеми — ці вузли
      віддають формат бази, а не той, що обрав дизайн:

      #{bare_decimal_renders.join("\n      ")}

      Лік: клич дім формату (`formatted_points` — бали · `formatted_amount` —
      гроші, `04_04 §2`). Для БЕЗРОЗМІРНОЇ величини (координата, z_value)
      чесна форма — `.to_f` без округлення. ⚠️ `.round(2)` НЕ рятує — на
      BigDecimal він повертає BigDecimal.
    MSG
  end

  it "не тримає рукописних копій формули дому (.to_f.round)" do
    expect(handwritten_rounding).to be_empty, <<~MSG
      `.to_f.round(` у view-дереві — це друга копія формули дому форматування,
      і вона розʼїдеться з ним мовчки (так застосунок уже відповідав на одне
      питання трьома числами — ARCH.88):

      #{handwritten_rounding.join("\n      ")}

      Лік: `formatted_points(x)` для балових величин, `formatted_amount(x)` для
      грошових (SCC/USD) — дім і обґрунтування точності → `04_04 §2`.
    MSG
  end
end
