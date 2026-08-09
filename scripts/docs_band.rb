#!/usr/bin/env ruby
# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

#
# scripts/docs_band.rb — ПОВНА локальна смуга `CI · Docs` (OPS.25).
#
# ЧОМУ ВОНА ІСНУЄ. `scripts/docs_check.rb` ганяє ДВА кроки джоби `docs_check`
# (`docs:check_refs` + `tracker:check`) за 0.3 с — і цього досить рівно доти,
# доки читач не прочитає його зелене як вердикт про СМУГУ. Саме так `main`
# ставав червоним тричі; вимір щоразу був чесний, просто міряв меншу множину,
# ніж читач вирішив. Клас-дім — памʼять `feedback_measurement_substitution`
# («цитуй гейт лише на класі, який він реально ловить»).
#
# ПЕРЕЛІК КРОКІВ НЕ ХАРДКОДИТЬСЯ — він читається з `.github/workflows/docs.yml`
# (`jobs.docs_check.steps[].run`). Список-за-прикладом протухає за побудовою
# (DOC-T.64), а сторож, що виводить множину з того самого джерела, яким її
# визначає CI, розійтися з нею не може.
#
# NOT-RUN ⊥ FAILED — класифікація ДО запуску, НЕ з exit-коду.
# Виміряно: 127 віддає лише відсутній БІНАРНИК; відсутній гем, невідповідний
# мажор Ruby, скрипт, що не парситься, `LoadError -- rake` — усі дають **1**,
# байт-у-байт як справжнє порушення. Тож придатність кожного кроку
# перевіряється пробою ФІЧІ, якої він потребує (резолв інтерпретатора →
# `ruby -c` над самим файлом → `bundle check` для bundle-залежних), а exit-код
# читається лише як PASS/FAIL. Це припис `ssot-maintenance` §Guard-craft #47:
# вартовий питає не «чи бінарник існує», а «чи він здатен виконати ЦЮ перевірку».
#
# ⛔ ОГОЛОШЕНІ СТЕЛІ (гейт без названої стелі перетворює зелене на «не перевірено»):
#   1. NOT-RUN детектується на МЕЖІ кроку, ніколи ВСЕРЕДИНІ. Крок, що стартував,
#      зробив половину перевірок і вмер, для смуги виглядає як FAIL — а якщо він
#      сам ковтає власну непридатність, то й як PASS. Це не лікується звідси:
#      ліхтар усередині кроку — обовʼязок самого кроку.
#   2. 🔴 `spdx_headers.rb` перелічує файли через `git ls-files`, тобто через
#      ІНДЕКС. Новий, ще не `git add`-нутий файл для нього НЕВИДИМИЙ — і саме
#      таким був інцидент 2026-08-09. Тому смуга ВИМАГАЄ, щоб робоче дерево не
#      мало untracked-файлів у in-scope теках, і червоніє, якщо має: інакше вона
#      друкує зелене на дереві, яке покладе CI.
#   3. `bin/rspec`-крок перезаписує локальний `coverage/` ≈0%-звітом (SimpleCov
#      стартує безумовно; `COVERAGE=0` лише знімає поріг). Артефакт gitignored,
#      але якщо тобі потрібен свіжий звіт покриття — зроби його ПІСЛЯ смуги.
#   4. Смуга виконує довільні `run:`-рядки з `docs.yml`. На своїй гілці це те
#      саме, що набрати їх руками; на ЧУЖІЙ — ні. Не ганяй її на неперевіреному
#      діфі workflow.
#
# Usage:
#   ruby scripts/docs_band.rb           # повна смуга (~1.5 хв)
#   ruby scripts/docs_band.rb --list    # лише перелік кроків + придатність
#

require "yaml"
require "shellwords"

ROOT = File.expand_path("..", __dir__)
WORKFLOW = File.join(ROOT, ".github", "workflows", "docs.yml")
JOB = "docs_check"

# ── перелік кроків із CI-джерела ─────────────────────────────────────────────
# ⚠️ Ключ `on:` у GitHub-YAML парситься як TrueClass (YAML 1.1 «Norway»), тож
# ніколи не адресуй тригери рядком "on" — тут ми читаємо лише `jobs`.
def band_steps
  doc = YAML.load_file(WORKFLOW, aliases: true)
  job = doc.dig("jobs", JOB) or abort("docs_band: у #{WORKFLOW} немає джоби `#{JOB}`")
  steps = job.fetch("steps").select { |s| s["run"] }
  abort("docs_band: джоба `#{JOB}` не має жодного run-кроку — парсер зламався") if steps.empty?
  steps
end

# ── придатність: проба ФІЧІ, не наявності ───────────────────────────────────
BUNDLE_CMDS = %w[bin/rails bin/rspec bundle].freeze

def bundle_ok?
  @bundle_ok = system("bundle", "check", out: File::NULL, err: File::NULL) if @bundle_ok.nil?
  @bundle_ok
end

# Повертає nil, якщо крок придатний; інакше — рядок-причину NOT-RUN.
def unfit_reason(cmd)
  # ENV-префікси (`COVERAGE=0 bin/rspec …`) не є командою.
  words = Shellwords.split(cmd.lines.first.to_s.strip)
  words.shift while words.first&.match?(/\A[A-Z_][A-Z0-9_]*=/)
  bin = words.first
  return "порожній крок" if bin.nil?

  exe = bin.include?("/") ? File.join(ROOT, bin) : bin
  if bin.include?("/")
    return "немає файлу #{bin}" unless File.exist?(exe)
  else
    return "бінарник `#{bin}` не резолвиться" unless system("command", "-v", bin, out: File::NULL, err: File::NULL) ||
                                                    system("sh", "-c", "command -v #{bin.shellescape}", out: File::NULL, err: File::NULL)
  end

  # ruby-скрипт: чи ЦЕЙ інтерпретатор його розбирає (той самий клас, що DOC-T.64:
  # «ruby є, але не той» — PATH на знятий gemset давав macOS 2.6).
  if bin == "ruby" && (script = words[1]) && File.exist?(File.join(ROOT, script))
    ok = system("ruby", "-c", File.join(ROOT, script), out: File::NULL, err: File::NULL)
    return "ruby не парсить #{script} (не той інтерпретатор?)" unless ok
  end

  return "bundle check провалився (гемів немає)" if BUNDLE_CMDS.include?(bin) && !bundle_ok?

  nil
end

# ── ліхтар дерева: untracked ламає spdx-крок мовчки (стеля 2) ───────────────
def untracked_in_scope
  out = IO.popen([ "git", "-C", ROOT, "ls-files", "--others", "--exclude-standard" ], &:read)
  # git мовчки віддає порожньо при `dubious ownership` — порожній перелік тоді
  # означав би «untracked немає», тобто ліхтар світив би зелене на власній сліпоті.
  abort("docs_band: `git ls-files --others` провалився — ліхтар untracked сліпий") unless $?.success?

  out.split("\n").grep(%r{\A(app|lib|scripts|spec|tools|firmware|contracts|docs|\.claude|\.github)/})
end

steps = band_steps
list_only = ARGV.include?("--list")

puts "смуга `CI · Docs` — #{steps.size} run-кроків із #{File.basename(WORKFLOW)} (джоба `#{JOB}`)"

untracked = untracked_in_scope
unless untracked.empty?
  warn "\n::error::docs_band: #{untracked.size} untracked-файл(ів) у in-scope теках — крок `spdx_headers` їх НЕ ПОБАЧИТЬ"
  untracked.first(10).each { |f| warn "  ? #{f}" }
  warn "  `git add` їх перед смугою, інакше вона зелена на дереві, яке покладе CI (стеля 2 в шапці)."
  exit 1 unless list_only
end

results = []
steps.each_with_index do |s, i|
  cmd = s["run"].strip
  name = (s["name"] || cmd.lines.first.strip)[0, 62]
  reason = unfit_reason(cmd)

  if list_only
    printf("%2d. %-64s %s\n", i + 1, name, reason ? "NOT-RUN — #{reason}" : "готовий")
    next
  end

  if reason
    printf("%2d. %-64s NOT-RUN\n", i + 1, name)
    warn "    ↳ #{reason}"
    results << [ :not_run, name, reason ]
    next
  end

  t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  ok = system(cmd, chdir: ROOT, out: File::NULL, err: File::NULL)
  ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000).round
  printf("%2d. %-64s %-7s %6dms\n", i + 1, name, ok ? "PASS" : "FAIL", ms)
  results << [ ok ? :pass : :fail, name, cmd ]
end

exit 0 if list_only

failed  = results.select { |r| r[0] == :fail }
not_run = results.select { |r| r[0] == :not_run }

puts
if failed.empty? && not_run.empty?
  puts "✅ смуга зелена — #{results.size}/#{steps.size} кроків ВИКОНАЛИСЬ і пройшли"
  exit 0
end

# Порожній набір знахідок = «чисто» ЛИШЕ якщо кожна перевірка виконалась
# (§Guard-craft #47). Тому NOT-RUN червонить нарівні з FAIL.
failed.each  { |_, name, cmd| warn "::error::FAIL    #{name}\n          → #{cmd.lines.first.strip}" }
not_run.each { |_, name, why| warn "::error::NOT-RUN #{name}\n          → #{why} (перевірка НЕ бігла — це не «чисто»)" }
warn "\nсмуга ЧЕРВОНА: #{failed.size} впало · #{not_run.size} не бігло · #{results.count { |r| r[0] == :pass }} пройшло"
exit 1
