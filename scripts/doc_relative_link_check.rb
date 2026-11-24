#!/usr/bin/env ruby
# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

#
# [DOC-T.131] Відносний лінк із `docs/**` на файл мусить резолвитись (HARD, docs.yml).
#
# Дірку дали два окремо ПРАВИЛЬНІ периметри (§Guard-craft #110): `docs:check_refs` судить лише
# голі канон-лінки `(NN_NN_Name)` верхніх `docs/*.md`, а `protocols_ref_check` — лише канон-лінки
# `../…` з `docs/protocols/**` і в шапці оголошує решту лінків підкаталогу «out of scope by design».
# Аркуш, лист, кеш, скрипт чи конфіг, на який шле `docs/**`, не судив ніхто: видалений файл лишав
# лінки на себе зеленими.
#
# ⚖️ Присуд — founder 2026-11-24: «Гейт HARD (Recommended)», тобто рекомендація машини, обрана
# з закритого списку «гейт · прилад on-demand · відмова».
# Підстава — вимір того ж дня на коміті 3e9887f08 по всіх відстежених `docs/**/*.md`: 9 кандидатів,
# усі 9 мертві в перегляді репо (4 — і у вікі; 5 шляхів від кореня репо у верхньому доці вікі
# дотягувала fallback-ом), полагоджені комітом, що й завів гейт; межа з сусідами, виправлена за
# другим адверсаром, додала 42 голі канон-лінки `SECURITY_ASSURANCE_CASE.md` (переведені на `.md` тим
# самим комітом), тож цей двигун на 3e9887f08 дає 51. Позитивний контроль — блок видалення Б1:
# тексти `55acdd87d^` на наборі файлів `55acdd87d` (видалені Б1 файли знято з індексу worktree) —
# цей двигун дає 250 порушень, з них давніх (мертвих і до Б1) — 51, тож сам блок — 199 (у поданні
# стояло 203: прилад-попередник рахував 4 давні лінки як частину Б1 і не рахував 5 шляхів від
# кореня). Детектор уже існував, але не годився: `wiki:sync` друкує «links left untouched» і
# виходить з кодом 0 (§Guard-craft #10), бачить лише канон-сторінки, біжить уже після злиття й
# несе два постійні хибні позитиви. Ціна: один крок смуги, рядок `00_06 §3.4`, ця шапка й спека
# на супровід. Найслабша ланка: (а) строгість — шлях від кореня репо без `/` у верхньому
# `docs/*.md` заборонено, хоч вікі його дотягує; (б) парсер регулярний, не Markdown.
#
# Семантика — ПЕРЕГЛЯД РЕПО: ціль береться відносно каталогу файлу (`/x` — від кореня репо) і
# шукається в `git ls-files` (не у файловій системі — §Guard-craft #48/#157): файл, каталог,
# корінь репо або шлях усередині субмодуля. Канон-слаг без `.md` приймається, якщо `.md` існує, —
# лише в лінку з вікі-сторінки `docs/NN_NN_*.md`: у перегляді репо такий лінк — 404 звідусіль
# (зонд 2026-11-24, позитивний контроль — та сама адреса з `.md` дає 200), і з вікі-сторінки його
# оживляє лише вікі-копія `wiki:sync` — тут гейт свідомо бере вікі-семантику.
# З нормалізатором `wiki:sync` на канон-сторінках на день присуду розходжень немає; за побудовою
# вони розходяться — серед іншого, перелік не вичерпний, — на вмісті субмодуля, %-кодуванні,
# `?запиті`, `<…>`, вкладених дужках мітки, змішаних fence, канон-слагу з чужим каталогом,
# fallback-ах нормалізатора й схемах на кшталт `ftp:` чи `//host`; `docs/protocols/**` вікі не
# публікує взагалі.
#
# Друга вісь — проти декоративності (§Guard-craft #1): кожна резолвлена ціль мусить стояти під
# фільтром `changes` у `docs.yml`, інакше PR, що лише видаляє ціль, цього кроку не запускає.
# Конверсія glob → regex — копія осі D2 `guard_registry_sync` (дві копії; `?`, `{}`, `!` не знає
# жодна).
#
# Предмет сусідів — рівно дві форми канон-лінка БЕЗ прикрас (`<…>`, пробіли, титул: регекси сусідів
# вимагають `](` одразу перед слагом і `)` одразу після), і тут вони не судяться (один гейт — одна
# річ): голий `NN_NN_Name[#…]` у вікі-сторінці `docs/NN_NN_*.md` (`docs:check_refs`) і `../…NN_NN_Name[.md][#…]`
# у `docs/protocols/**` (`protocols_ref_check`). Будь-яка інша форма — предмет цього гейта.
# Голий слаг у верхньому НЕ-вікі доці `check_refs` судить лише за ІМЕНЕМ доку, а GitHub без `.md`
# дає 404 — тож його судить і цей гейт (⚖️ founder 2026-11-24, виняток форми — `00_06 §1`; 42 лінки
# `SECURITY_ASSURANCE_CASE.md` переведено на `.md`). ⚠️ `../…NN_NN_Name` без `.md` у protocols лишається
# формою сусіда, який судить за ІМЕНЕМ: на GitHub це 404, і її не судить ніхто; на день присуду таких
# нуль (вісім полагоджено комітом гейта — стандарт шару вимагає `.md`).
#
# ⚠️ Оголошена стеля — що цей гейт НЕ бачить або бачить хибно:
#   • лише вбудовані `[…](…)` і `![…](…)`; посилань-визначень `[x]: шлях` і HTML-лінків у корпусі
#     на день присуду нуль — зʼявиться форма, гейт треба вчити, не послаблювати;
#   • невидимі: титул у `'…'` чи `(…)`, `<шлях із пробілом>`, ціль лінка-обгортки `[![…](…)](ціль)`,
#     лінк чи code-span, розірвані переносом рядка;
#   • `)` усередині href обрізає його на першій дужці — хибне червоне, не сліпота;
#   • code-span вирізається ДО скану (як рендерить CommonMark) — ширше за `WikiLinkNormalizer`, що
#     пропускає лише лінк, цілком вкладений в один span; звідси його два хибні `(…)`;
#   • fence закриває лише той самий символ; незакритий на кінці файлу — порушення (інакше решта
#     файлу мовчки не сканувалась би: `unbalanced_code_fences` бачить лише ``` з нульової колонки);
#     fence усередині цитати (`> ```) fence-ом не вважається — її вміст сканується;
#   • `#фрагмент` не перевіряється на жодній цілі, яку судить цей гейт;
#   • `../…NN_NN_Name` без `.md` у protocols — форма сусіда, який судить за ІМЕНЕМ доку: на GitHub
#     це 404, і її не судить ніхто (на день присуду таких нуль — абзац «Предмет сусідів»);
#   • вміст субмодуля приймається за префіксом: `actions/checkout` його не тягне, а GitHub у
#     перегляді батьківського репо такого файлу теж не відкриває — лінк свідчить лише про субмодуль;
#   • нижньої межі на кількість лінків свідомо немає: кампанія видалень законно її знижує
#     (§Guard-craft #138);
#   • периметр — лише `docs/**`: вбудовані відносні лінки поза ним (корінь, `tools/`, `firmware/`,
#     `.claude/`) не судить ніхто — `claude_prose_path_refs_spec` судить шляхи в бектиках, не лінки.
#
# Pure Ruby, без Rails і без bundle. Запуск із кореня: `ruby scripts/doc_relative_link_check.rb`.
require "set"
require "uri"
require "yaml"

module DocRelativeLinkCheck
  LINK = /!?\[(?:[^\[\]]|\[[^\[\]]*\])*\]\(\s*<?([^)\s>]+)>?(?:\s+"[^"]*")?\s*\)/
  CODE_SPAN = /(`+).*?\1/
  FENCE = /\A\s*(```|~~~)/
  SCHEME = %r{\A(?:[a-z][a-z0-9+.-]*:|//)}i
  SLUG = /\d\d_\d\d_[A-Za-z0-9_]+/
  TOP_CANON = /\A#{SLUG}(?:#.*)?\z/                           # docs:check_refs
  PROTOCOLS_CANON = %r{\A(?:\.\./)+#{SLUG}(?:\.md)?(?:#.*)?\z} # protocols_ref_check
  WIKI_PAGE = %r{\Adocs/\d\d_\d\d_[^/]+\.md\z}                  # canon_glob у wiki.rake

  module_function

  # Hrefs поза fence і code-span, крім схеми, `//` і чистого якоря: [[рядок, href, прикрашений?], …].
  def relative_hrefs(text) = walk(text).first

  # [hrefs, рядок незакритого fence або nil]. «Прикрашений» — href у `<…>`, з пробілами чи титулом.
  def walk(text)
    fence = fence_line = nil
    hrefs = text.each_line.with_index(1).flat_map do |line, ln|
      if (m = line.match(FENCE))
        if fence.nil? then fence, fence_line = m[1], ln
        elsif fence == m[1] then fence = nil
        end
        next []
      end
      next [] if fence

      line.gsub(CODE_SPAN) { |s| " " * s.size }.to_enum(:scan, LINK).filter_map do
        md = Regexp.last_match
        href = md[1]
        [ ln, href, !md[0].end_with?("](#{href})") ] unless href.match?(SCHEME) || href.start_with?("#")
      end
    end
    [ hrefs, fence && fence_line ]
  end

  # Чи судить цю форму сусідній гейт (тоді тут вона не предмет). Прикрашену — не судить жоден.
  def neighbour_form?(path, href, decorated = false)
    return false if decorated

    top = path.match?(WIKI_PAGE)
    (top && href.match?(TOP_CANON)) || (path.start_with?("docs/protocols/") && href.match?(PROTOCOLS_CANON))
  end

  # Шлях репо, на який веде href із файлу `path` ("" — корінь), або nil (ціль поза репо).
  def resolve(path, href)
    target = href.split("#", 2).first.split("?", 2).first
    target = URI.decode_www_form_component(target.gsub("+", "%2B")) rescue target
    base = target.start_with?("/") ? target : File.join(File.dirname(path), target)
    parts = []
    base.split("/").each do |seg|
      next if seg.empty? || seg == "."
      return nil if seg == ".." && parts.empty?

      seg == ".." ? parts.pop : parts << seg
    end
    parts.join("/")
  end

  def filter_regexps(globs)
    globs.map do |g|
      re = Regexp.escape(g).gsub('\*\*', "DOUBLESTAR").gsub('\*', "[^/]*").gsub("DOUBLESTAR", ".*")
      Regexp.new("\\A#{re}\\z")
    end
  end

  # tree: { files: Set, dirs: Set, submodules: [шляхи] }; filter: [Regexp] або nil.
  def violations(path, text, tree, filter: nil)
    hrefs, open_fence = walk(text)
    found = hrefs.filter_map do |ln, href, decorated|
      next if neighbour_form?(path, href, decorated)

      target = resolve(path, href)
      next "#{path}:#{ln}: `#{href}` веде за межі репозиторію" if target.nil?
      next if target.empty? # корінь репо

      if path.match?(WIKI_PAGE) && File.basename(target).match?(/\A#{SLUG}\z/) && tree[:files].include?("#{target}.md")
        target = "#{target}.md"
      end
      dir = tree[:dirs].include?(target)
      live = dir || tree[:files].include?(target)
      inside_sub = tree[:submodules].any? { |s| target == s || target.start_with?("#{s}/") }
      next "#{path}:#{ln}: мертвий лінк `#{href}` → `#{target}` (немає в git ls-files)" unless live || inside_sub

      probe = dir ? "#{target}/_" : target
      if filter && filter.none? { |re| re.match?(probe) }
        "#{path}:#{ln}: ціль `#{target}` поза фільтром `changes` у docs.yml — видалення цілі " \
          "цього кроку не запустить (додай її корінь у фільтр)"
      end
    end
    found << "#{path}:#{open_fence}: незакритий fence — решта файлу не сканувалась" if open_fence
    found
  end

  def tree_from_git(root)
    files = IO.popen([ "git", "-C", root, "ls-files", "-z" ], &:read).split("\0").to_set
    dirs = Set.new
    files.each do |f|
      d = File.dirname(f)
      d = File.dirname(d) while d != "." && dirs.add?(d)
    end
    stage = IO.popen([ "git", "-C", root, "ls-files", "-s" ], &:read)
    submodules = stage.lines.filter_map { |l| l.split(/\s+/, 4)[3]&.strip if l.start_with?("160000") }
    { files: files, dirs: dirs, submodules: submodules }
  end

  def changes_filter(root)
    wf = YAML.safe_load_file(File.join(root, ".github/workflows/docs.yml"), aliases: true)
    raw = (wf.dig("jobs", "changes", "steps") || []).filter_map { |s| s.dig("with", "filters") }.first
    raise "docs.yml: не знайдено фільтра changes" if raw.nil?

    filter_regexps(YAML.safe_load(raw).fetch("docs"))
  end
end

if $PROGRAM_NAME == __FILE__
  root = File.expand_path("..", __dir__)
  tree = DocRelativeLinkCheck.tree_from_git(root)
  filter = DocRelativeLinkCheck.changes_filter(root)
  docs = tree[:files].select { |f| f.start_with?("docs/") && f.end_with?(".md") }.sort
  abort "doc_relative_link_check: git ls-files не дав жодного docs/**/*.md — прилад сліпий" if docs.empty?

  judged = 0
  found = docs.flat_map do |f|
    text = File.read(File.join(root, f), encoding: "UTF-8")
    judged += DocRelativeLinkCheck.relative_hrefs(text).count { |_, h, d| !DocRelativeLinkCheck.neighbour_form?(f, h, d) }
    DocRelativeLinkCheck.violations(f, text, tree, filter: filter)
  end

  if found.empty?
    puts "doc_relative_link_check — #{docs.size} файлів, #{judged} відносних лінків поза формами сусідів; усі резолвляться ✓"
  else
    puts "doc_relative_link_check — порушень: #{found.size}"
    found.each { |v| puts "  ✗ #{v}" }
    puts "Лагодь ціль або href; ілюстрацію форми бери в code-span."
    exit 1
  end
end
