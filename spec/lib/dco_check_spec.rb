# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "spec_helper"
require_relative "../../scripts/dco_check"

# [UNI.20] Unit coverage for the DCO sign-off gate. Pure functions only (no git, no
# Rails): the `commits` reader is a thin `git log` shell-out, while every rule that can
# be wrong lives in `bot_author?`, `signoffs` and `verdict`. The bot case carries the
# most weight — a wrong answer there jams the weekly Dependabot queue across five
# ecosystems, which is exactly how this gate would have been reverted on day one.
RSpec.describe DcoCheck do
  def commit(name: "Oleksii Lukin", email: "dev@example.com", committer: nil, body: "")
    { sha: "0" * 40, author_name: name, author_email: email,
      committer_email: committer || email, subject: "feat: thing", body: }
  end

  describe ".bot_author?" do
    it "recognises GitHub App identities by the [bot] suffix" do
      expect(described_class.bot_author?("dependabot[bot]",
                                         "49699333+dependabot[bot]@users.noreply.github.com")).to be(true)
      expect(described_class.bot_author?("github-actions[bot]", "x@y")).to be(true)
    end

    it "does not mistake a human for a bot" do
      expect(described_class.bot_author?("Oleksii Lukin", "realvirtuozzz@example.com")).to be(false)
      # A human whose name merely mentions robots is still a human.
      expect(described_class.bot_author?("Robot Enthusiast", "human@example.com")).to be(false)
    end
  end

  describe ".signoffs" do
    it "extracts name and lower-cased email from every trailer" do
      body = "feat: thing\n\nSigned-off-by: A Dev <A.Dev@Example.COM>\n"
      expect(described_class.signoffs(body)).to eq([ [ "A Dev", "a.dev@example.com" ] ])
    end

    it "finds a sign-off that is not the last line" do
      # `git commit -s` appends, but a rebase or an amend can leave a Co-Authored-By
      # (or a blank line) after it — scanning only the final trailer block would miss it.
      body = "fix: thing\n\nSigned-off-by: A Dev <a@b.c>\nCo-Authored-By: Claude <noreply@anthropic.com>\n"
      expect(described_class.signoffs(body).map(&:last)).to eq([ "a@b.c" ])
    end

    it "returns [] when there is no trailer" do
      expect(described_class.signoffs("chore: no sign-off here\n")).to eq([])
    end
  end

  describe ".verdict" do
    it "passes a commit signed off by its author" do
      c = commit(email: "a@b.c", body: "x\n\nSigned-off-by: A Dev <a@b.c>\n")
      expect(described_class.verdict(c)).to be_nil
    end

    it "passes when the sign-off matches the COMMITTER after a rebase" do
      # A rebase rewrites the committer while preserving the author; either identity
      # certifying the work is the practical standard.
      c = commit(email: "author@x", committer: "rebaser@y",
                 body: "x\n\nSigned-off-by: R <rebaser@y>\n")
      expect(described_class.verdict(c)).to be_nil
    end

    it "fails a commit with no sign-off at all" do
      expect(described_class.verdict(commit)).to include("no Signed-off-by trailer")
    end

    it "fails a sign-off belonging to somebody else" do
      c = commit(email: "author@x", body: "x\n\nSigned-off-by: Other <other@y>\n")
      expect(described_class.verdict(c)).to include("does not match the author")
    end

    it "exempts a bot even though its sign-off email never matches its author" do
      # The verified Dependabot shape: signs as support@github.com, authors as
      # …+dependabot[bot]@users.noreply.github.com. Strict author-match would fail
      # every dependency PR; bots hold no copyright, so there is no origin to certify.
      c = commit(name: "dependabot[bot]",
                 email: "49699333+dependabot[bot]@users.noreply.github.com",
                 body: "chore(deps): bump x\n\nSigned-off-by: dependabot[bot] <support@github.com>\n")
      expect(described_class.verdict(c)).to be_nil
    end

    it "exempts a bot that did not sign off at all" do
      c = commit(name: "github-actions[bot]", email: "actions@github.com")
      expect(described_class.verdict(c)).to be_nil
    end

    it "matches the author email case-insensitively" do
      c = commit(email: "Dev@Example.com", body: "x\n\nSigned-off-by: D <dev@example.com>\n")
      expect(described_class.verdict(c)).to be_nil
    end
  end
end
