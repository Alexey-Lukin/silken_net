# SPDX-License-Identifier: AGPL-3.0-or-later
# Run using bin/ci

CI.run do
  step "Setup", "bin/setup --skip-server"

  step "Style: Ruby", "bin/rubocop"

  # [OPS.33, 2026-08-23] Був список із десяти копів, бо omakase гасив увесь
  # департамент `Lint`. Департамент увімкнено в `.rubocop.yml`, і девʼять із них
  # тепер покриває крок «Style: Ruby» вище — на ВСЬОМУ дереві. Лишається один,
  # і саме тому, що глобально його ввімкнути не можна: `spec/` тримає ~два
  # десятки хітів іншого роду (невживані фікстурні привʼязки), а гейт,
  # народжений червоним, знімає перший, кому він заважає.
  # ⚠️ Цінність кроку тепер у ПЕРИМЕТРІ, не в наборі. Дзеркало — крок
  # `Lint for dead code (perimeter without spec/)` у `.github/workflows/ci.yml`;
  # правити ОБИДВА, інакше локальна смуга й CI розійдуться мовчки.
  step "Lint: dead code", "bin/rubocop --only Lint/UselessAssignment app lib scripts config"

  step "Security: Gem audit", "bin/bundler-audit"
  step "Security: Importmap vulnerability audit", "bin/importmap audit"
  step "Security: Brakeman code analysis", "bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error"
  step "Tests: RSpec", "bundle exec rspec"
  step "Tests: Seeds", "env RAILS_ENV=test bin/rails db:seed:replant"

  # Optional: Run system tests
  # step "Tests: System", "bin/rails test:system"

  # Optional: set a green GitHub commit status to unblock PR merge.
  # Requires the `gh` CLI and `gh extension install basecamp/gh-signoff`.
  # if success?
  #   step "Signoff: All systems go. Ready for merge and deploy.", "gh signoff"
  # else
  #   failure "Signoff: CI failed. Do not merge or deploy.", "Fix the issues and try again."
  # end
end
