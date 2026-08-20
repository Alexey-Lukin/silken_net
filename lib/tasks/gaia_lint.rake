# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# Lints Phlex views for raw Tailwind colour utilities that should be design
# tokens (docs/04_04 § 3.1) — and its DEFAULT PERIMETER is the surface where
# that rule is actually binding.
#
# 🔴 [UI.1] The default used to be `app/views/components/`, which inverted the
# gate: `04_04 § 3.5` back then ALLOWED raw Tailwind in domain page-components
# ("вони не переповикористовуються у різних контекстах") and FORBADE it in
# `app/views/shared/**`. So the linter scanned the permissive surface — where a
# hit was not a violation — and was blind to the strict one, which it never
# looked at at all. Measured at the flip: shared/ = 0 hits over every file,
# components/ = several hundred then-legal ones.
#
# ⚠️ READ THAT PARAGRAPH AS HISTORY — the permission it cites is DEAD. It was
# withdrawn on 2026-08-07 (§3.5 narrowed to theme-invariant *and declared*), yet
# this comment kept asserting it in the PRESENT tense until 2026-08-15, i.e. the
# gate that enforces the rule justified its own perimeter by a licence the rule
# no longer grants — the SEVENTH surviving copy found that day (two component
# headers, a spec comment, a spec's NAME, two canon lines, and this). A raw
# colour under `app/views/components/**` is a THEME DEFECT today; it sits
# outside this gate's default PERIMETER, never outside the RULE. Repealing a
# rule means sweeping its CITATIONS, not its section: the section has an owner,
# the citations do not.
#
#   bin/rails gaia:lint_tokens                          # the HARD default — see
#                                                       # `default_scopes` below
#   LINT_SCOPE=app/views/components/wallets/ \
#     bin/rails gaia:lint_tokens                        # any subtree, on demand
#
# ⚠️ The default is a LIST since 2026-08-19 (UI.1) and its members live in
# `default_scopes` — do not enumerate them here. A domain joins that list the
# moment it measures clean under BOTH instruments (this gate ⊥ an independent
# grep for palette / bracketed colour / inline `style:`), and thereby loses the
# right to regress. `LINT_SCOPE=` still takes exactly ONE path.
#
# ⚠️ `app/views/layouts/` is deliberately OUT of the default: measured, its one
# hit is `backdrop:bg-black/60` — the scrim behind the mobile drawer, which must
# stay black in BOTH themes (a surface token there would make the light-theme
# scrim pale). Adding layouts means adding that allowlist entry first.
#
# ⚠️ LINT_SCOPE= takes ONE path. The `.then` below branches on `directory?`, so a
# space-separated pair yields a non-directory Pathname and silently lints one
# nonexistent file — green with zero files scanned, the decorative-gate shape.
#
# Allowlist: see `allowlist` below — brand / decorative colours that are raw on
# purpose (e.g. `bg-emerald-500/10` for the login button's brand-glow).
#
# ✅ [UI.3 (б), 2026-08-15] ОБИДВА раніше оголошені сліпі діалекти ЗАКРИТО — GRADIENT
# stops (`from-`/`via-`/`to-black`) і ARBITRARY colour values (`bg-[#000]`,
# `bg-[radial-gradient(#10b981…)]`). Це не був теоретичний зазор: саме градієнтною
# формою сирий колір повернувся в `telemetry/live_stream`, тобто рівно туди, де
# `04_04 § 3.5` його забороняє, а гейт лишався зеленим. Ratchet виконано в
# приписаному цим же файлом порядку — периметр поміряно ПЕРЕД внесенням: у
# `app/views/shared/**` нуль хітів обох діалектів, тож migrate-to-green не
# знадобився. ⚠️ Arbitrary-патерн навмисно вимагає КОЛІР усередині дужок,
# а не будь-яке arbitrary-значення: `min-h-[60vh]`, `tracking-[0.3em]`,
# `[background-size:20px_20px]` — законні не-кольорові утиліти, і гейт, що
# червонів би на них, зняли б першим.
#
# 🔴 [UI.1, 2026-08-19] ГЕЙТ ПІД-ІМПЛЕМЕНТУВАВ ВЛАСНИЙ КОНТРАКТ, і доводиться це
# не арифметикою, а мутацією. Він друкує «no raw Tailwind **colour utilities**
# detected» — заяву про ВСІ сирі кольорові утиліти, — а знав рівно підмножину:
# `bg-` лише білий/чорний + пʼять НЕЙТРАЛЬНИХ родин (жодної хроматичної);
# `text-` мав `white` і НЕ мав `black` (асиметрія з `bg-`, де є обидва) та різав
# emerald по `400…900`; `border-` різав emerald по `700…900`; носіїв `divide-`,
# `decoration-`, `stroke-`, `fill-`, `ring-` не існувало взагалі. По всьому
# `app/views/**` це 666 бачених проти **268 пропущених** — заниження на 29 %.
#
# Але число тут не вердикт. Мутація ШЕСТИ пропущених родин, вписана в
# `app/views/shared/ui/empty_state.rb` — тобто в HARD-периметр, де правило
# звʼязує й де цей гейт є ЄДИНИМ носієм, — давала `✓ … EXIT=0`. Тобто дірка
# не «теоретично колись», а «перший же сирий `bg-red-500` у `shared/` проходить
# мовчки». Форма класу — `ssot-maintenance` §Guard-craft, «гейт, що
# під-імплементує оголошений контракт»: він не бреше про себе, він просто
# ніколи не звіряв вивіску з реалізацією.
#
# ⚠️ І резидуал `00_07` UI.1 приписував цьому розширенню ЦІНУ, якої більше
# немає: «кожне regex-розширення передує своєю migrate-хвилею, інакше CI
# червоніє миттєво». Це було правдою, доки дефолтний периметр був
# `app/views/components/`; 2026-08-07 його розвернули на `shared/`, а там нуль
# хітів УСІХ пропущених родин — тобто припис пережив власну передумову й
# коштував пункту чотири місяці відкладання. Ratchet виконано так само, як два
# попередні розширення: периметр поміряно ПЕРЕД внесенням.
#
# 🔴 ЩО ЛИШАЄТЬСЯ ЗА СТЕЛЕЮ (гейт судить КЛАСИ в СИРОМУ ТЕКСТІ файла):
#   · інлайн `style:` із кольором — класу не має взагалі, тож не існує тут за
#     побудовою (живих екземплярів у дереві нуль, `00_07` UI.1);
#   · клас, зібраний інтерполяцією чи взятий із константи/БД;
#   · ПРИДАТНІСТЬ пари — гейт не знає поверхні, на якій стоїть текст (вона
#     приходить від батьківського компонента), тож токен при 1.1:1 проходить.
#     Другий бік цієї стелі — браузерний збирач `spec/support/contrast_audit.rb`.
#
# 🔴 ПОВНОРЯДКОВІ КОМЕНТАРІ ПРОПУСКАЮТЬСЯ, і межа тут несуча. Гейт, що червоніє
# на власній документації, знімають першим (прецедент — `no_turbo_permanent_spec`,
# який розділив код і прозу з тієї ж причини); а пояснити дефект, не назвавши
# класу, яким він написаний, неможливо. Стрипиться САМЕ повний рядок-коментар
# (`\A\s*#`), ніколи не «все після `#`»: у Ruby `#` живе й усередині
# `"#{…}"`-інтерполяції, тож наївне обрізання ховало б справжню розмітку —
# хибний НЕГАТИВ, тобто помилка в тому єдиному напрямку, який тут коштує.
# ⚠️ Ціна цієї межі — ТРЕЙЛІНГ-коментар: `foo # раніше тут стояв bg-red-500`
# почервоніє. Живих таких у дереві нуль (перевірено по всіх хітах `components/`
# 2026-08-19), але після розширення до повної палітри шанс зрости — тож
# **прозу, що НАЗИВАЄ клас, пиши окремим рядком**. Це свідомий хибний ПОЗИТИВ,
# дешевий і видимий, обраний замість дешевого й невидимого негативу.
#
# 🔴 NO `:environment` PREREQUISITE, and that is load-bearing rather than tidy.
# The body is pure Ruby (Pathname + ENV), and its docs.yml neighbours —
# `docs:check_refs`, `tracker:check` — declare no `:environment` either, so that
# job has never booted the app and its runner carries no native libvips. With
# the prerequisite in place the step died at `ActiveStorage::Transformers::Vips`
# before the linter ran a single line: green locally, red in CI, for a reason
# that has nothing to do with what the gate checks.
require "pathname"

namespace :gaia do
  desc "Find raw Tailwind colour utilities in shared Phlex primitives (compliance check)"
  task :lint_tokens do
    # [UI.1] Стара назва (`COMPONENTS=`) відмовляє ГУЧНО, а не ігнорується.
    # Мовчазний скип був би найгіршим із можливих виходів: дефолт — існуючий
    # каталог із файлами, тож ліхтар порожнього набору нижче НЕ спрацював би, і
    # прогін надрукував би ✓ про `shared/` людині, яка просила доменний каталог —
    # зелений вердикт про НЕ ТУ множину.
    if ENV["COMPONENTS"]
      abort "✗ gaia:lint_tokens — `COMPONENTS=` перейменовано на `LINT_SCOPE=`. " \
            "Стара назва брехала: дефолт — `shared/` плюс поіменні чисті домени, а не `components/` цілком."
    end

    # [UI.1] Дефолт — СПИСОК, бо ratchet доменний: каталог заходить сюди в мить,
    # коли зміряний чистим, і більше не має права зрегресувати. `LINT_SCOPE=`
    # лишається ОДНИМ шляхом (див. шапку) — міняється дефолт, не контракт змінної.
    # ⚠️ Кожен запис тут вимагає ДВОХ вимірів, а не одного: гейт зелений ⊥
    # незалежний греп по палітрі/дужках/інлайн-`style:` теж нульовий. Інакше
    # «чисто» означало б лише «наш регекс сюди не дотягується».
    default_scopes = [
      "app/views/shared/",              # HARD із 2026-08-07 — §3.5 забороняє тут сиру Tailwind
      "app/views/components/alerts/",   # зміряно чистим 2026-08-19 (обома вимірами)
      "app/views/components/navigation/", # те саме; сайдбар стоїть на КОЖНІЙ сторінці
      "app/views/components/wallets/",  # зміряно чистим 2026-08-20 (codemod-хвиля + обидва виміри)
      "app/views/components/settings/",  # зміряно чистим 2026-08-20 (codemod 29 + 9 ручних: gaia-input-* тріада, пара primary/-text)
      "app/views/components/audit_logs/", # зміряно чистим 2026-08-20 (codemod-хвиля + ручні divide/бейдж, обидва виміри)
      "app/views/components/reports/",    # те саме, 2026-08-20; watermark text-emerald-900/5 — оголошений виняток гейта
      "app/views/components/gateways/",   # 2026-08-20 після сигнальної хвилі (LED/кільця → -strong/-accent; обидва виміри)
      "app/views/components/clusters/",   # те саме; watermark SECTOR — оголошений виняток гейта
      "app/views/components/tree_families/", # 2026-08-20 пʼята порція (codemod 23 + ручні; watermark /5 — виняток)
      "app/views/components/actuators/",  # те саме (STATUS_STYLES бейджа → status-*-пари; LED — сигнальна хвиля)
      "app/views/components/maintenance/", # 2026-08-20 шоста порція (codemod 114-на-два-домени + ручні: action_badge → -accent-родина, кнопки → -strong-пара; watermark /5 — виняток)
      "app/views/components/blockchain_transactions/" # те саме (carbon-чіп → token-carbon фон/рамка, error-панель → danger-пастель+text, ARCH.101 колір напрямку)
    ]

    scopes = ENV["LINT_SCOPE"] ? [ ENV["LINT_SCOPE"] ] : default_scopes
    paths = scopes.flat_map do |p|
      Pathname.new(p).directory? ? Pathname.glob("#{p}/**/*.rb") : [ Pathname.new(p) ]
    end

    # 🔴 ПОВНА палітра Tailwind, а не її підмножина. Доти перелічувались лише
    # пʼять НЕЙТРАЛЬНИХ родин, тож `bg-red-500` не існував для гейта — а сира
    # хроматика саме на сигнальних поверхнях і живе (LED тривоги, severity-рамка).
    # Дві родини мають синоніми (`gray`/`grey` не є Tailwind-класом, але
    # `rebeccapurple` тощо ловить іменований перелік нижче).
    palette = "slate|gray|zinc|neutral|stone|red|orange|amber|yellow|lime|green|" \
              "emerald|teal|cyan|sky|blue|indigo|violet|purple|fuchsia|pink|rose"

    # 🔴 УСІ носії кольору, а не чотири. `divide-`/`decoration-`/`stroke-`/`fill-`
    # були відсутні цілком, і кожен має живих носіїв у дереві (`divide-emerald-900`
    # ×21, `stroke-red-600` на severity-дузі `trees/show`). Той самий перелік
    # обслуговує й arbitrary-гілку — межа була штучна.
    carriers = "bg|text|border|from|via|to|ring|fill|stroke|shadow|outline|" \
               "decoration|divide|accent|caret|placeholder"

    # Іменовані CSS-кольори (CSS Color 4) — третій діалект, яким сирий колір
    # заходить у дужках повз hex-тест. Живі носії: `shadow-[0_0_8px_red]` на
    # `trees/index` і `actuators/card` — ОБИДВА стани тривоги, і обидва стояли
    # рядком поруч зі своїм hex-двійником, який гейт бачив. Тобто дискримінувала
    # не роль і не поверхня, а НОТАЦІЯ.
    named_colours = %w[
      aliceblue antiquewhite aqua aquamarine azure beige bisque black blanchedalmond
      blue blueviolet brown burlywood cadetblue chartreuse chocolate coral
      cornflowerblue cornsilk crimson cyan darkblue darkcyan darkgoldenrod darkgray
      darkgreen darkgrey darkkhaki darkmagenta darkolivegreen darkorange darkorchid
      darkred darksalmon darkseagreen darkslateblue darkslategray darkslategrey
      darkturquoise darkviolet deeppink deepskyblue dimgray dimgrey dodgerblue
      firebrick floralwhite forestgreen fuchsia gainsboro ghostwhite gold goldenrod
      gray green greenyellow grey honeydew hotpink indianred indigo ivory khaki
      lavender lavenderblush lawngreen lemonchiffon lightblue lightcoral lightcyan
      lightgoldenrodyellow lightgray lightgreen lightgrey lightpink lightsalmon
      lightseagreen lightskyblue lightslategray lightslategrey lightsteelblue
      lightyellow lime limegreen linen magenta maroon mediumaquamarine mediumblue
      mediumorchid mediumpurple mediumseagreen mediumslateblue mediumspringgreen
      mediumturquoise mediumvioletred midnightblue mintcream mistyrose moccasin
      navajowhite navy oldlace olive olivedrab orange orangered orchid palegoldenrod
      palegreen paleturquoise palevioletred papayawhip peachpuff peru pink plum
      powderblue purple rebeccapurple red rosybrown royalblue saddlebrown salmon
      sandybrown seagreen seashell sienna silver skyblue slateblue slategray
      slategrey snow springgreen steelblue tan teal thistle tomato turquoise violet
      wheat white whitesmoke yellow yellowgreen transparent currentcolor
    ].join("|")

    # Колір УСЕРЕДИНІ arbitrary-дужок: hex · функція · іменований.
    # ⚠️ Іменований мусить бути ЦІЛИМ токеном (`(?<![a-z])…(?![a-z])`), інакше
    # `transparent` матчиться всередині домену `transparenttextures.com`, а `red`
    # — у хвості `:clusters_measured`. Виміряно обидва: наївний підрядок дає три
    # хибні позитиви на живому дереві, цілий токен — нуль.
    colour_in_brackets =
      /\#[0-9a-fA-F]{3,8}|(?:rgb|hsl|hwb|lab|lch|oklab|oklch|color-mix)a?\(|
       (?<![a-z])(?:#{named_colours})(?![a-z])/xi

    # Patterns that indicate a class slipped past gaia-token migration.
    raw_patterns = [
      # Один патерн замість чотирьох: носій × родина × шкала. Шкала — рівно 2–3
      # цифри (Tailwind має 50…950), тож `stroke-[3]` та `border-2` не зачіпає.
      /\b((?:#{carriers})-(?:white|black|(?:#{palette})-\d{2,3}))\b/,
      # [UI.3 (б)] Arbitrary-значення, що НЕСЕ колір. Дужка без кольору — законна утиліта.
      # ⚠️ Дужка з `url(` виключена свідомо: там колірне слово є частиною ШЛЯХУ,
      # а не значенням (`bg-[url('…transparenttextures.com…')]`).
      /(\b(?:#{carriers})-\[(?![^\]]*url\()[^\]]*(?:#{colour_in_brackets})[^\]]*\])/
    ]

    # Decorative / brand allowlist — these are intentional and not migrated.
    # ⚠️ Порядок несучий для префікс-пар: довший рядок мусить скрабитись ПЕРШИМ,
    # інакше `bg-emerald-500` зʼїв би префікс свого `/10`-сусіда й лишив хвіст.
    allowlist = [
      "bg-emerald-500/10",  # login submit brand glow
      "bg-emerald-500/20",  # brand glow (parcel of the /10 pair)
      # [UI.1 сигнальна хвиля 2026-08-20] Голий `bg-emerald-500` ЗНЯТО: всі
      # сигнальні крапки/LED мігровано на `bg-gaia-primary-strong` (у темній
      # byte-той-самий #10b981, у світлій 4.98+ проти 2.43 у сирого), тож запис
      # відмивав би лише НОВІ регресії. Тіні-glow лишаються hex-парами акцентів:
      # тінь — не текст і не сигнал, 1.4.3/1.4.11 її не судять (§16.4), а
      # радіуси зведено до ЄДИНОГО 8px — саме щоб реєстр не ріс переліком форм.
      "border-emerald-500/20", # spinner ring
      # watermark `/5` (15 сайтів, деліберейт 1.09:1 — реєстр декорацій `contrast_audit`)
      "text-emerald-900/5",      # decorative watermarks (declared, aria-hidden)
      "shadow-[0_0_8px_#10b981]", # status-LED brand glow (здорова гілка пари)
      "shadow-[0_0_8px_#ef4444]"  # alert-LED glow (тривожна гілка тієї ж пари)
    ]

    violations = []
    scanned = 0
    paths.each do |path|
      next unless path.extname == ".rb"
      next unless path.exist?

      scanned += 1
      path.each_line.with_index(1) do |line, lineno|
        # Проза — не розмітка: повнорядковий коментар пояснює дефект і мусить мати
        # право назвати клас, яким той написаний. Межа вузька СВІДОМО — див. шапку.
        next if line =~ /\A\s*#/

        # Strip allowlisted brand tokens before scanning.
        scrubbed = line.dup
        allowlist.each { |a| scrubbed.gsub!(a, "") }

        raw_patterns.each do |re|
          scrubbed.scan(re).each do |hit|
            klass = hit.is_a?(Array) ? hit.compact.first : hit
            violations << { file: path.to_s, line: lineno, klass: klass }
          end
        end
      end
    end

    # [DOC-T.64] Population lantern. A green verdict is a claim about the files that
    # were READ — and a mistyped or space-separated `LINT_SCOPE=` yields a Pathname
    # that is neither a directory nor an existing file, so the loop above scanned
    # nothing and the ✓ below would attest an empty set. The comment at the head of
    # this file has described that hole since it was written; describing is not
    # closing. Same shape as the `expect(scanned_files.size).to be > N` floor every
    # spec/quality gate carries.
    if scanned.zero?
      abort "✗ gaia:lint_tokens — НУЛЬ файлів прочитано (scope: #{ENV['LINT_SCOPE'] || 'app/views/shared/'}). " \
            "Вердикту немає: перевірка не бігла. LINT_SCOPE= бере ОДИН шлях."
    end

    if violations.empty?
      puts "✓ gaia:lint_tokens — no raw Tailwind colour utilities detected (#{scanned} files scanned)"
      next
    end

    puts "✗ gaia:lint_tokens — #{violations.size} raw Tailwind class(es) detected:"
    violations.group_by { |v| v[:file] }.each do |file, items|
      puts "  #{file}"
      items.each { |i| puts "    L#{i[:line]}: #{i[:klass]}" }
    end
    puts ""
    puts "Migrate via: bin/migrate-tailwind-tokens #{violations.first[:file]}"
    puts "Mapping reference: docs/04_04_Phlex_UI_and_Tailwind.md § 3.1"
    abort
  end
end
