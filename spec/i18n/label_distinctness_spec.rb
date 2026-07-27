# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# Гейт класу «дві операційно РІЗНІ мітки злиплись в одне слово».
#
# 🔴 Вісь, якої не має жоден інший гейт — і не через недогляд, а за побудовою:
# `i18n-tasks missing` і `enum_label_parity_spec` питають «чи мітка Є», ніколи
# «чи вона ВІДРІЗНЯЄТЬСЯ від сусідньої». Обидва ключі присутні, обидва
# перекладені, всі локалі узгоджені — зелено скрізь, а користувач не може
# відрізнити два стани.
#
# Живий прецедент (I18N.1, 2026-07-27): `actuators.command_status_badge`
# рендерив `acknowledged` і `confirmed` ОДНИМ словом у всіх трьох неанглійських
# локалях (uk «підтверджено»×2, lv `apstiprināts`×2, lt `patvirtinta`×2). А модель
# каже, що це різні фізичні стани: `acknowledge` = момент, коли дія ФІЗИЧНО
# починається (клапан відкривається, сирена вмикається), `confirm` виставляє
# `completed_at`. Тобто оператор-неангломовець не відрізняв «сирена виє» від
# «сирена замовкла», а англомовний відрізняв.
#
# ⚠️ Перевірка йде по ВСІХ налаштованих локалях, а не лише по базовій — і це
# свідоме відхилення від правила §12.14. Причина проста: дефект живе саме в
# перекладі. Базова локаль тут завжди зелена (`acknowledged`/`confirmed` —
# різні токени), тож base-only перевірка не знайшла б НІЧОГО. Ціна лишається
# мізерною (порівняння рядків), а нова, ще не перекладена локаль не червоніє:
# fallback-ланцюг віддає базові мітки, які вже різні.
#
# 🔒 Стеля: гейт судить лише РІЗНІСТЬ, не правильність. Дві різні, але однаково
# хибні мітки він пропустить — це робота нативного ревʼю (`protocols/i18n/`).
RSpec.describe "operationally distinct labels stay distinct" do # rubocop:disable RSpec/DescribeClass
  # Курована мапа як tripwire (`00_06 §3`): один рядок на набір міток, які
  # користувач бачить у ТОМУ САМОМУ місці й мусить розрізняти.
  let(:distinct_sets) do
    [
      {
        name: "ActuatorCommand#status → бейдж команди",
        scope: "actuators.command_status_badge",
        keys: -> { ActuatorCommand.statuses.keys }
      },
      {
        # `ui.status` — спільний bag на кілька моделей, тож повний набір там
        # розрізняти НЕ зобов'язаний (різні доми можуть законно ділити слово).
        # Але ці п'ять стоять поруч у житті однієї команди, і `StatusBadge` може
        # показати будь-яку з них — отже між собою вони мусять різнитись.
        # ⚠️ `confirmed` тут належить BlockchainTransaction («підтверджено
        # мережею»), а не актуатору — саме тому переклади двох домів свідомо
        # асиметричні, і саме тому цей набір заданий ЯВНО, а не з enum'а.
        name: "спільний ui.status — життєвий цикл команди",
        scope: "ui.status",
        keys: -> { %w[issued sent acknowledged failed confirmed] }
      }
    ]
  end

  # Без цього «0 порушень» могло б означати «0 перевірок».
  it "is a live check (every registered set resolves to real labels)" do
    distinct_sets.each do |set|
      keys = set[:keys].call
      expect(keys).not_to be_empty, "#{set[:name]}: порожній набір ключів — джерело зникло?"

      unresolved = keys.reject { |k| I18n.exists?("#{set[:scope]}.#{k}", I18n.default_locale, fallback: false) }
      expect(unresolved).to be_empty,
        "#{set[:name]}: скоуп `#{set[:scope]}` не резолвить #{unresolved.join(', ')} — реєстр застарів"
    end
  end

  it "renders a different word for every state, in every configured locale" do
    collisions = distinct_sets.flat_map do |set|
      keys = set[:keys].call

      I18n.available_locales.flat_map do |locale|
        labels = keys.index_with { |k| I18n.t("#{set[:scope]}.#{k}", locale: locale, default: k) }

        labels.group_by { |_k, v| v.to_s.downcase }
              .select { |_label, pairs| pairs.size > 1 }
              .map { |label, pairs| "#{set[:name]} [#{locale}]: #{pairs.map(&:first).join(' = ')} → «#{label}»" }
      end
    end

    expect(collisions).to be_empty, <<~MSG.strip
      два операційно різні стани рендеряться ОДНИМ словом:
        #{collisions.join("\n  ")}
      Це не нюанс перекладу — користувач тієї мови втрачає інформацію, яку має англомовний.
    MSG
  end
end
