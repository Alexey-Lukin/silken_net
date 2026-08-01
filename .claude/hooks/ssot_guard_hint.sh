#!/usr/bin/env bash
# PreToolUse hook — SSOT discipline reminder, fired ONCE per session per class.
#
# Why PreToolUse and not PostToolUse (like our two other hooks): this one must
# land BEFORE the edit. A reminder that arrives after I have already collapsed a
# canon section is worth nothing — the damage is the edit itself.
#
# Why it carries what it carries: `docs_check.rb` already catches every FORM
# violation (DOC-T.15 line-refs, meta-line WHO, section-home, bare doc-ids) and
# it does so in 0.3s, HARD. Repeating those here would be noise. What no gate
# can see is the one red line `deep_archival.md` itself flags as ungated: the
# zero-loss set-diff is grep-based, so a fact that is present-by-token but
# gutted-in-substance passes GREEN. That is the only thing worth interrupting
# for — plus the ordering rule, whose violations are invisible by construction.
#
# Once per session per class (canon vs tracker), keyed on session_id: a noisy
# advisory is a disabled gate — the same rule this repo applies to its linters.
set -uo pipefail

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

marker="${TMPDIR:-/tmp}/claude-ssot-hint-${session}-${class}"
[[ -f "$marker" ]] && exit 0
: > "$marker"

if [[ "$class" == "canon" ]]; then
  read -r -d '' hint <<'EOF' || true
[SSOT] Канон-док. Скіл `ssot-maintenance` — операційний playbook; `00_06 §2` — реєстр домів.

Гейти вже стережуть ФОРМУ (`ruby scripts/docs_check.rb` — 0.3с, HARD: dangling-лінки, §-drift, ToC, bare doc-ids, volatile line-refs). Тут — те, чого не бачить ЖОДЕН гейт:

1. **grep-hit ≠ канонізовано.** Перед тим як схлопнути/стоншити факт — ПРОЧИТАЙ повну секцію в КОЖНОМУ домі, де він живе. Zero-loss set-diff сам grep-based, тож факт, присутній по токену але вихолощений по суті, проходить ЗЕЛЕНИМ. Це єдина червона лінія без гейта позаду.
2. **Migrate-first.** Наповни новий дім ПОВНОЮ субстанцією + переконайся, що вона там, і лише ТОДІ ріж джерело.
3. **Одна Edit → верифікуй → наступна.** Навіть non-glue: leading-`\n` removal склеює рядки, елементи зникають з парсера, гейт лишається хибно-зеленим.
EOF
else
  read -r -d '' hint <<'EOF' || true
[SSOT] Трекер `00_07`. Форму стереже `ruby scripts/docs_check.rb tracker` (HARD) — не переказую. Тут те, що гейт пропускає:

1. **Чекбокс несе ЛИШЕ відкрите.** Закрита робота живе в `- **Стан:**` + git, не як `[x]`-звіт. Повністю закритий пункт → §🗄️ Архів рядком `| ID | суть | канон |`, а НЕ «товстий ✅».
2. **Перед архівацією — verify-canon.** Інбаунд-рефи по ID (канон/код/скіли) мусять лишитись живими: архівний рядок і є їхній дім. Спершу перевір, що присуд і design-justification вже в каноні — інакше зріжеш незбережене.
3. **WHO meta-line = обʼєднання ВІДКРИТИХ виконавців** (закрита половина не рахується); `⚖️` — завжди trailing у комбо; перший канон-реф мусить бути модуля своєї §-секції.

Метод цілком — `.claude/prompts/deep_archival.md`.
EOF
fi

jq -nc --arg ctx "$hint" \
  '{hookSpecificOutput: {hookEventName: "PreToolUse", additionalContext: $ctx}}'
