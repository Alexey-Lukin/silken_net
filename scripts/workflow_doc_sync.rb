#!/usr/bin/env ruby
# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# Workflow↔doc parity gate for the CI inventory in 06_07 §1.
#
# ЧОМУ. `06_07 §1` є рукописним реєстром усіх воркфлоу, і воно гниє
# ОДНОНАПРАВЛЕНО: новий `.github/workflows/*.yml` рядка тут не дістає сам.
# Виміряно 2026-09-08 (DOC-T.103): док документував 21 із 22 — бракувало
# `dco.yml`, і сам той файл при цьому ЗАЯВЛЯВ `06_07 §1` своїм інвентарним
# домом («# Canon: … CI inventory = 06_07 §1»). Тобто реф стояв, дому не було,
# і не червоніло ніщо.
#
# ⛔ ЧОМУ ЦЬОГО НЕ ЛОВИВ НАЯВНИЙ ГЕЙТ. `workflow_gate_perimeter.rb` судить
# ІНШУ вісь — required-множину branch-protection — і `06_07` не читає жодного
# разу (згадки там лише в коментарях). Дві осі свідомо роз'єднані: одна питає
# «чи цей чек обовʼязковий для merge», друга — «чи він узагалі описаний».
#
# ЩО ЕНФОРСИТЬСЯ, обидва напрямки:
#   A. кожен `.github/workflows/*.yml` має рядок у `06_07 §1`;
#   B. кожне імʼя воркфлоу, назване в §1, існує на диску (ретирований із живим
#      рядком = RED, бо мертвий рядок читається як чинний інвентар).
#
# ⛔ ОГОЛОШЕНА СТЕЛЯ, і вона не косметична: гейт судить НАЯВНІСТЬ рядка, ніколи
# його ПРАВДИВІСТЬ. Опис тригера чи призначення може розійтись із самим yml, і
# тут не почервоніє нічого — це лишається ручною віссю (`00_05 §4`, свіп по
# ЗНАЧЕННЮ). Розширювати гейт на зміст означало б парсити `on:`-блоки, і ціна
# цього виміряна не була.
#
# ⚠️ Периметр §1 — ТРИ таблиці (quality gates · deploy · repo governance), тож
# рядок приймається в БУДЬ-ЯКІЙ: вимагати конкретну означало б гейтувати
# редакційне рішення, а не інвентар.
#
# Pure Ruby (no Rails / no bundle). Run: ruby scripts/workflow_doc_sync.rb
# Exit 0 = in sync; exit 1 = drift. Method/why → docs/00_06 §3.

ROOT   = File.expand_path("..", __dir__)
DOC    = File.join(ROOT, "docs/06_07_CICD_and_Runbook_Index.md")
WF_DIR = File.join(ROOT, ".github/workflows")

# 🔴 Підлога периметра: пін на порожній множині зелений завжди. Якщо парсер
# перестане бачити рядки (зміна форми таблиці, перейменування секції), гейт
# мусить впасти ГУЧНО, а не відрапортувати «все синхронно» над нулем.
ROW_FLOOR = 15

abort "workflow_doc_sync ✗ — немає #{DOC}" unless File.file?(DOC)
abort "workflow_doc_sync ✗ — немає #{WF_DIR}" unless Dir.exist?(WF_DIR)

lines = File.readlines(DOC)
s = lines.index { |l| l.start_with?("## ") && l.include?("CI/CD Workflows") }
abort "workflow_doc_sync ✗ — секцію «CI/CD Workflows» не знайдено в 06_07" unless s
e = ((s + 1)...lines.size).find { |i| lines[i].start_with?("## ") } || lines.size

documented = lines[s...e]
              .select { |l| l.start_with?("| `") }
              .filter_map { |l| l[/`([a-z0-9_.\-]+\.ya?ml)`/, 1] }
              .uniq
              .sort

on_disk = Dir[File.join(WF_DIR, "*.yml")].map { |f| File.basename(f) }.sort

errors = []
if documented.size < ROW_FLOOR
  errors << "ПЕРИМЕТР §1 СТИСНУВСЯ: розпарсено #{documented.size} воркфлоу-рядків, підлога #{ROW_FLOOR}. " \
            "Найімовірніше змінилась форма таблиці або заголовок секції — полагодь ПАРСЕР, не підлогу."
end

(on_disk - documented).each do |wf|
  errors << "#{wf} існує в .github/workflows/, але НЕ описаний у 06_07 §1 — " \
            "додай рядок у відповідну таблицю (quality / deploy / governance)"
end
(documented - on_disk).each do |wf|
  errors << "06_07 §1 описує #{wf}, якого на диску НЕМАЄ — мертвий рядок читається як чинний інвентар; " \
            "зніми його або познач ретированим"
end

if errors.empty?
  puts "workflow_doc_sync ✓ — 06_07 §1 ⟷ .github/workflows (#{on_disk.size} воркфлоу, обидва напрямки; " \
       "периметр: #{documented.size} рядків ≥ #{ROW_FLOOR})"
  exit 0
end

warn "workflow_doc_sync FAILED — 06_07 §1 розійшовся з .github/workflows/"
errors.each { |m| warn "  ✗ #{m}" }
exit 1
