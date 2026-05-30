# frozen_string_literal: true

# = =====================================================================
# 🛠 github:* — IaC entry-points for Projects V2 + milestone bootstrap
# = =====================================================================
# Source: docs/09_04_GitHub_Projects_and_IaC_Automation.md §1.2 + §6.
# Tracker: docs/09_06_Action_Plan_Tracker.md → OPS.6.
#
# All tasks require:
#   * `gh` CLI installed and authenticated (`gh auth status`)
#   * GH_OWNER          — GitHub user/org (default Alexey-Lukin)
#   * GH_REPO           — Repository slug (default silken_net)
#   * GH_PROJECT_NUMBER — Project V2 number (default 1)
# = =====================================================================
namespace :github do
  desc "Create missing Projects V2 fields (idempotent). ENV: GH_OWNER, GH_PROJECT_NUMBER"
  task :project_fields do
    require_relative "../github_bootstrap"

    owner = ENV.fetch("GH_OWNER", "Alexey-Lukin")
    project_number = Integer(ENV.fetch("GH_PROJECT_NUMBER", "1"))

    puts "🛠 Syncing fields on #{owner}/##{project_number}..."
    results = GithubBootstrap.sync_project_fields(owner: owner, project_number: project_number)
    results.each { |name, action| puts "  #{action == :created ? '➕' : '✓ '} #{name} (#{action})" }
    created = results.count { |_, a| a == :created }
    puts "✅ Done — #{created} created, #{results.size - created} already present"
  end

  desc "Full bootstrap: labels are pushed by git, this creates project fields + first cycle milestone"
  task :bootstrap, [ :cycle_title ] do |_t, args|
    require_relative "../github_bootstrap"

    owner = ENV.fetch("GH_OWNER", "Alexey-Lukin")
    repo = ENV.fetch("GH_REPO", "silken_net")
    project_number = Integer(ENV.fetch("GH_PROJECT_NUMBER", "1"))
    cycle_title = args[:cycle_title] || ENV["CYCLE_TITLE"] || default_cycle_title
    cycle_description = ENV["CYCLE_DESCRIPTION"]

    puts "🛠 Bootstrapping GitHub for #{owner}/#{repo} (project ##{project_number})"
    puts "   Cycle milestone: #{cycle_title}"
    puts

    result = GithubBootstrap.bootstrap(
      owner: owner, repo: repo, project_number: project_number,
      cycle_title: cycle_title, cycle_description: cycle_description
    )

    puts "Fields:"
    result[:fields].each { |name, action| puts "  #{action == :created ? '➕' : '✓ '} #{name} (#{action})" }
    puts "Milestone:"
    puts "  #{result[:milestone] == :created ? '➕' : '✓ '} #{cycle_title} (#{result[:milestone]})"
    puts
    puts "🎯 Next: push labels via `git push` (triggers labels_sync.yml)"
  end

  # Compute the current quarter as `Cycle YYYY.QN` so the operator does
  # not have to remember which cycle they are in. ENV/argument override
  # is always available.
  def default_cycle_title
    now = Time.now.utc
    quarter = (now.month - 1) / 3 + 1
    "Cycle #{now.year}.Q#{quarter}"
  end
end
