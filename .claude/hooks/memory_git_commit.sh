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
# паралельного запису, відсутній git) → тихий exit 0. Пропущений коміт файлу
# самолікується наступним записом ТОГО Ж файлу.
#
# ЧОМУ ЛИШЕ ЗАПИСАНИЙ ФАЙЛ, А НЕ `add -A` (наступного дня після інциденту 2026-11-03). Доти хук брав ВЕСЬ брудний
# корпус — сітка, що наступним Edit підхоплювала власні Bash-правки сесії. Але
# корпус спільний: з паралельною сесією той самий `-A` змів шість її незакомічених
# файлів під subject чужого запису, і провенанс `git log -S` збрехав про автора.
# Тепер комітиться лише файл події, а решту брудних файлів хук НАЗИВАЄ сесії в
# мить дії (additionalContext), не змітаючи. Ціна названа: Bash-правка лишається
# незакоміченою, доки сесія не закомітить її явним шляхом — і щоразу про це чує.

set -uo pipefail

MEM_DIR="${MEMORY_GATE_DIR:-/Users/oleksiilukin/.claude/projects/-Users-oleksiilukin-silken-net/memory}"

commit_now() {
  local fp=$1 tool=$2 sid=$3 bn rel dirty
  [ -d "$MEM_DIR/.git" ] || return 0
  bn=$(basename "$fp")
  rel=${fp#"$MEM_DIR"/}

  # Лише файл події: `add` робить простеженим і новий файл із Write, а `--only`
  # комітить рівно його, не чіпаючи нічого, що в індексі лишила інша сесія.
  git -C "$MEM_DIR" add -- "$rel" >/dev/null 2>&1 || return 0
  # Цей файл не змінився (harness переписав його байт-у-байт) — коміту немає.
  if ! git -C "$MEM_DIR" diff --cached --quiet -- "$rel"; then
    git -C "$MEM_DIR" commit -q --only -F - -- "$rel" >/dev/null 2>&1 <<EOF
mem(${bn}): ${tool:-write}

session ${sid:-unknown}
EOF
  fi

  # Решта брудного корпусу — назвати сесії в мить дії, не змітати.
  dirty=$(git -C "$MEM_DIR" -c core.quotepath=false status --porcelain 2>/dev/null |
    sed 's/^...//' | grep -v -x -F -- "$rel" | head -8 | tr '\n' ' ')
  [ -n "${dirty// /}" ] || return 0
  jq -n --arg ctx "[memory-commit] Закомічено лише ${bn}. У корпусі лишились НЕзакомічені: ${dirty}— якщо це твої Bash-правки, закоміть їх явними шляхами (git -C <memory> add <файли> && git -C <memory> commit); якщо паралельної сесії — не чіпай." \
    '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$ctx}}' 2>/dev/null || true
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

  # 7. ПІН НА ЧУЖІЙ ПРАВЦІ ВСЕРЕДИНІ КОРПУСУ [2026-11-03]. Паралельна сесія лишила свій
  #    файл брудним; запис у НАШ файл мусить закомітити лише його — `add -A` замів би й
  #    чужий під наш subject (так і сталося в живому корпусі).
  _build; before=$(_count)
  printf 'theirs\n' >"$root/feedback_beta.md"
  printf 'ours\n' >"$root/feedback_alpha.md"
  out=$(_fire "$root/feedback_alpha.md" Edit sess-7)
  [ "$(git -C "$root" show --name-only --format= HEAD)" = "feedback_alpha.md" ] &&
    [ "$(_count)" -eq $((before + 1)) ] &&
    git -C "$root" status --porcelain | grep -q '^?? feedback_beta.md$' &&
    _ok "a corpus write commits ONLY its own file; a neighbour's file stays untouched (not even staged)" ||
    _bad "own-file commit: HEAD '$(git -C "$root" show --name-only --format= HEAD | tr '\n' ' ')', status '$(git -C "$root" status --porcelain | tr '\n' ' ')'"

  # 7b. Сусідка свій файл уже ЗАСТЕЙДИЛА, але не закомітила: наш запис бере лише наш
  #     файл (`--only`), а її стейдж лишає як був — голий `commit` забрав би й його.
  _build; before=$(_count)
  printf 'theirs-staged\n' >"$root/feedback_beta.md"; git -C "$root" add feedback_beta.md
  printf 'ours-again\n' >"$root/feedback_alpha.md"
  _fire "$root/feedback_alpha.md" Edit sess-7b >/dev/null
  [ "$(git -C "$root" show --name-only --format= HEAD)" = "feedback_alpha.md" ] &&
    git -C "$root" status --porcelain | grep -q '^A  feedback_beta.md$' &&
    _ok "a neighbour's STAGED file is neither committed nor unstaged" ||
    _bad "staged neighbour: HEAD '$(git -C "$root" show --name-only --format= HEAD | tr '\n' ' ')', status '$(git -C "$root" status --porcelain | tr '\n' ' ')'"

  # 8. …і хук НАЗИВАЄ чужий брудний файл у мить дії; на чистому корпусі — мовчить.
  printf '%s' "$out" | grep -q 'feedback_beta.md' &&
    _ok "the neighbour's dirty file is NAMED in additionalContext" ||
    _bad "warning: hook output did not name feedback_beta.md: '$out'"
  _build
  printf 'clean-rest\n' >"$root/feedback_alpha.md"
  out=$(_fire "$root/feedback_alpha.md" Edit sess-8)
  [ -z "$out" ] &&
    _ok "with no other dirty file the hook stays silent" ||
    _bad "silence: the hook spoke on a clean corpus: '$out'"

  # 9. Новий файл із Write комітиться — `--only` без `add` мовчки пропустив би непростежений.
  _build; before=$(_count)
  printf 'new\n' >"$root/project_gamma.md"
  _fire "$root/project_gamma.md" Write sess-9 >/dev/null
  [ "$(_count)" -eq $((before + 1)) ] &&
    git -C "$root" ls-files --error-unmatch project_gamma.md >/dev/null 2>&1 &&
    _ok "a NEW file written by Write is committed" ||
    _bad "new file: count $before → $(_count), tracked: '$(git -C "$root" ls-files project_gamma.md)'"

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
