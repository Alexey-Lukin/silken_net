#!/usr/bin/env bash
# memory_git_commit.sh — версіонує КОЖЕН запис у корпус памʼяті.
#
# ЧОМУ ОКРЕМИЙ ФАЙЛ, А НЕ ПАТЧ У memory_gate.sh. Гейт — діагност: він читає
# корпус і доповідає. Це — дія, що змінює стан. Злити їх означало б навчити
# 40-кейсову CI-батарею гейта створювати коміти, і кожен її тимчасовий корпус
# став би репозиторієм. Різні роботи — різні доми.
#
# ЧОМУ ХУК, А НЕ ПРАВИЛО. «Не забудь закомітити памʼять» не спрацьовує в момент
# дії; PostToolUse — і є той момент. Правило без носія рецидивує, це виміряно на
# цьому ж корпусі.
#
# ЧОМУ ПЕР-ЗАПИС, А НЕ ПЕР-СЕСІЮ. Цінність історії тут — `git log -S '<фраза>'`:
# «коли ця заява ввійшла в корпус і яка сесія її написала». Пер-сесійний коміт
# зліплює десяток правок в одну й ту відповідь губить. Репозиторій локальний і
# ніколи не пушиться, тож дрібність коміта нічого не коштує.
#
# НІКОЛИ НЕ ВАЛИТЬ ВИКЛИК. Немає `set -e`; будь-яка невдача (index.lock від
# паралельного запису, відсутній git) → тихий exit 0. Пропущений коміт
# самолікується наступним, бо `add -A` бере ВЕСЬ стан, а не дельту події.

set -uo pipefail

MEM_DIR="${MEMORY_GATE_DIR:-/Users/oleksiilukin/.claude/projects/-Users-oleksiilukin-silken-net/memory}"

commit_now() {
  local fp=$1 tool=$2 sid=$3 bn
  [ -d "$MEM_DIR/.git" ] || return 0
  bn=$(basename "$fp")

  git -C "$MEM_DIR" add -A -- . >/dev/null 2>&1 || return 0
  # Порожній стейдж = запис нічого не змінив (harness переписав файл байт-у-байт).
  git -C "$MEM_DIR" diff --cached --quiet && return 0

  git -C "$MEM_DIR" commit -q -F - >/dev/null 2>&1 <<EOF
mem(${bn}): ${tool:-write}

session ${sid:-unknown}
EOF
}

# ── selftest ────────────────────────────────────────────────────────────────
# Норма цього репо: патч їде зі своїм пін-кейсом, мутаційно перевіреним — той,
# що проходить в обидва боки, не перевіряє нічого.
#
# ⚠️ Перша редакція цієї батареї впала саме туди й це записано як урок. Вона
# кликала commit_now НАПРЯМУ і пінила «no-op запис не дає коміта» — а мутант із
# вирізаним guard'ом лишився ЗЕЛЕНИМ, бо `git commit` із порожнім індексом і так
# падає. Кейс міряв поведінку git, а не мій код, і при цьому фільтр шляху —
# єдине справжнє розгалуження хука — не перевірявся взагалі, бо жив у стійці
# PostToolUse, куди батарея не заходила.
#
# Тому батарея ганяє ХУК НАСКРІЗЬ через stdin, а пін стоїть на фільтрі: корпус
# лишається БРУДНИМ, і приходить запис у чужий файл. Без фільтру `add -A` замів
# би брудний корпус у коміт, спричинений подією, що корпусу не стосується —
# тобто чужий запис привласнив би авторство. Це і є те, що можна зламати.
if [ "${1:-}" = "--selftest" ]; then
  SELF="${BASH_SOURCE[0]}"
  root=$(mktemp -d) || { echo "selftest: cannot mktemp"; exit 1; }
  outside=$(mktemp -d) || { echo "selftest: cannot mktemp"; exit 1; }
  fail=0

  _build() {
    rm -rf "$root"; mkdir -p "$root"
    git -C "$root" init -q -b main
    git -C "$root" config user.name t; git -C "$root" config user.email t@t
    printf 'seed\n' >"$root/feedback_alpha.md"
    git -C "$root" add -A >/dev/null; git -C "$root" commit -q -m seed
  }
  # Ганяє САМ хук так, як його кличе harness.
  _fire() {
    printf '{"tool_name":"%s","session_id":"%s","tool_input":{"file_path":"%s"}}' "$2" "$3" "$1" |
      MEMORY_GATE_DIR="$root" bash "$SELF"
  }
  _count() { git -C "$root" rev-list --count HEAD 2>/dev/null || echo 0; }
  _ok()   { pass_msg=$1; echo "  ok    $pass_msg"; }
  _bad()  { echo "  FAIL  $1"; fail=1; }

  # 1. ПОЗИТИВ — запис у корпус дає рівно один коміт.
  _build; before=$(_count)
  printf 'changed\n' >"$root/feedback_alpha.md"
  _fire "$root/feedback_alpha.md" Edit sess-1
  [ "$(_count)" -eq $((before + 1)) ] &&
    _ok "a corpus write produces exactly one commit" ||
    _bad "write→commit: expected $((before + 1)), got $(_count)"

  # 2-3. Повідомлення несе адресу археології: файл+інструмент, і сесію в тілі.
  git -C "$root" log -1 --format=%s | grep -q '^mem(feedback_alpha.md): Edit$' &&
    _ok "subject names the file and the tool" ||
    _bad "subject: got '$(git -C "$root" log -1 --format=%s)'"
  git -C "$root" log -1 --format=%b | grep -q '^session sess-1$' &&
    _ok "body carries the session id (the log -S → transcript route)" ||
    _bad "body: got '$(git -C "$root" log -1 --format=%b)'"

  # 4. ПІН НА ФІЛЬТРІ ШЛЯХУ. Корпус брудний, подія — про ЧУЖИЙ файл.
  #    Без фільтру чужий запис привласнив би брудний корпус собі.
  _build; before=$(_count)
  printf 'dirty\n' >"$root/feedback_alpha.md"
  printf 'x\n' >"$outside/elsewhere.md"
  _fire "$outside/elsewhere.md" Write sess-2
  [ "$(_count)" -eq "$before" ] &&
    _ok "a write OUTSIDE the corpus commits nothing, dirty corpus notwithstanding" ||
    _bad "path filter: an outside write moved the corpus $before → $(_count)"

  # 5. Той самий пін для власної машинерії репозиторію.
  _fire "$root/.git/config" Write sess-2
  [ "$(_count)" -eq "$before" ] &&
    _ok "a write under .git/ commits nothing" ||
    _bad ".git filter: commit count moved $before → $(_count)"

  # 6. Корпус без .git — хук мовчить, а не падає (перший запуск, знятий репо).
  _build; rm -rf "$root/.git"
  printf 'y\n' >"$root/feedback_alpha.md"
  _fire "$root/feedback_alpha.md" Write sess-3 &&
    _ok "a corpus without .git is silent, not fatal" ||
    _bad "missing .git returned non-zero"

  rm -rf "$root" "$outside"
  [ "$fail" -eq 0 ] && { echo "memory_git_commit selftest: all pass"; exit 0; }
  echo "memory_git_commit selftest: FAILURES"; exit 1
fi

# ── PostToolUse ─────────────────────────────────────────────────────────────
input=$(cat)
fp=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
case "$fp" in
  "$MEM_DIR"/.git/*) exit 0 ;;   # ніколи не версіонуємо власну машинерію
  "$MEM_DIR"/*)      ;;
  *)                 exit 0 ;;
esac

commit_now "$fp" \
  "$(printf '%s' "$input" | jq -r '.tool_name   // empty' 2>/dev/null)" \
  "$(printf '%s' "$input" | jq -r '.session_id  // empty' 2>/dev/null)"
exit 0
