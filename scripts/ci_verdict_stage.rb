#!/usr/bin/env ruby
# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# Verdict-stage classifier for the CI aggregates (OPS.47 · 06_07 §2 «Verdict-stage invariant»).
#
# ЧОМУ. Агрегат бачить лише `needs.<job>.result`, а GitHub пише `failure` для ТРЬОХ різних
# світів: (1) перевірка виконалась і сказала «ні»; (2) впав крок НАЛАШТУВАННЯ, і жодна
# перевірка не бігла (2026-11-09: micromamba-504 у `smoke` смуги In-silico надрукувала
# «ВПАЛО (вердикт є)»); (3) джоба не виконала жодного кроку — раннер не видано (OPS.23,
# друга форма). Дискримінатор `needs.*.result` цих світів не розрізняє за побудовою.
#
# ЩО РОБИТЬ. Читає JSON джоб ЦІЄЇ спроби запуску (Actions API, `…/attempts/{n}/jobs`) і для
# кожної джоби з `conclusion == failure` друкує ОДНУ анотацію з етапом. Кроки дає API, ЕТАП
# задає межа `BOUNDARY`, яку автор воркфлоу ставить у кожну гейтовану джобу:
#   · кроків немає                           → не стартувала — вердикту немає;
#   · першим не пройшов «Set up job»          → підготовка раннера чи екшенів — вердикту немає;
#   · першим не пройшов «Post …»/«Complete job» → перевірки пройшли, впав службовий крок;
#   · межа пройшла                           → вердикт є: впала перевірка після межі;
#   · межа є, але не пройшла                 → впало НАЛАШТУВАННЯ — вердикту немає;
#   · межі в джобі немає                     → етап НЕ РОЗМІЧЕНО — названо лише крок.
# «Вердикту немає» не означає «не наш дефект»: зламаний lock-файл, environment-файл, global.json
# чи gitlink сабмодуля падають ДО межі, тож повідомлення каже, коли це дефект діфу.
#
# 🔒 КОНТРАКТ: скрипт НІКОЛИ не змінює вердикт агрегату — завжди exit 0 (лише друкує), і
# агрегат кличе його ПІСЛЯ власного кроку вердикту (exit 1 на той час уже поставлено).
#
# ⛔ ОГОЛОШЕНА СТЕЛЯ:
#   · межу ставить автор воркфлоу: перевірка, поставлена ДО межі, читалася б налаштуванням —
#     і composite-екшен API бачить ОДНИМ кроком, тож до межі не можна ставити composite, що
#     виконує наш код (`setup-rails-test` тому не збирає Tailwind: та задача бутує застосунок).
#     Правило розмітки — 06_07 §2. Крок, що сам і качає інструмент, і перевіряє, стоїть ПІСЛЯ
#     межі — його збій читається вердиктом, тобто помилка тут іде в БЕЗПЕЧНИЙ бік.
#   · джоба без межі не класифікується, а лише називає крок — безпечний бік.
#   · API недоступний чи порожній → попередження «етап не визначено»; API показав менше
#     джоб із failure, ніж `needs` (env `NEEDS_JSON`) → попередження, без тверджень.
#   · імена джоб — з API (display name), а крок вердикту агрегату друкує ключі `needs`:
#     для джоби з власним `name:` вони різні.
#   · `cancelled` на рівні ДЖОБИ тут не розбирається — його називає крок агрегату (OPS.30).
#
# Usage:
#   ruby scripts/ci_verdict_stage.rb JOBS_JSON   # JSON-відповідь …/attempts/{n}/jobs
#   ruby scripts/ci_verdict_stage.rb --selftest
require "json"
require "tmpdir"

module CiVerdictStage
  BOUNDARY = "Verdict boundary — setup complete"
  PASSED = %w[success skipped].freeze
  NO_VERDICT = "НЕ СТАРТУВАЛО (вердикту НЕМАЄ)"
  DIFF_HINT = "Якщо діф чіпає залежності чи сабмодулі (lock-файл, environment-файл, global.json, gitlink) — " \
              "це дефект діфу; інакше — інфраструктура: re-run."

  module_function

  def load(path)
    JSON.parse(File.read(path, encoding: "UTF-8"))
  rescue StandardError
    {}
  end

  # Returns [annotations], each a [level, title, message] triple.
  def classify(payload, needs_failures = nil)
    jobs = payload.is_a?(Hash) ? Array(payload["jobs"]) : []
    return [ [ :warning, "ЕТАП НЕ ВИЗНАЧЕНО", "API запуску не віддав джоб — етап читай у лозі джоби." ] ] if jobs.empty?

    failed = jobs.select { |j| j["conclusion"] == "failure" }
    out = failed.map { |j| classify_job(j) }
    total = payload["total_count"].to_i
    out << [ :warning, "ЕТАП ЧАСТКОВО", "API віддав #{jobs.size} з #{total} джоб — решту читай у лозі." ] if total > jobs.size
    if needs_failures && needs_failures > failed.size
      out << [ :warning, "ЕТАП ЧАСТКОВО",
               "needs має #{needs_failures} джоб із failure, API показав #{failed.size} — решту читай у лозі." ]
    end
    out
  end

  def classify_job(job)
    name = job["name"].to_s
    steps = Array(job["steps"])
    if steps.empty?
      return [ :error, NO_VERDICT,
               "#{name} — джоба не виконала жодного кроку (раннер не видано або збій до першого кроку). " \
               "Інфраструктура: re-run." ]
    end

    bad = steps.find { |s| !s["conclusion"].nil? && !PASSED.include?(s["conclusion"]) }
    step = bad ? "«#{bad["name"]}»" : "(крок, що не пройшов, не знайдено)"
    bad_name = bad ? bad["name"].to_s : ""
    if bad_name == "Set up job"
      return [ :error, NO_VERDICT, "#{name} — не пройшов #{step} (підготовка раннера чи завантаження екшенів). #{DIFF_HINT}" ]
    end
    if bad_name.start_with?("Post ") || bad_name == "Complete job"
      return [ :error, "ВПАЛО (службовий крок)",
               "#{name} — перевірки пройшли, не пройшов службовий крок #{step}. Це не твердження про код." ]
    end

    boundary = steps.find { |s| s["name"] == BOUNDARY }
    if boundary.nil?
      [ :error, "ВПАЛО (етап не розмічено)",
        "#{name} — не пройшов крок #{step}; межі вердикту в джобі немає, тож чи є вердикт про код — читай лог." ]
    elsif boundary["conclusion"] == "success"
      [ :error, "ВПАЛО (вердикт є)", "#{name} — не пройшла перевірка на кроці #{step}." ]
    else
      [ :error, NO_VERDICT, "#{name} — не пройшло налаштування на кроці #{step}, до межі вердикту; перевірки не бігли. #{DIFF_HINT}" ]
    end
  end

  def needs_failures(env_json)
    return nil if env_json.to_s.strip.empty?

    JSON.parse(env_json).count { |_, v| v.is_a?(Hash) && v["result"] == "failure" }
  rescue StandardError
    nil
  end

  def emit(annotations, io = $stdout)
    annotations.each { |level, title, msg| io.puts "::#{level} title=#{title}::#{msg}" }
  end

  def selftest
    step = ->(n, c) { { "name" => n, "conclusion" => c } }
    job = ->(n, c, *s) { { "name" => n, "conclusion" => c, "steps" => s } }
    setup_fail = job.("smoke", "failure", step.("Set up job", "success"), step.("Set up silken_md conda env", "failure"),
                      step.(BOUNDARY, "skipped"), step.("L2 engine smoke test", "skipped"))
    check_fail = job.("smoke", "failure", step.("Set up silken_md conda env", "success"), step.(BOUNDARY, "success"),
                      step.("L2 engine smoke test", "failure"))
    step_timeout = job.("smoke", "failure", step.(BOUNDARY, "success"), step.("L2 engine smoke test", "cancelled"))
    post_fail = job.("lint", "failure", step.(BOUNDARY, "success"), step.("Lint code", "success"),
                     step.("Post Harden runner", "failure"))
    runner_prep = job.("test", "failure", step.("Set up job", "failure"), step.("Checkout code", "skipped")) # no boundary: the branch must stand alone
    unmarked = job.("lint", "failure", step.("Checkout code", "success"), step.("Lint code", "failure"))
    not_started = job.("test", "failure")
    green = job.("docs_check", "success", step.(BOUNDARY, "success"))
    running = { "name" => "In-silico passed", "conclusion" => nil, "steps" => [] }

    cases = {
      "setup failure → no verdict + diff hint" => [ setup_fail, NO_VERDICT, "дефект діфу" ],
      "check failure → verdict" => [ check_fail, "ВПАЛО (вердикт є)", "L2 engine smoke test" ],
      "step timeout after boundary → verdict, step named" => [ step_timeout, "ВПАЛО (вердикт є)", "L2 engine smoke test" ],
      "post-step failure → service step" => [ post_fail, "ВПАЛО (службовий крок)", "Post Harden runner" ],
      "Set up job failure → no verdict" => [ runner_prep, NO_VERDICT, "Set up job" ],
      "no boundary → unmarked, step named" => [ unmarked, "ВПАЛО (етап не розмічено)", "Lint code" ],
      "no steps → not started" => [ not_started, NO_VERDICT, "жодного кроку" ]
    }
    bad = []
    cases.each do |label, (j, title, needle)|
      got = classify("jobs" => [ j, green, running ], "total_count" => 3)
      bad << "#{label}: expected one annotation, got #{got.size}" unless got.size == 1
      _, t, m = got.first
      bad << "#{label}: title #{t.inspect}" unless t == title
      bad << "#{label}: message lacks #{needle.inspect}" unless m.to_s.include?(needle)
    end
    # The dangerous direction: a real check failure must NEVER read as «no verdict».
    [ check_fail, step_timeout ].each do |j|
      _, t, = classify("jobs" => [ j ])[0]
      bad << "check failure classified as no-verdict" if t.include?("НЕМАЄ")
    end
    bad << "green/running jobs produced annotations" unless classify("jobs" => [ green, running ], "total_count" => 2).empty?
    lvl, t, = classify({})[0]
    bad << "empty payload must warn" unless lvl == :warning && t == "ЕТАП НЕ ВИЗНАЧЕНО"
    bad << "partial page must warn" unless classify("jobs" => [ green ], "total_count" => 5).any? { |a| a[1] == "ЕТАП ЧАСТКОВО" }
    nf = needs_failures(JSON.generate("smoke" => { "result" => "failure" }, "lint" => { "result" => "failure" },
                                      "changes" => { "result" => "success" }))
    bad << "needs_failures counted #{nf.inspect}, expected 2" unless nf == 2
    bad << "needs mismatch must warn" unless classify({ "jobs" => [ check_fail ] }, 2).any? { |a| a[1] == "ЕТАП ЧАСТКОВО" }
    # The real parse path, under a non-UTF-8 default locale: the boundary name carries «—».
    old = Encoding.default_external
    begin
      Encoding.default_external = Encoding::US_ASCII
      Dir.mktmpdir do |d|
        f = File.join(d, "jobs.json")
        File.write(f, JSON.generate("jobs" => [ setup_fail ], "total_count" => 1), encoding: "UTF-8")
        _, t, = classify(load(f))[0]
        bad << "parse under US-ASCII locale lost the payload (got #{t.inspect})" unless t == NO_VERDICT
      end
    ensure
      Encoding.default_external = old
    end

    if bad.empty?
      puts "✅ ci_verdict_stage selftest — #{cases.size + 7} cases green"
      true
    else
      bad.each { |b| warn "❌ #{b}" }
      false
    end
  end
end

if $PROGRAM_NAME == __FILE__
  exit(CiVerdictStage.selftest ? 0 : 1) if ARGV.first == "--selftest"
  payload = CiVerdictStage.load(ARGV.fetch(0, ""))
  CiVerdictStage.emit(CiVerdictStage.classify(payload, CiVerdictStage.needs_failures(ENV.fetch("NEEDS_JSON", nil))))
  exit 0
end
