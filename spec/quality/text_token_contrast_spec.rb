# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("lib/silken_net/contrast")

# [UI.1] Гейт на ПРИДАТНІСТЬ токена до РОЛІ «колір тексту» — SC 1.4.3, бар 4.5.
#
# 🔴 Навіщо, коли токен-гейти вже є. Обидва наявні судять ІНШЕ:
# `design_token_existence_spec` питає, чи токен ОГОЛОШЕНИЙ у `@theme` (бо Tailwind v4
# на невідомий токен молчки не емітує класу), а `gaia:lint_tokens` — чи в розмітці
# немає СИРОЇ палітри. Обидва зелені для оголошеного gaia-токена з будь-яким
# значенням, тож питання «а чи можна цим кольором писати ТЕКСТ» не ставив ніхто.
#
# Вимір, що завів цей файл (2026-08-19): `--gaia-primary` як колір тексту дає
# **2.30–2.54** у світлій темі — і стояв на **30 сайтах у 15 файлах**, включно з
# обома лейаутами й сайдбаром (тобто на кожній сторінці) та в `shared/`, де діє
# HARD-гейт. Той гейт пропускав це за побудовою: він судить існування токена, ніколи
# його придатність. 🔴 І та сама вада була в САМОМУ ІНСТРУМЕНТІ міграції —
# `bin/migrate-tailwind-tokens` відправляв `text-emerald-500` → `text-gaia-primary`,
# тобто codemod, приписаний каноном як лік, виробляв цей дефект.
#
# 🧱 ГЕЙТ НА ЗНАЧЕННЯ, не на перелік імен: пари рахуються з `@theme` у момент
# прогону, тож він переживає ре-палітрування — зміниш значення токена на бліде,
# і почервоніє саме той токен, не питаючи дозволу. Дзеркало для не-тексту
# (кільце фокуса, бар 3:1) — `focus_ring_contrast_spec`.
#
# 🔒 Стелі названо, інакше зелений читається ширше:
#   1. Судиться ПЛОСКИЙ ужиток. `hover:`/`focus-visible:`/`group-hover:` — це
#      СТАНИ, і їх міряє браузерний прохід (`contrast_audit` форсує псевдоклас);
#      статичний файл не знає, на чому саме стоїть вузол у стані.
#   2. Бар завжди 4.5, тобто НОРМАЛЬНИЙ текст. Великий (≥24px, або ≥18.66px
#      жирний) має право на 3.0 — гейт цього не розрізняє й свідомо суворіший:
#      токен, придатний лише для великого тексту, мусить бути ОГОЛОШЕНИЙ нижче.
#   3. Судиться пара «токен ⟷ ПОВЕРХНЯ, на якій він МОЖЕ стояти», не фактична
#      пара з дерева. Реальні пари — робота браузерного контуру (`UI.3`).
RSpec.describe "[UI.1] Токен-колір тексту тримає AA (SC 1.4.3)", type: :model do
  let(:css_path) { Rails.root.join("app/assets/tailwind/application.css") }
  let(:bar)      { 4.5 }

  # Поверхні, на яких текст тіла реально живе. `status-*` фони сюди НЕ входять:
  # вони пара для `status-*-text` і судяться окремим прикладом нижче.
  let(:surfaces) { %w[gaia-surface-base gaia-surface gaia-surface-elevated gaia-surface-sunken] }

  # 🔴 ОГОЛОШЕНІ ВИНЯТКИ — рівно два, кожен із ВИМІРЯНИМ числом, і обидва про
  # ОДНУ поверхню (`surface-sunken`). Це не skip-list: пара названа точно, тож
  # новий токен, що провалить будь-яку іншу поверхню, червонить.
  # ⚠️ Обидва — межові промахи (4.39 при 4.5), і обидва мають зовнішнє свідчення:
  # `gaia-label` пінить браузерний контур на живій сторінці `/firmwares/new`, де
  # він стоїть на `gaia-surface` (4.83). Якщо колись з'явиться плоский текстовий
  # сайт цього токена НА sunken — його зловить контур, не цей файл.
  let(:exempt) do
    {
      [ "gaia-label", "gaia-surface-sunken", :light ] => "4.39 — межовий промах; плоских сайтів на sunken не виміряно",
      [ "status-danger-accent", "gaia-surface-sunken", :light ] => "4.39 — те саме; accent живе на surface/elevated"
    }
  end

  def css = @css ||= css_path.read

  # Якір СТРУКТУРНИЙ: голий пошук підрядка знаходить КОМЕНТАР за двісті рядків
  # вище (спіймано на сусідньому гейті 2026-08-19), тож беремо рядок, що
  # ПОЧИНАЄТЬСЯ з `@media` і відкриває блок.
  def halves
    @halves ||= begin
      i = css.index(/^@media[^{]*prefers-color-scheme:\s*dark[^{]*\{/)
      raise "темна шафа не знайдена — гейт міряв би одну тему двічі" if i.nil?

      # [UI.1 п.11] Права межа dark-шафи — початок a11y-перевизначень
      # (`prefers-contrast` піднімає найтихіші токени до `var(--gaia-text)`).
      # Без межі `.last` брав би САМЕ їх, і гейт давився var()-посиланням:
      # a11y-блоки — ТРЕТЯ шафа з власною семантикою, цей файл судить дві базові.
      j = css.index(/^@media \(prefers-contrast/) || css.length
      { light: css[0...i], dark: css[i...j] }
    end
  end

  def token(name, half)
    halves.fetch(half).scan(/--#{Regexp.escape(name)}:\s*([^;]+);/).last&.first&.strip
  end

  def ratio(a, b)
    SilkenNet::Contrast.ratio(SilkenNet::Contrast.parse(a), SilkenNet::Contrast.parse(b))
  end

  # Плоский ужиток `text-<token>`: без префікса стану, поза повнорядковими
  # коментарями. ⚠️ Негативний lookbehind на `[-:\w]` несучий — без нього
  # `text-gaia-primary` матчиться ВСЕРЕДИНІ `hover:text-gaia-primary-strong`,
  # і гейт звітує стан як плоский ужиток.
  def plain_text_tokens
    @plain_text_tokens ||= begin
      pattern = /(?<![-:\w])text-((?:gaia|status|token)-[a-z0-9-]+)(?![-\w])/
      Dir.glob(Rails.root.join("app/views/**/*.rb")).each_with_object({}) do |path, acc|
        File.readlines(path).each_with_index do |line, i|
          next if line.lstrip.start_with?("#")

          line.scan(pattern).flatten.each do |tok|
            acc[tok] ||= []
            acc[tok] << "#{Pathname.new(path).relative_path_from(Rails.root)}:#{i + 1}"
          end
        end
      end
    end
  end

  it "ліхтар: розкол шафи живий і токени в обох половинах" do
    %i[light dark].each do |half|
      count = halves.fetch(half).scan(/--gaia-[a-z0-9-]+:/).size
      expect(count).to be >= 10, "шафа #{half} несе #{count} токенів — розкол зламався"
    end
  end

  # Ліхтар на скоуп: порожня множина зробила б головний приклад вакуумним —
  # він би пройшов, «не знайшовши порушень» у нуля кандидатів.
  it "ліхтар: у дереві взагалі є плоскі текстові токени" do
    expect(plain_text_tokens.size).to be >= 10,
                                      "знайдено #{plain_text_tokens.size} токенів — регекс або glob обвалились"
  end

  it "кожен ПЛОСКО вжитий текстовий токен тримає 4.5 на кожній звичній поверхні" do
    failures = plain_text_tokens.keys.sort.flat_map do |tok|
      %i[light dark].flat_map do |half|
        colour = token(tok, half)
        next [] if colour.nil?   # оголошення поза шафою — не предмет цього гейта

        surfaces.filter_map do |surface|
          next if exempt.key?([ tok, surface, half ])

          sv = token(surface, half)
          next if sv.nil?

          r = ratio(colour, sv)
          next if r >= bar

          format("%s: text-%s (%s) на %s → %.2f  [%d сайт(ів), напр. %s]",
                 half, tok, colour, surface, r,
                 plain_text_tokens[tok].size, plain_text_tokens[tok].first)
        end
      end
    end

    expect(failures).to be_empty, <<~MSG
      Токен ужито як колір ТЕКСТУ, і він не тримає AA:
        #{failures.join("\n  ")}

      Гейти існування токена й заборони сирої палітри цього не бачать за
      побудовою — вони судять ІМʼЯ, не придатність до РОЛІ. Або переведи сайти
      на придатний токен (парний `-strong` — усталена форма), або, якщо ужиток
      законно ВЕЛИКИЙ/декоративний, додай пару в `exempt` РАЗОМ із виміром.
    MSG
  end

  # Друга вісь: бейдж. `status-*-text` живе на ПАРНОМУ `status-*` фоні, і ця
  # пара не покрита прикладом вище — там судяться gaia-поверхні.
  it "кожен `status-*-text` тримає 4.5 на своєму ПАРНОМУ фоні" do
    families = plain_text_tokens.keys.filter_map { |t| t[/\Astatus-([a-z]+)-text\z/, 1] }.uniq

    expect(families.size).to be >= 4, "родин статусу знайдено #{families.size} — скоуп обвалився"

    failures = families.sort.flat_map do |fam|
      %i[light dark].filter_map do |half|
        fg = token("status-#{fam}-text", half)
        bg = token("status-#{fam}", half)
        next if fg.nil? || bg.nil?

        r = ratio(fg, bg)
        next if r >= bar

        format("%s: text-status-%s-text (%s) на bg-status-%s (%s) → %.2f", half, fam, fg, fam, bg, r)
      end
    end

    expect(failures).to be_empty, <<~MSG
      Текст бейджа не тримає AA на власному фоні:
        #{failures.join("\n  ")}
    MSG
  end
end
