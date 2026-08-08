# SPDX-License-Identifier: AGPL-3.0-or-later
# Run using bin/ci

CI.run do
  step "Setup", "bin/setup --skip-server"

  step "Style: Ruby", "bin/rubocop"

  # Omakase turns the whole Lint department off (154 cops, 5 enabled), so a green
  # `bin/rubocop` is silent about dead code — that blindness already shipped an
  # orphaned payload in a money-path worker. Perimeter is the one measured clean;
  # `spec/` stays out on purpose (24 low-stakes hits; a gate born red gets removed).
  step "Lint: dead code", "bin/rubocop --only " \
    "Lint/UselessAssignment,Lint/UselessMethodDefinition,Lint/UnreachableCode," \
    "Lint/UnreachableLoop,Lint/DuplicateMethods,Lint/Debugger,Lint/EmptyWhen," \
    "Lint/DuplicateCaseCondition,Lint/ShadowedArgument,Lint/BinaryOperatorWithIdenticalOperands " \
    "app lib scripts config"

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
