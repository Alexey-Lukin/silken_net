# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require Rails.root.join("lib/silken_net/contrast")

# Браузерний ЗБИРАЧ пар «текст ⟷ поверхня» (`00_07` UI.3).
#
# Розподіл праці дзеркалить наявні гейти репо: арифметика — `lib/silken_net/
# contrast.rb` (pure Ruby, власний unit-спек), тут — рівно збирання.
#
# ⚠️ Реєстр сторінок як окремий ДОКУМЕНТ (`spec/support/contrast_registry.rb`,
# форма `browser_contour_registry`) ще НЕ існує — перелік поки хардкодом у
# споживачі. Він народиться разом із гейтом, і не раніше: реєстр винятків, що
# випереджає лік кореневих токенів, був би довшим за реєстр сторінок.
#
# 🧱 Чому шар браузерний, хоч коштує на два порядки дорожче (`04_06 §B.1.4`,
# критерій належності): пара fg/bg майже завжди живе в РІЗНИХ файлах — поверхню
# дає батьківський компонент або `<body>`. Це не думка: шапка
# `spec/quality/design_token_existence_spec.rb` сама оголошує контраст віссю,
# недосяжною їй за побудовою.
#
# ── ТАКСОНОМІЯ: кожен текстовий вузол потрапляє РІВНО в один кошик ──
#
# Плаский лічильник «пропущено» тут був би дефектом того самого класу, який
# прилад ловить: «не подивився» мусить бути відрізнимим від «порушень немає».
#
#   1. MEASURED    — пара розв'язана, число є.
#   2. EXCLUDED    — вузол законно поза вимогою 1.4.3: не рендериться взагалі,
#                    або це disabled-контрол (нормативний виняток «inactive
#                    user interface component»).
#   3. UNMEASURABLE — вузол ВИДИМИЙ, але пари під ним не існує як суцільних
#                    кольорів: градієнт/зображення/blend/filter під текстом,
#                    opacity-група, SVG-текст (фарбує `fill`, не `color`),
#                    колір у формі, якої двигун не читає (`oklab`, `color-mix`).
#                    🔴 Це НЕ «пройшло» — це відмова міряти, і вона гучна.
#
# ⚠️ Кошиків РІВНО ТРИ, і четвертого тут свідомо немає. Перша редакція цієї
# шапки оголошувала «UNVISITED — стани, яких статичний знімок не має» четвертим
# кошиком «з завжди ненульовим лічильником»; у коді його не існувало жодного
# разу. Це рівно той клас, який гейти цього репо ловлять під іменем «гейт
# під-імплементує контракт, який сам оголосив», — тож замість дописати мертвий
# ключ, заява знята: невідвідані стани порахувати НЕМОЖЛИВО за побудовою, бо
# щоб їх порахувати, треба їх відвідати. Вони живуть у стелі нижче, як стеля.
#
# 🔒 Стеля — чесно й поіменно; зелений НЕ означає «сторінка доступна»:
#   · `::before`/`::after` (у нас це мобільні мітки таблиць, `td::before`
#     `content: attr(data-label)`) — `TreeWalker` не бачить їх за побудовою.
#   · Перекриття (z-index): фон береться від ПРЕДКА, тож текст під чужим
#     оверлеєм дав би правдоподібне й неправильне число. Детектора немає.
#   · `text-shadow`/`-webkit-text-stroke` можуть і рятувати пару, і вбивати
#     (WCAG рахує вузьку обводку частиною літери, широкий ореол — фоном).
#   · Shadow DOM та `<iframe>` не перетинаються; у дереві їх нема, стеля — про
#     майбутнє.
#   · `aria-hidden` НЕ є підставою для відсіву: 1.4.3 — критерій ВІЗУАЛЬНИЙ, а
#     атрибут ховає від скрінрідера, не від ока. Декоративне (watermark)
#     виключається ЯВНОЮ декларацією в реєстрі, не автоматом.
#   · Один розмір вікна; мобільні брейкпойнти мають власну розмітку.
module ContrastAudit
  # Одна ВИМІРЯНА пара. Одиниця звіту — пара, а не вузол: 160+ текстових вузлів
  # сторінки дають десяток унікальних пар, і питання «що лагодити» ставиться
  # саме до пари.
  Pair = Struct.new(
    :colour, :backdrop, :font_size, :font_weight,
    :ratio, :threshold, :passes, :nodes, :sample_text, :sample_path,
    keyword_init: true
  )


  HARVEST_JS = <<~JS
    (() => {
      const buckets = { measured: 0, excluded: {}, unmeasurable: {} };
      const bump = (b, r) => { buckets[b][r] = (buckets[b][r] || 0) + 1; };
      const pairs = new Map();
      const TRANSPARENT = /^rgba\\(0,\\s*0,\\s*0,\\s*0\\)$/;

      // 🔴 Нормалізація кольору — БРАУЗЕРОМ, не нами. Tailwind v4 компілює
      // альфа-суфікс (`/80`) у `color-mix(in oklab, …)`, і Chrome серіалізує
      // результат У ПРОСТОРІ ІНТЕРПОЛЯЦІЇ: `oklab(0.163 -0.006 0.0001 / 0.8)`
      // (виміряно на нашому ж топ-барі). Писати власну конверсію OKLab→sRGB
      // означало б завести ДРУГИЙ двигун кольору, якого ніхто не звіряє;
      // canvas робить ту саму роботу рідним кодом рушія.
      // ⚠️ Наївний варіант `ctx.fillStyle = css; ctx.fillStyle` НЕ працює й був
      // виміряно відкинутий: з підтримкою CSS Color 4 Chrome повертає значення
      // В ТОМУ САМОМУ просторі (`oklch(…)` → `oklch(…)`), тож нормалізації не
      // відбувається. Надійна форма — намалювати піксель і ПРОЧИТАТИ його:
      // растр завжди sRGB, і це та сама відповідь, яку побачить око.
      const norm = (() => {
        const cv = document.createElement('canvas');
        cv.width = cv.height = 1;
        const ctx = cv.getContext('2d', { willReadFrequently: true });
        return (css) => {
          if (!css) return css;
          if (css.startsWith('rgb')) return css;      // вже sRGB — не чіпаємо
          ctx.clearRect(0, 0, 1, 1);
          ctx.globalCompositeOperation = 'copy';
          ctx.fillStyle = css;
          ctx.fillRect(0, 0, 1, 1);
          const d = ctx.getImageData(0, 0, 1, 1).data;
          const a = d[3] / 255;
          return a >= 1 ? `rgb(${d[0]}, ${d[1]}, ${d[2]})`
                        : `rgba(${d[0]}, ${d[1]}, ${d[2]}, ${a.toFixed(3)})`;
        };
      })();

      const cssPath = (el) => {
        const parts = [];
        for (let n = el; n && n.nodeType === 1 && parts.length < 4; n = n.parentElement) {
          let s = n.tagName.toLowerCase();
          if (n.id) { parts.unshift(s + '#' + n.id); break; }
          const cls = (typeof n.className === 'string' ? n.className : '').trim().split(/\\s+/)[0];
          if (cls) s += '.' + cls;
          parts.unshift(s);
        }
        return parts.join(' > ');
      };

      // Видимість перевіряємо ОДНИМ рідним механізмом, а не чорним списком
      // тегів: script/style/title/noscript мають `display:none` за UA-стилями,
      // тож список був би другим реєстром, який гниє окремо.
      const rendered = (el) => el.checkVisibility
        ? el.checkVisibility({ visibilityProperty: true, opacityProperty: true, contentVisibilityAuto: true })
        : (getComputedStyle(el).display !== 'none' && getComputedStyle(el).visibility !== 'hidden');

      const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
      let node;
      while ((node = walker.nextNode())) {
        if (!node.nodeValue.trim()) continue;           // whitespace — не вузол контенту
        const el = node.parentElement;
        if (!el) { bump('excluded', 'detached'); continue; }

        if (!rendered(el)) { bump('excluded', 'not_rendered'); continue; }

        // Текст, що не займає місця (sr-only через clip, нульові боксі).
        const range = document.createRange();
        range.selectNodeContents(node);
        const rects = Array.from(range.getClientRects());
        if (!rects.length || rects.every(r => r.width < 1 || r.height < 1)) {
          bump('excluded', 'zero_area'); continue;
        }

        // Нормативний виняток 1.4.3: inactive UI component.
        if (el.closest('[disabled], [aria-disabled="true"], fieldset[disabled]')) {
          bump('excluded', 'disabled'); continue;
        }

        // SVG красить `fill`, а не `color` — computed style тут описує не те,
        // що видно, і підкладкою є фігури-сибліни, яких обхід предків не бачить.
        if (el.ownerSVGElement || el.tagName === 'svg') { bump('unmeasurable', 'svg_text'); continue; }

        const cs = getComputedStyle(el);

        // Прозорість предка гасить ТЕКСТ І ФОН разом, і в computed style дитини
        // цього не видно (opacity не успадковується). Число тут було б завищене.
        let group = false, blended = false, filtered = false;
        for (let p = el; p && p !== document.documentElement; p = p.parentElement) {
          const pcs = getComputedStyle(p);
          if (parseFloat(pcs.opacity) < 1) { group = true; break; }
          if (pcs.mixBlendMode && pcs.mixBlendMode !== 'normal') { blended = true; break; }
          if (pcs.filter && pcs.filter !== 'none') { filtered = true; break; }
        }
        if (group)    { bump('unmeasurable', 'opacity_group'); continue; }
        if (blended)  { bump('unmeasurable', 'blended'); continue; }
        if (filtered) { bump('unmeasurable', 'filtered'); continue; }

        // Стек фонів знизу вгору. Напівпрозорі шари НАКОПИЧУЮТЬСЯ, а не
        // пропускаються: `bg-black/80` над білою панеллю — це не біла панель.
        const stack = [];
        let painted = false, resolved = false;
        for (let p = el; p; p = p.parentElement) {
          const pcs = getComputedStyle(p);
          if ((pcs.backgroundImage && pcs.backgroundImage !== 'none') ||
              (pcs.backdropFilter && pcs.backdropFilter !== 'none')) { painted = true; break; }
          const bg = norm(pcs.backgroundColor);
          if (!bg || bg === 'transparent' || TRANSPARENT.test(bg)) continue;
          stack.push(bg);
          const a = bg.startsWith('rgba') ? parseFloat(bg.split(',')[3]) : 1;
          if (a >= 1) { resolved = true; break; }
        }
        if (painted)   { bump('unmeasurable', 'painted_backdrop'); continue; }
        if (!resolved) { bump('unmeasurable', 'unresolved_backdrop'); continue; }

        const colour = norm(cs.color);
        const key = [colour, stack.join('|'), cs.fontSize, cs.fontWeight].join('~');
        const seen = pairs.get(key);
        if (seen) { seen.nodes += 1; buckets.measured += 1; continue; }
        buckets.measured += 1;
        pairs.set(key, {
          colour: colour, stack: stack,
          font_size: cs.fontSize, font_weight: cs.fontWeight,
          nodes: 1, sample_text: node.nodeValue.trim().slice(0, 60), sample_path: cssPath(el)
        });
      }

      return {
        pairs: Array.from(pairs.values()),
        buckets: buckets,
        os_dark: window.matchMedia('(prefers-color-scheme: dark)').matches,
        reduced_motion: window.matchMedia('(prefers-reduced-motion: reduce)').matches,
        // Ліхтар на ІДЕНТИЧНІСТЬ, не на кількість — див. пояснення в Ruby нижче.
        body_bg: norm(getComputedStyle(document.body).backgroundColor),
        surface_base_token: getComputedStyle(document.documentElement)
                              .getPropertyValue('--gaia-surface-base').trim()
      };
    })()
  JS

  # Очікуваний фон `<body>` у кожній темі — саме значення `--gaia-surface-base`
  # з `@theme`. Служить доказом, що стилі ДІЮТЬ, а не лише що вузли є.
  EXPECTED_BODY_BG = { dark: "rgb(5, 6, 7)", light: "rgb(250, 250, 250)" }.freeze

  # 🔴 Один важіль знімає джерела недетермінізму, і всі вони — рідні механізми
  # застосунку, а не наш хак поверх нього:
  #   · глобальний `@media (prefers-reduced-motion)` глушить CSS-анімації —
  #     інакше `animate-pulse` (легальний бренд-глоу, `04_04 §16.4`) робив би
  #     обчислену прозорість функцією МОМЕНТУ зчитування;
  #   · декоративних canvas-ефектів у дереві немає (matrix_rain знято — UI.1).
  # ⚠️ Тут доти стояла ТРЕТЯ підстава — appear-on-scroll-контролер, що при
  # reduce розкриває вузли одразу в `connect()`. Її знято разом із самим
  # контролером (UI.3): він мав нуль споживачів сьомий місяць. Важіль лишається
  # потрібним заради CSS-половини вище — тобто впала ПІДСТАВА, не рішення.
  # 🔴 І це не косметика коментаря: доки підстава посилалась на неіснуючого
  # споживача, вона читалась як доказ, що прилад бачить ширшу множину, ніж
  # бачить насправді.
  # Кольорів цей режим не міняє — перевірено в `application.css`.
  #
  # ⚠️ Доти тут стояв ДРУГИЙ важіль (`localStorage`), а ОС емулювалась у
  # ПРОТИЛЕЖНУ тему навмисно — щоб пін на клас міг упасти. Обидві половини тієї
  # конструкції зникли разом із тумблером: клієнтського стану теми не існує, а
  # клас `.dark` більше не бере участі в ланцюгу. Тепер емулюється РІВНО та
  # тема, яку просять, і вона ж є єдиним джерелом.
  def emulate_media(theme)
    page.driver.browser.page.command(
      "Emulation.setEmulatedMedia",
      features: [
        { name: "prefers-color-scheme", value: theme.to_s },
        { name: "prefers-reduced-motion", value: "reduce" }
      ]
    )
  end

  # Знімає сторінку в заданій темі й повертає ВИМІРЯНІ пари + повний облік.
  #
  # 🔴 Самосвідчення обов'язкове: приклад, що маніпулює середовищем поза
  # каналом, мусить пінити, що маніпуляція СПРАЦЮВАЛА — інакше при тихій
  # відмові він зелений на порожній множині, тобто атестує рівно той клас,
  # який мав ловити (`ssot-maintenance` §Mutation-verify).
  def harvest_contrast(path, theme:)
    emulate_media(theme)
    visit(path)
    expect(page).to have_css("body", wait: 5)

    # 🔴 Пін на ІДЕНТИЧНІСТЬ СТОРІНКИ, і він несучий: `render_forbidden`,
    # `render_not_found` і `render_internal_server_error` усі рендерять
    # `Errors::Page` всередині того самого лейауту (`base_controller`), тобто
    # 403/404/500 дають правильний `body_bg`, правильний `.dark` і правильний
    # `reduced_motion`. Без цього рядка всі три самосвідчення зелені, а число
    # приписане не тій сторінці — правдоподібно й неправильно.
    expect(page).to have_current_path(path, ignore_query: true),
                    "опинились на #{page.current_path} замість #{path} — ймовірно сторінка помилки, вимір недійсний"

    # 🔴 Пін вище ловить лише РЕДИРЕКТ, і доти цього рядка бракувало: `render_forbidden`
    # та `render_internal_server_error` рендерять `Errors::Page` **на тому самому
    # шляху**, тож `have_current_path` проходить зеленим над сторінкою помилки —
    # рівно над тими трьома випадками, заради яких сусідній пін і писався.
    # Виміряно, не виведено: probe на `/tree_families/new` (гейтований
    # `authorize_super_admin!`) віддав нуль пар цільового токена й ЗЕЛЕНИЙ шлях.
    expect(page.status_code).to eq(200),
                                "сторінка віддала #{page.status_code} — міряємо `Errors::Page`, а не #{path}"

    raw = page.evaluate_script(HARVEST_JS)

    expect(raw["reduced_motion"]).to be(true),
                                     "CDP-емуляція не спрацювала — рух не заморожено, вимір недетермінований"
    expect(raw["os_dark"]).to be(theme.to_sym == :dark),
                              "CDP не переставив `prefers-color-scheme` (маємо dark=#{raw['os_dark']}, просили #{theme}) — " \
                              "вимір недійсний. Після зняття тумблера це ЄДИНИЙ важіль теми, тож без цього піна " \
                              "весь звіт зелений на порожній множині"

    # 🔴 Ліхтар мусить пінити ІДЕНТИЧНІСТЬ, а не кількість вузлів, і причина
    # конкретна: `spec/support/layout_asset_stubs.rb` глушить asset-теги на
    # `Propshaft::MissingAssetError`. Сторінка тоді приїжджає БЕЗ Tailwind —
    # усе стає чорним на білому, тобто 21:1 на КОЖНОМУ вузлі при МАКСИМАЛЬНІЙ
    # популяції. Лічильник вузлів у такому світі показав би рекорд, а прилад
    # атестував би порожнечу. Пін на конкретний токен обійти нічим.
    expect(raw["body_bg"]).to eq(EXPECTED_BODY_BG.fetch(theme.to_sym)),
                             "фон `<body>` не дорівнює `--gaia-surface-base` теми #{theme} " \
                             "(маємо #{raw['body_bg'].inspect}) — стилі не діють, вимір недійсний"
    expect(raw["surface_base_token"]).to be_present,
                                         "змінна `--gaia-surface-base` не резолвиться — CSS не завантажено"

    measured = raw["pairs"].map { |p| measure_pair(p) }

    # 🔴 Пара, чий колір двигун не прочитав, НЕ є виміряною — а JS порахував її
    # у `measured` ще до того, як Ruby спробував розібрати рядок. Без цього
    # перенесення головна цифра звіту завищена рівно на непрочитані пари, а
    # причина невимірності зникає з обліку — тобто «не подивився» знову стає
    # невідрізнимим від «порушень немає».
    unreadable = measured.select { |p| p.ratio.nil? }
    if unreadable.any?
      nodes = unreadable.sum(&:nodes)
      raw["buckets"]["measured"] -= nodes
      raw["buckets"]["unmeasurable"]["unreadable_colour"] =
        raw["buckets"]["unmeasurable"].fetch("unreadable_colour", 0) + nodes
    end

    {
      pairs: measured,
      buckets: raw["buckets"],
      measured_nodes: raw["buckets"]["measured"]
    }
  end

  def measure_pair(raw)
    base = {
      colour: raw["colour"], backdrop: raw["stack"].join(" ← "),
      font_size: raw["font_size"], font_weight: raw["font_weight"],
      nodes: raw["nodes"], sample_text: raw["sample_text"], sample_path: raw["sample_path"]
    }

    surface = SilkenNet::Contrast.flatten_backdrop(raw["stack"])
    verdict = SilkenNet::Contrast.measure(
      text: raw["colour"], surface: format("rgb(%d, %d, %d)", *surface.map(&:round)),
      font_size_px: raw["font_size"].to_f, font_weight: raw["font_weight"]
    )

    Pair.new(**base, ratio: verdict[:ratio], threshold: verdict[:threshold], passes: verdict[:passes])
  rescue SilkenNet::Contrast::UnparseableColour
    # Колір у формі, якої двигун не читає (`oklab`, `color-mix`), — це НЕ
    # «пройшло». Пара лишається без вердикту й потрапляє у звіт окремо.
    Pair.new(**base, ratio: nil, threshold: nil, passes: nil)
  end
end

RSpec.configure do |config|
  config.include ContrastAudit, file_path: %r{spec/features/}
end
