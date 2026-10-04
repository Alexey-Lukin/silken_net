#!/usr/bin/env bash
# PreToolUse hook — SSOT discipline reminder, fired ONCE per session per class.
#
# Why PreToolUse and not PostToolUse (which is where most of the hook set sits
# — count them with `jq '.hooks' .claude/settings.json`, never from a number
# written here: this line said "our two other hooks" and was falsified a week
# later by two hooks landing in ANOTHER file): this one must
# land BEFORE the edit. A reminder that arrives after I have already collapsed a
# canon section is worth nothing — the damage is the edit itself.
#
# Why it carries what it carries: `docs_check.rb` catches every FORM violation
# THIS file can commit (DOC-T.15 line-refs, meta-line WHO, section-home, bare
# doc-ids) in 0.3s, HARD. Repeating those here would be noise. ⚠️ It is two
# steps of the lane, though — the hint text says so and points at
# `docs_band.rb`, because reading its green as a verdict about the whole Docs
# lane is exactly what reddened `main` three times (OPS.25). What no gate
# can see is a red line `item_cementation.md` itself flags as ungated (one of
# several — the sentence below already says "plus the ordering rule"): the
# zero-loss set-diff is grep-based, so a fact that is present-by-token but
# gutted-in-substance passes GREEN. That is the only thing worth interrupting
# for — plus the ordering rule, whose violations are invisible by construction.
#
# Once per session per class (canon vs tracker), keyed on session_id: a noisy
# advisory is a disabled gate — the same rule this repo applies to its linters.
# The two CONTENT branches below are the exception, and on purpose: each matches
# only the shape of one act, so it can fire every time without being noise.
set -uo pipefail

# ── The ARCHIVE-ACT hint, one home for both arms [OPS.41] ─────────────────────
# The three outgoing sweeps of an archive (`item_cementation.md` ⚡ Шпаргалка) have no
# CI behind them by construction, and the once-per-session tracker hint below reaches
# the FIRST tracker edit of a session, not the archive that lands hours later
# (guard-craft #104: the carrier fired, its dedup key was the SESSION, the rule guards
# a MOMENT). So the act gets its own carrier, in two arms: the Edit/Write content
# branch below, and `bash_verify_guard.sh` rule I for the script channel — which is
# the DOMINANT one (2,392 recorded calls wrote `00_07` by script in a month). That
# rule prints this same text through `--archive-hint`, so the wording has one home.
archive_hint() {
  cat <<EOF
[SSOT] Акт архівації чи зрізу пункту в \`00_07\`: $1— три вихідні свіпи, за якими не стоїть жоден CI, і нагадування на першу правку сесії до цієї миті не доживає (OPS.41):
1. Хто чекав на МЕНЕ: \`grep -n "<ID>" docs/00_07*.md\` — читай контекст КОЖНОГО хіта на ⛔ · ЗАБЛОКОВАНО · до присуду · чекає на, ⊕ гліф 🔗 у рядку з цим ID (словника в нього немає).
2. Хто шле СЮДИ по стан (джерело поза git): \`bash .claude/hooks/memory_gate.sh --stale-state\`.
3. Чи не лишився я в 🚦 Critical Path: \`ruby scripts/tracker_report.rb --critical-path\` ⊕ слеш-форми \`/<номер>\` у рядках 🚦/⛓️ (звіт їх не бачить).
⊕ Архівація — теж зріз: урок, метод чи відкинута альтернатива з тіла мають доми ПОЗА трекером, і рядок архіву їх не переживе. ⚠️ ID зібрано з рядків-літералів правки, тож серед них буває й ЯКІР, а не архівований пункт. Метод — \`.claude/prompts/item_cementation.md\` (⚡ Шпаргалка · Фаза 5).
EOF
}
if [[ "${1:-}" == "--archive-hint" ]]; then
  archive_hint "${2:-}"
  exit 0
fi

# A tracker-ID that opens an archive row: `PREFIX.N…` or `PREFIX-N` (`SLASH-1`). Rows of
# this shape exist ONLY under `## 🗄️` — measured over the whole tracker 2026-10-04 —
# so a NEW one in an edit is an archive act, and a vanished `#### ID —` is an item cut.
ID_RE='[A-Z][A-Za-z0-9]*(-[A-Za-z0-9]+)*(\.[0-9][0-9A-Za-z.]*|-[0-9]+)'
row_ids()  { printf '%s\n' "$1" | grep -oE "^\| ${ID_RE} \|" | sed -E 's/^\| ([^ ]+) \|$/\1/' | LC_ALL=C sort -u; }
head_ids() { printf '%s\n' "$1" | grep -oE '^#### [^ ]+ — ' | sed -E 's/^#### ([^ ]+) — $/\1/' | LC_ALL=C sort -u; }
archive_ids() {  # $1 = text before, $2 = text after → the IDs whose act this is
  { LC_ALL=C comm -13 <(row_ids "$1") <(row_ids "$2"); LC_ALL=C comm -23 <(head_ids "$1") <(head_ids "$2"); } \
    | grep -v '^$' | LC_ALL=C sort -u | tr '\n' ' '
}

# ── --selftest · both content branches, both arms of each ─────────────────────
# A hint hook fails SILENT: a broken detector reads exactly like «no act happened»,
# which is the very class OPS.41 exists for. So the content branches carry a
# battery (wired as a docs.yml step), like the guard beside them. Fresh session ids
# and an own TMPDIR keep the once-per-session markers out of the verdicts.
if [[ "${1:-}" == "--selftest" ]]; then
  TMPDIR=$(mktemp -d "${TMPDIR:-/tmp}/ssothint-selftest.XXXXXX"); export TMPDIR
  trap 'rm -rf "$TMPDIR"' EXIT
  self="$0"; fails=0; n=0
  trk="$TMPDIR/repo/docs/00_07_Action_Plan_Tracker.md"; mkdir -p "$(dirname "$trk")"
  printf '#### FIXT.8 — живий пункт\n- **Стан:** x\n\n## 🗄️ Архів\n\n| FIXT.7 | **закрито** | `00_06 §3` |\n' > "$trk"
  canon="$TMPDIR/repo/docs/00_06_SSOT_Documentation_Standard.md"; : > "$canon"
  # Fixture IDs use the `FIXT` prefix on purpose: it is not a tracker family, so
  # `scripts/code_tracker_id_check.rb` (which judges only known families) leaves them
  # alone while the archive regex still reads them. A phantom of a REAL family reds
  # that gate; a real ID would surface in every future «who cites X» sweep.
  # c <name> <expect> <file> <old_string> <new_string>   (old="@WRITE" → a Write of new_string)
  c() {
    local name=$1 expect=$2 fp=$3 old=$4 new=$5 js out got
    n=$((n + 1))
    if [[ "$old" == "@WRITE" ]]; then
      js=$(jq -nc --arg f "$fp" --arg c "$new" --arg s "st-$$-$n" '{tool_input:{file_path:$f,content:$c},session_id:$s}')
    else
      js=$(jq -nc --arg f "$fp" --arg o "$old" --arg w "$new" --arg s "st-$$-$n" '{tool_input:{file_path:$f,old_string:$o,new_string:$w},session_id:$s}')
    fi
    out=$(printf '%s' "$js" | bash "$self")
    got="silent"
    [[ -n "$out" ]] && got="once"
    [[ "$out" == *"ТІЛО присуду"* ]] && got="verdict"
    [[ "$out" == *"Акт архівації"* ]] && got="archive"
    [[ "$out" == *"ТІЛО присуду"* && "$out" == *"Акт архівації"* ]] && got="both"
    if [[ "$got" == "$expect" ]]; then
      printf '  ✓ %-50s %s\n' "$name" "$got"
    else
      printf '  ✗ %-50s expected %s, got %s\n    out: %s\n' "$name" "$expect" "$got" "${out:0:200}"
      fails=$((fails + 1))
    fi
  }
  c "archive: a NEW archive row"                   archive "$trk" '| FIXT.7 | **закрито** | x |' $'| FIXT.7 | **закрито** | x |\n| FIXT.9 | **закрито** | `00_06 §3` |'
  c "archive: a cut #### heading"                  archive "$trk" $'#### FIXT.8 — живий пункт\n- **Стан:** x\n' ''
  c "archive: a PREFIX-N-shaped ID counts"         archive "$trk" 'x' $'| FIXT-9 | **закрито** | `05_05 §3` |'
  c "archive: Write that adds a row"               archive "$trk" '@WRITE' $'#### FIXT.8 — живий пункт\n- **Стан:** x\n\n## 🗄️ Архів\n\n| FIXT.7 | **закрито** | `00_06 §3` |\n| FIXT.6 | **так** | `00_06 §3` |\n'
  c "no act: an EXISTING row edited in place"      once    "$trk" '| FIXT.7 | **закрито** | x |' '| FIXT.7 | **закрито ✅** | x |'
  c "no act: a heading RETITLED, not cut"          once    "$trk" '#### FIXT.8 — живий пункт' '#### FIXT.8 — живий пункт, нова назва'
  c "no act: a table row of ANOTHER shape"         once    "$trk" 'x' '| SWD | пади | так |'
  c "no act: an archive-shaped row in a CANON doc" once    "$canon" 'x' '| FIXT.5 | **закрито** | `00_06 §3` |'
  c "verdict: delegated verdict body"              verdict "$trk" 'x' $'- ✅ **⚖️ делеговано 2026-10-04:** суть **Підстава:** y'
  c "both: verdict body AND an archive row"        both    "$trk" 'x' $'- ✅ **⚖️ x**\n| FIXT.4 | **закрито** | `00_06 §3` |'
  if (( fails > 0 )); then
    echo "ssot_guard_hint --selftest: ${fails}/${n} FAILED"
    exit 1
  fi
  echo "ssot_guard_hint --selftest: OK (${n} cases — archive-act and verdict-body branches, both arms)"
  exit 0
fi

input=$(cat)
file_path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
session=$(printf '%s' "$input" | jq -r '.session_id // "nosession"' 2>/dev/null)

[[ -n "$file_path" ]] || exit 0
[[ "$file_path" == *"/docs/"* ]] || exit 0
[[ "$file_path" == *.md ]] || exit 0

case "$file_path" in
  */00_07_Action_Plan_Tracker.md) class="tracker" ;;
  */docs/[0-9][0-9]_[0-9][0-9]_*.md)  class="canon" ;;
  *) exit 0 ;;
esac

# Content branches — fire EVERY time, bypassing the once-per-session marker below.
# (1) A closed verdict BODY is being written into the tracker. Measured 2026-09-27: the
# once-per-session hint fired at the first tracker edit, and eight delegated-verdict
# bodies were written hours later (the event recurs, the reminder did not); and
# item 4 said «ратифікований» while the act was «записую делегований», so the act did
# not recognise itself in the carrier. `grep -F` on purpose — byte-exact on
# emoji/Cyrillic, locale-free.
# (2) An ARCHIVE ACT [OPS.41]: a new `| ID |` row, or a `#### ID —` heading that the edit
# removes. For a Write the «before» is the file on disk. ⚠️ Ceiling, named: an item MOVED
# between sections by two edits fires on the cut — a move is not an archive, and telling
# the two apart needs the second edit, which this hook never sees together with the first.
if [[ "$class" == "tracker" ]]; then
  new_text=$(printf '%s' "$input" | jq -r '.tool_input.new_string // .tool_input.content // empty' 2>/dev/null)
  if printf '%s' "$input" | jq -e '.tool_input | has("content")' >/dev/null 2>&1; then
    old_text=$(cat "$file_path" 2>/dev/null || true)
  else
    old_text=$(printf '%s' "$input" | jq -r '.tool_input.old_string // empty' 2>/dev/null)
  fi
  ctx=""
  if printf '%s' "$new_text" | grep -qF -e '- ✅ **⚖️' \
     || { printf '%s' "$new_text" | grep -qF 'делеговано 20' && printf '%s' "$new_text" | grep -qF '**Підстава'; }; then
    read -r -d '' ctx <<'EOF' || true
[SSOT] Ти пишеш у трекер ТІЛО присуду (підстава · ціна · найслабша ланка). Це стосується й ДЕЛЕГОВАНОГО присуду, який ти сам щойно ухвалюєш: запис присуду і є його застосуванням. Повна форма живе в КАНОН-ДОМІ (сторінка, картка, шапка рушія); у пункт — одне речення «⚖️ делеговано <дата>: суть — адреса» і відкриті ноги, які присуд породив (`00_05 §5`, третя половина кола). Тіло в ✅-рядку трекера = борг, який наступна цементація платить перевідкриттям.
EOF
  fi
  ids=$(archive_ids "$old_text" "$new_text")
  if [[ -n "${ids// /}" ]]; then
    ctx="${ctx:+$ctx

}$(archive_hint "$ids")"
  fi
  if [[ -n "$ctx" ]]; then
    jq -nc --arg ctx "$ctx" \
      '{hookSpecificOutput: {hookEventName: "PreToolUse", additionalContext: $ctx}}'
    exit 0
  fi
fi

marker="${TMPDIR:-/tmp}/claude-ssot-hint-${session}-${class}"
[[ -f "$marker" ]] && exit 0
: > "$marker"

if [[ "$class" == "canon" ]]; then
  read -r -d '' hint <<'EOF' || true
[SSOT] Канон-док. Скіл `ssot-maintenance` — операційний playbook; `00_06 §2` — реєстр домів.

ФОРМУ цього файлу стережуть `docs:check_refs`+`tracker:check` (`ruby scripts/docs_check.rb`, 0.3с, HARD: dangling-лінки, §-drift, ToC, bare doc-ids, volatile line-refs). ⚠️ Це **два кроки** джоби `docs_check`, а не смуга: решта (spdx · model/component-sync · code_doc_section_refs · protocols-ref …) НЕ біжить — повна смуга `ruby scripts/docs_band.rb`. Тут — те, чого не бачить ЖОДЕН із них:

1. **grep-hit ≠ канонізовано.** Перед тим як схлопнути/стоншити факт — ПРОЧИТАЙ повну секцію в КОЖНОМУ домі, де він живе. Zero-loss set-diff сам grep-based, тож факт, присутній по токену але вихолощений по суті, проходить ЗЕЛЕНИМ. Це єдина червона лінія без гейта позаду.
2. **Migrate-first.** Наповни новий дім ПОВНОЮ субстанцією + переконайся, що вона там, і лише ТОДІ ріж джерело.
3. **Одна Edit → верифікуй → наступна.** Навіть non-glue: leading-`\n` removal склеює рядки, елементи зникають з парсера, гейт лишається хибно-зеленим.
EOF
else
  read -r -d '' hint <<'EOF' || true
[SSOT] Трекер `00_07`. Форму стереже `ruby scripts/docs_check.rb tracker` (HARD) — не переказую; ⚠️ це ОДИН крок джоби `docs_check`, повна смуга перед комітом — `ruby scripts/docs_band.rb`. Тут те, що гейт пропускає:

1. **Чекбокс несе ЛИШЕ відкрите.** Закрита робота живе в `- **Стан:**` + git, не як `[x]`-звіт. Повністю закритий пункт → §🗄️ Архів рядком `| ID | суть | канон |`, а НЕ «товстий ✅».
2. **Перед архівацією — verify-canon.** Інбаунд-рефи по ID (канон/код/скіли) мусять лишитись живими: архівний рядок і є їхній дім. Спершу перевір, що присуд і design-justification вже в каноні — інакше зріжеш незбережене.
3. **WHO meta-line = обʼєднання ВІДКРИТИХ виконавців** (закрита половина не рахується); `⚖️` — завжди trailing у комбо; перший канон-реф мусить бути модуля своєї §-секції.
4. **Застосовуєш присуд — ратифікований чи ДЕЛЕГОВАНИЙ, який ти сам записуєш, — ПОВЕРНИ його тим самим комітом:** підстава · ціна · найслабша ланка → канон-дім, тіло з пункту геть, відкриті ноги лишаються (`00_05 §5`, третя половина кола). Без цього пункт росте до гіганта (HW.34 — 139 kB).

Метод цілком — `.claude/prompts/item_cementation.md`.
EOF
fi

jq -nc --arg ctx "$hint" \
  '{hookSpecificOutput: {hookEventName: "PreToolUse", additionalContext: $ctx}}'
