# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# =============================================================================
# [ARCH.110] РЕЄСТР ПРИЧИН CLUSTER-LEVEL FIELD-AUDIT МУСИТЬ ЛИШАТИСЬ ПОВНИМ
# =============================================================================
# ⚖️ Присуд founder 2026-08-25. Дискримінатор «кластер не чути» ⊥ «вердикт
# утримано» несе `message_key`, і на ньому стоять ДВА механізми: дедуп ескалацій
# (`EwsAlert.escalate_field_audit!`) і глушник dead-man switch'а
# (`TreeStalenessSweepWorker#dark_cluster_ids`).
#
# 🔴 Чому потрібен гейт, а не самої константи досить. Новий cluster-level продюсер
# приїде з новим ключем і мовчки випаде з ОБОХ списків: `SILENCE_ASSERTING_KEYS`
# його не знає, тож глушник просто не спрацює — і ніщо не почервоніє, бо
# «не глушить» це штатна гілка. Тобто зламається саме той бік, якого не видно.
# Дзеркально: ключ, вилучений із локалей, лишив би рендер порожнім, а вердикт —
# без тексту для людини, що поїде в поле.
#
# 🔒 Оголошена СТЕЛЯ, щоб гейт не читався ширше, ніж він є:
#   (1) Скан бере ЛІТЕРАЛЬНІ `message_key:` у виклик-сайтах `escalate_field_audit!`.
#       Динамічно склеєні ключі (`"slash_frozen_#{magnitude}_#{subject}"` у
#       `BlockchainBurningService`) статично не видно — їхні розгортки внесені в
#       реєстр руками, і саме їх стереже нога (б) через локалі.
#   (2) Гейт судить ПОВНОТУ реєстру, а не ПРАВИЛЬНІСТЬ класифікації: чи ключ
#       справді стверджує нечутність, вирішує його ПУСКАЧ, і це присуд людини.
#       Приклад: `insurance_no_data` живе в silence-половині попри своє ім'я, бо
#       підіймається рівно на `router.blackout?`.
#   (3) Аргумент-матчер `[^)]*` обривається на ПЕРШІЙ `)`, тож виклик із вкладеним
#       викликом у `message_params` (`format(...)`, `.round(1)`) розпарситься
#       вкорочено — і `tree:`, що стоїть за ним, стане невидимим, тобто per-tree
#       ескалація хибно вимагатиме класифікації. Виміряно 2026-08-25: таких
#       викликів у дереві НУЛЬ. Побачив червоне на per-tree виклику — це ця стеля,
#       і лікується вона винесенням значення у змінну ПЕРЕД викликом.
# =============================================================================
RSpec.describe "Cluster-level field_audit key registry", type: :model do
  # Периметр УСЬОГО `app/` + `lib/`, не трьох «очевидних» тек: продюсером може стати
  # будь-що (`app/jobs/` уже існує й у вужчому скані був невидимий). Ціну розширення
  # виміряно ДО вмикання — нуль нових хітів, тобто воно безкоштовне.
  let(:producer_globs) { %w[app/**/*.rb lib/**/*.rb] }

  # Літеральний `message_key: "…"` у межах виклику `escalate_field_audit!`.
  let(:call_with_literal_key) { /escalate_field_audit!\((?<args>[^)]*)\)/m }

  let(:registry) { EwsAlert::CLUSTER_FIELD_AUDIT_KEYS }

  it "розділяє реєстр на дві половини без перетину й без порожнеч" do
    expect(EwsAlert::SILENCE_ASSERTING_KEYS).to all(be_present)
    expect(EwsAlert::VERDICT_HELD_KEYS).to all(be_present)
    expect(EwsAlert::SILENCE_ASSERTING_KEYS & EwsAlert::VERDICT_HELD_KEYS).to be_empty
    expect(registry.uniq.size).to eq(registry.size)
  end

  it "кожен ЛІТЕРАЛЬНИЙ ключ cluster-level продюсера класифіковано в реєстрі" do
    files = producer_globs.flat_map { |glob| Dir[Rails.root.join(glob)] }
    # Ліхтар на сам скан: переїзд каталогів інакше дав би «0 порушень» на нулі
    # прочитаних файлів — зелений на порожній множині.
    expect(files.size).to be > 50

    found = files.flat_map { |path|
      File.read(path).scan(call_with_literal_key).flatten.flat_map { |args|
        # per-tree ескалації живуть в іншому dedup-скоупі й глушника не годують.
        next [] if args.include?("tree:")

        args.scan(/message_key:\s*"([a-z0-9_]+)"/).flatten
      }
    }.uniq

    expect(found).not_to be_empty, "скан не знайшов жодного продюсера — зламався патерн, не код"
    expect(found - registry).to be_empty,
      "некласифіковані cluster-level message_key: #{(found - registry).inspect} — " \
      "внеси кожен у SILENCE_ASSERTING_KEYS або VERDICT_HELD_KEYS (ews_alert.rb)"
  end

  it "кожен ключ реєстру має текст у КОЖНІЙ локалі" do
    missing = I18n.available_locales.flat_map { |locale|
      registry.filter_map { |key|
        "#{locale}/#{key}" unless I18n.exists?("#{EwsAlert::MESSAGE_SCOPE}.#{key}", locale)
      }
    }

    expect(missing).to be_empty, "ключі реєстру без перекладу: #{missing.inspect}"
  end
end
