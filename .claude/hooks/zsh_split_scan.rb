#!/usr/bin/env ruby
# frozen_string_literal: true
#
# zsh_split_scan.rb — the statically-decidable half of the zsh word-splitting
# class, for `bash_verify_guard.sh`. Reads a shell command on stdin, prints one
# line per finding, exits 0 always (the hook decides what to do with them).
#
# WHY A SCRIPT AND NOT A REGEX. zsh does not word-split an unquoted scalar, so
# `for x in $list` iterates ONCE over the whole string and `set -- $pair` leaves
# $2 empty for any input — a check written against bash intuition then reports
# "clean" no matter what it was given. Deciding this needs to know whether a `$`
# stands at shell level or inside quotes opened EARLIER, which is parser state;
# the best stateless pattern measured 33.9% precision on this corpus and was
# killed by `echo "=== $var ==="`. So the quote/substitution walk below is the
# whole point, and the anchors are deliberately narrow.
#
# Kept compatible with /usr/bin/ruby (2.6) so the detector cannot go dark when
# RVM is absent from the hook's PATH — a silent scanner is worse than none.
#
# ⛔ DO NOT ADD AN `echo` EXCLUSION. It looks obvious — `echo $v` cannot corrupt
# anything — and it was measured NET-HARMFUL on the grep-era prototype: it muted
# 4 true positives (`ruby $(echo $g)`, and whole calls where an inert `echo $v`
# sat beside a live `prog $v`) against 2 false ones. The narrow anchors below
# make it unnecessary anyway: `echo "=== $var ==="` is not a `for`/`set --` list,
# which is precisely what the 33.9%-precision grep version could not tell.
#
# THREE FORMS ARE SAFE IN zsh AND ARE EXCLUDED BY MEASUREMENT, NOT BY TASTE
# (probe run 2026-08-08, zsh 5.9): `$(subst)` DOES split (3 iterations) · an
# array `arr=(a b c); for x in $arr` DOES expand to elements (3) · a glob
# `$dir/*.md` still expands after the parameter. An assignment RHS never splits
# in any shell, so `f=${pair%%:*}` inside the body is not a defect either.

FILL = ' '

# One pass over the command. Returns [masked, qspans]:
#   masked — same length as cmd, with every character inside quotes or inside a
#            command substitution replaced by FILL, so whatever is still visible
#            stands at shell level.
#   qspans — [open_idx, close_idx, content] for each CORRECTLY PAIRED quoted
#            span at substitution depth 0. Pairing must come from the walk: the
#            obvious pattern /"[^"]*[[:space:]][^"]*"/ matches the GAP BETWEEN
#            two quoted words, so on `"a" "b" "c"` it answers "multi-word" —
#            i.e. it silently tests a different question than the one asked.
def walk(cmd)
  masked = cmd.dup
  qspans = []
  q = 0 # 0 unquoted · 1 inside '…' · 2 inside "…"
  depth = 0
  qstack = []
  bt = false
  qstart = nil
  substart = nil
  i = 0
  len = cmd.length
  while i < len
    c = cmd[i]
    if q == 1 # single quotes take no escapes and no substitutions
      if c == "'"
        qspans << [qstart, i, cmd[(qstart + 1)...i]] if depth.zero?
        q = 0
      else
        masked[i] = FILL
      end
      i += 1
      next
    end
    if c == '\\'
      masked[i] = FILL
      masked[i + 1] = FILL if i + 1 < len
      i += 2
      next
    end
    if q.zero? && c == "'"
      qstart = i
      q = 1
      i += 1
      next
    end
    if c == '"'
      if q == 2
        qspans << [qstart, i, cmd[(qstart + 1)...i]] if depth.zero?
        q = 0
      else
        qstart = i
        q = 2
      end
      i += 1
      next
    end
    if c == '$' && cmd[i + 1] == '(' # substitution opens inside "…" too
      substart = i if depth.zero?
      qstack.push(q)
      q = 0
      depth += 1
      i += 2
      next
    end
    # `q.zero?` is load-bearing: a ')' inside "…" is a literal, and closing on it
    # shifts the rest of the command to a level it is not on. Found by reading a
    # finding rather than a count — the culprit was `grep -oE "(A|B)"`.
    if c == ')' && depth.positive? && !bt && q.zero?
      depth -= 1
      q = qstack.pop || 0
      if depth.zero? && substart
        (substart..i).each { |k| masked[k] = FILL }
        substart = nil
      end
      i += 1
      next
    end
    if c == '`'
      if bt
        depth -= 1
        q = qstack.pop || 0
        bt = false
        if depth.zero? && substart
          (substart..i).each { |k| masked[k] = FILL }
          substart = nil
        end
      else
        substart = i if depth.zero?
        qstack.push(q)
        q = 0
        depth += 1
        bt = true
      end
      i += 1
      next
    end
    masked[i] = FILL if q == 2 || depth.positive?
    i += 1
  end
  [masked, qspans]
end

LEAD = '(?:\A|[;&|(){}\n]|&&|\|\||\bdo\b|\bthen\b|\belse\b)'
HEAD = /#{LEAD}\s*(?:for\s+([A-Za-z_]\w*)\s+in|(set)\s+--)\s+/.freeze
BARE = /\$\{?([A-Za-z_]\w*)/.freeze
STOP = /;|\n|\s+do\b|\|\||&&/.freeze

# Is the word holding this offset a glob pattern? Then the extra words come from
# filename expansion, which happens after the parameter and is not splitting.
def glob_word?(text, at)
  from = text.rindex(/\s/, at)
  from = from ? from + 1 : 0
  to = text.index(/\s/, at) || text.length
  text[from...to].to_s =~ /[*?\[]/ ? true : false
end

# Is this occurrence the right-hand side of an assignment? No shell splits there.
def assignment_rhs?(text, at)
  from = text.rindex(/[\s;&|(]/, at)
  from = from ? from + 1 : 0
  text[from...at].to_s =~ /\A[A-Za-z_]\w*=/ ? true : false
end

def findings(cmd)
  masked, qspans = walk(cmd)
  hits = []
  pos = 0
  while (m = masked.match(HEAD, pos))
    name = m[1]
    lstart = m.end(0)
    tail = masked[lstart..-1] || ''
    lend = lstart + (tail =~ STOP || tail.length)
    list_masked = masked[lstart...lend].to_s
    list_raw = cmd[lstart...lend].to_s

    bare = nil
    list_masked.scan(BARE) do
      at = lstart + Regexp.last_match.begin(0)
      var = Regexp.last_match(1)
      next if glob_word?(masked, at)
      next if cmd =~ /(?:\A|[\s;&|(])#{Regexp.escape(var)}=\(/ # zsh array
      bare = var
      break
    end

    if bare
      # C2 — the word-list IS an unsplit scalar.
      hits << ['C2', (name || 'set --'), "$#{bare}", list_raw.strip]
    elsif name
      # C1 — the list carries multi-word quoted elements and the body re-splits.
      multi = qspans.select do |s|
        s[0] >= lstart && s[1] < lend && s[2].strip.include?(' ')
      end
      unless multi.empty?
        brest = masked[lend..-1] || ''
        dm = brest =~ /\bdone\b/
        body = dm ? brest[0...dm] : brest
        use = body =~ /\$\{?#{Regexp.escape(name)}\b/
        if use && !assignment_rhs?(body, use)
          hits << ['C1', name, multi.first[2].strip, list_raw.strip]
        end
      end
    end
    pos = m.end(0)
  end
  hits
end

# ── controls ─────────────────────────────────────────────────────────────────
# Positive AND negative; a case that passes with the detector removed is testing
# nothing. Every SAFE case below is a real idiom from this repo's own history.
CASES = [
  [:hit,  "doomed='a b c'; for slug in $doomed; do echo $slug; done", 'bare scalar list'],
  [:hit,  "pair='x y'; set -- $pair; test -z \"$2\" && echo ok",      'set -- scalar'],
  [:hit,  'for g in "ruby -v" "jq --version"; do $g; done',           'multi-word list, body re-splits'],
  [:hit,  'ids=$(grep -o X f); for id in $ids; do echo $id; done',    'subst assigned, then bare'],
  [:hit,  'for c in "bin/rails a" "bin/rails b"; do $c 2>&1; done',   'command built from list'],
  [:safe, "for id in $(gh run list --json id -q '.[].id'); do :; done", '$( ) does split in zsh'],
  [:safe, 'for c in "cmd1" "cmd2" "cmd3"; do echo $c; done',          'gap between quoted words is not an inner space'],
  [:safe, 'echo "=== $var ==="',                                      'the idiom that killed the regex version'],
  [:safe, "ruby -e 'for x in $foo; do puts x; done'",                 'not a command — inside single quotes'],
  [:safe, 'for f in "$@"; do echo "$f"; done',                        'positional array'],
  [:safe, 'for f in a b c; do echo $f; done',                         'literal list'],
  [:safe, 'for g in "a b" "c d"; do echo "$g"; done',                 'body quotes the variable'],
  [:safe, 'for f in $B/*.md; do echo $f; done',                       'glob still expands'],
  [:safe, 'arr=(a b c); for x in $arr; do echo $x; done',             'zsh array expands to elements'],
  [:safe, 'for p in "f.md:tok a" "g.md:tok b"; do n=${p%%:*}; done',  'assignment RHS never splits'],
  [:safe, 'for id in "HW.5 " "HW.6"; do echo $id; done',              'trailing space is not multi-word'],
  [:safe, 'for id in $(grep -oE "(A|B)" f); do e=$(echo "$id"); grep -qE "^## $e " t.md; done',
          'a paren inside quotes must not close the substitution']
].freeze

if ARGV[0] == '--selftest'
  bad = CASES.reject do |(want, cmd, _why)|
    got = findings(cmd).empty? ? :safe : :hit
    got == want
  end
  bad.each { |(want, cmd, why)| warn "FAIL want=#{want} (#{why}): #{cmd}" }
  warn "zsh_split_scan --selftest: #{CASES.size - bad.size}/#{CASES.size} ok"
  exit(bad.empty? ? 0 : 1)
end

findings($stdin.read).each do |rule, name, tok, list|
  if rule == 'C2'
    head = name == 'set --' ? "set -- #{tok}" : "for #{name} in #{tok}"
    puts "#{head}  ← the list is an unsplit scalar, so this runs ONCE"
  else
    puts "for #{name} in #{list[0, 46]}…  ← the body re-splits $#{name}"
  end
end
exit 0
