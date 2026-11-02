#!/usr/bin/env bash
# edit_glue_guard.sh — PreToolUse Edit: an Edit of a Markdown file whose new_string is EMPTY is denied, every time
# (⚖️ founder 2026-11-02, the proposal after relapse (31) of memory `log_parallel_edit`).
#
# The class: deleting text with new_string = "" hands the line boundaries to the exact span of old_string, and a
# "\n" too many or too few in it glues two neighbours into one line — 2026-11-02 in the tracker, «…джерела немає.- [ ]
# 👤 Метод ламінації…»: an open checkbox swallowed into the line above. No gate sees it: the tracker parser, every
# count and every grep read the glued line as one well-formed item. The rule lived in memory
# (`feedback_parallel_edit_glue` rule 4, «a solo Edit with an empty new_string glues too») and relapsed at the moment
# of the act — a rule needs a carrier at that moment, and this is it.
# The replacement keeps the boundary VISIBLE: take a neighbour into old_string and give it back in new_string, so the
# newlines on both sides are written out; or delete by script with an anchor and a guard.
# Every time, not once per session: a stop the retry passes would let the very edit through.
# ⚠️ Ceilings, named: *.md only (canon, tracker, protocols, the memory corpus — where a glued line is a silent
# structure change; code keeps its parser and linters); an edit made by script (Bash) never meets this hook; a Write
# rewriting the whole file is not judged; and an empty new_string is only the commonest form — an old_string that
# swallows a "\n" the new_string does not give back glues as well, and is not caught.
set -uo pipefail

reason() {
  printf '%s' "[edit-glue] Edit із порожнім new_string у ${1} — видалення без явних меж рядка склеює сусідів (рецидив 2026-11-02 у трекері: відкритий чекбокс проковтнуто рядком вище, і жоден гейт цього не бачить). Візьми сусідній рядок в old_string і поверни його в new_string — переноси з обох боків тоді видно; або видали скриптом з анкором і гардом (\`t.count(old) == 1\`, потім \`grep -n\` сусідів). Пам'ять: feedback_parallel_edit_glue, правило 4."
}

# ── --selftest · both arms: the glue form must stop ⊥ every neighbouring legitimate form must pass ─────────────
if [[ "${1:-}" == "--selftest" ]]; then
  self="$0"; fails=0; n=0
  c() {  # c <name> <expect deny|silent> <tool_input json>
    local out got=silent
    n=$((n + 1))
    out=$(jq -nc --argjson ti "$3" '{session_id:"st",tool_name:"Edit",tool_input:$ti}' | bash "$self")
    [[ "$out" == *'"permissionDecision":"deny"'* ]] && got=deny
    if [[ "$got" == "$2" ]]; then printf '  ✓ %-60s %s\n' "$1" "$got"
    else printf '  ✗ %-60s expected %s, got %s\n    out: %s\n' "$1" "$2" "$got" "${out:0:200}"; fails=$((fails + 1)); fi
  }
  c "empty new_string in a canon .md is DENIED"            deny   '{"file_path":"/r/docs/00_07_Action_Plan_Tracker.md","old_string":"- [ ] x\n","new_string":""}'
  c "…in a memory-corpus .md too"                          deny   '{"file_path":"/h/.claude/projects/p/memory/log_x.md","old_string":"a","new_string":""}'
  c "…and with replace_all"                                deny   '{"file_path":"/r/docs/a.md","old_string":"a","new_string":"","replace_all":true}'
  c "a neighbour kept in new_string passes"                silent '{"file_path":"/r/docs/a.md","old_string":"A\nB\n","new_string":"A\n"}'
  c "a single newline as new_string passes"                silent '{"file_path":"/r/docs/a.md","old_string":"A\nB\n","new_string":"\n"}'
  c "empty new_string in code (.py) passes — not this scope" silent '{"file_path":"/r/tools/x.py","old_string":"a","new_string":""}'
  c "a .md-like name that is not .md (.mdx) passes"        silent '{"file_path":"/r/docs/a.mdx","old_string":"a","new_string":""}'
  c "a Write (content, no new_string) passes"              silent '{"file_path":"/r/docs/a.md","content":""}'
  c "no file_path passes"                                  silent '{"old_string":"a","new_string":""}'
  if (( fails > 0 )); then echo "edit_glue_guard --selftest: ${fails}/${n} FAILED"; exit 1; fi
  echo "edit_glue_guard --selftest: OK (${n} cases — the glue form stops · its neighbours pass · scope *.md)"
  exit 0
fi

input=$(cat)
fp=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[[ "$fp" == *.md ]] || exit 0
empty=$(printf '%s' "$input" | jq -r 'if .tool_input.new_string == "" then "yes" else "no" end' 2>/dev/null)
[[ "$empty" == "yes" ]] || exit 0
jq -nc --arg r "$(reason "$(basename "$fp")")" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
exit 0
