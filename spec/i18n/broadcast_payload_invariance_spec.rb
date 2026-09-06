# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# Гейт інваріанта `04_04 §8.1а`: **вартість live-оновлення масштабується ПОПИТОМ
# (глядачі), НІКОЛИ каталогом (локалі)**.
#
# Механіка дефекту, який він ловить: `html:` — звичайний аргумент, тож Phlex-рендер
# їде **eagerly в процесі-ПРОДЮСЕРА**, а `LocaleSettable` — це `before_action`,
# якого нема ні в Sidekiq, ні в `ApplicationController.renderer`. Отже кожен `t()`
# у broadcast-компоненті віддає локаль ТОГО, ХТО СПРИЧИНИВ подію, усім підписникам
# одразу — латвієць бачить український рядок, бо українець натиснув кнопку.
#
# Форма — **авто-виявлення + іменований shrink-list**, як прописано в §8.1а:
# новий broadcast-компонент потрапляє під перевірку ЗА ЗАМОВЧУВАННЯМ (його не
# треба нікуди вписувати), а свідомий виняток мусить бути названий і може лише
# скорочуватись. Мертвий виняток червоніє — інакше «0 порушень» = «0 перевірок».
#
# 🔒 Стеля, названа чесно:
#   · Перевірка СТАТИЧНА — рахує `t(`/`I18n.t(` у ВЛАСНОМУ джерелі компонента.
#     Локаль-залежність, схована в сервісі, який компонент кличе (наприклад
#     `TextFormatter.alert_title`), сюди не потрапляє. Байт-у-байт рендер у двох
#     локалях був би сильніший, але вимагає конструктора на кожен компонент і
#     втрачає авто-виявлення — свідомий розмін.
#   · Не ходить у ДОЧІРНІ компоненти: `t()` дитини їде в тому ж payload'і
#     (`Alerts::Row` і його тодішній дочірній pill — саме такий випадок). Тому
#     запис у shrink-list знімається лише після READ дерева, не після грепу.
#   · 🔴 Патерн вимагає БАГАТОРЯДКОВОГО виклику (закривна дужка на власному
#     відступленому рядку), тож ОДНОРЯДКОВИЙ `broadcast_*_to(...)` невидимий —
#     виміряно: у `unpack_telemetry_worker.rb` він бачить 1 виклик із 2
#     (однорядковий `broadcast_remove_to(…, target: "feed_placeholder")`
#     пропущено). ЦЬОМУ гейту це поки не шкодить — bare-remove не
#     несе `html:`, отже й прози, — але машинерію не можна переносити як є в
#     гейт, якому потрібен ПОВНИЙ набір продюсерів (вісь «продюсер ⟷ підписник»,
#     `00_07` UI.4): там пропущений виклик = хибно-зелений. Перед злиттям —
#     переписати на AST (`Ripper`), не розширювати регекс.
RSpec.describe "broadcast payload carries no locale-dependent prose" do # rubocop:disable RSpec/DescribeClass
  # Компоненти, чий broadcast-продюсер живий, але payload ще не мігровано.
  # Стан і план по кожному → `00_07` I18N.2. Список ТІЛЬКИ скорочується.
  # ✅ ПОРОЖНІЙ від 2026-08-14 — борг вичерпано (`Telemetry::LogEntry` мігрував
  # останнім; сам компонент згодом заступив `Telemetry::BatchSummary` — [UI.16]
  # 2026-09-06, — і наступник народився з нулем `t()`, тож список лишився порожнім).
  # Машинерія лишається: це дім для наступного боргу, а не решта
  # від старого. Порожній список означає «кожен broadcast-компонент дерева
  # тримає інваріант», і саме це стереже приклад нижче.
  let(:pending) { [] }

  # Витягуємо константу компонента з `html:`-виразу кожного broadcast-сайту.
  let(:broadcast_components) do
    Dir[Rails.root.join("app/**/*.rb")].sort.flat_map do |path|
      src = File.read(path)
      src.scan(/Turbo::StreamsChannel\.broadcast_\w+\((.{0,800}?)\n\s*\)/m).flat_map do |(body)|
        body.scan(/html:\s*(?:render_phlex\()?\s*((?:::)?[A-Z][\w:]*)/).flatten
      end
    end.map { |c| c.delete_prefix("::") }.uniq
  end

  # Два корені: доменні компоненти живуть під `components/`, простір `Views::`
  # (shared-примітиви) — прямо під `app/views/`.
  def component_source(const_name)
    rel = "#{const_name.delete_prefix('Views::').underscore}.rb"
    path = [ Rails.root.join("app/views/components", rel), Rails.root.join("app/views", rel) ]
           .find { |candidate| File.exist?(candidate) }
    return nil unless path

    File.readlines(path).reject { |l| l.strip.start_with?("#") }.join
  end

  # Без цього «0 порушень» могло б означати «сканер не знайшов жодного броадкасту».
  it "is a live check (broadcast sites with Phlex payloads exist)" do
    expect(broadcast_components).not_to be_empty,
      "жодного `html:`-компонента в broadcast-сайтах не знайдено — сканер дивиться не туди"
  end

  it "has no dead entry in the shrink-list" do
    dead = pending - broadcast_components

    expect(dead).to be_empty,
      "виняток більше не рендериться в жодному broadcast (продюсера знято) — приберіть: #{dead.join(', ')}"
  end

  # 🔴 ДРУГА вісь смерті винятку, і саме вона тут прожила непоміченою
  # (знайдено 2026-08-14, коли `Telemetry::LogEntry` домігрував).
  #
  # Перевірка вище ловить лише «продюсера знято». Компонент, який ЗАЛИШИВСЯ
  # у броадкасті, але позбувся всіх `t()`, для неї виглядає живим винятком
  # назавжди — а виняток без підстави не просто декоративний: він ПРИКРИВАЄ
  # регресію, бо `t()`, повернений у такий компонент, гейт пропустить.
  #
  # Клас — `ssot-maintenance/guard-craft.md` #53 («реєстр винятків стереже
  # НАЯВНІСТЬ умови, ніколи її ІСТИННІСТЬ»); відмінність у тому, що тут
  # істинність механічно перевіряна, тож лишати її оку не було підстав.
  it "has no exemption whose grounds have expired (component already clean)" do
    expired = pending.filter_map do |const_name|
      src = component_source(const_name)
      next if src.nil?

      const_name if src.scan(/\bt\(|\bI18n\.t\(/).none?
    end

    expect(expired).to be_empty,
      "виняток більше не потрібен — компонент уже без `t()`, а запис у списку прикриває майбутню регресію: #{expired.join(', ')}"
  end

  it "keeps every non-exempt broadcast component free of t() calls" do
    offenders = (broadcast_components - pending).filter_map do |const_name|
      src = component_source(const_name)
      next if src.nil? # константа не резолвиться у файл — окремий приклад нижче

      hits = src.scan(/\bt\(|\bI18n\.t\(/).size
      "#{const_name} (#{hits})" if hits.positive?
    end

    expect(offenders).to be_empty,
      "broadcast-компонент несе локаль-залежну прозу — payload піде з локаллю ПРОДЮСЕРА (`04_04 §8.1а`): #{offenders.join(', ')}"
  end

  # Якщо константа не мапиться у файл, попередній приклад мовчки її пропускає —
  # тобто гейт звузився б непомітно.
  it "resolves every discovered component to a source file" do
    unresolved = broadcast_components.reject { |c| component_source(c) }

    expect(unresolved).to be_empty,
      "не знайдено джерела компонента — перевірку для нього мовчки пропущено: #{unresolved.join(', ')}"
  end
end
