# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# [SEC.25 Ф2] `UserContext` carries the pair «who asks + in WHICH organization's
# context», because the request's organization is no longer derivable from the user:
# a super_admin works inside ONE organization at a time and switches it.
#
# The class is deliberately tiny, and its ONE branch is the security-relevant one —
# `organization&.id` on a context built without an organization. That path had no pin,
# so nothing stated what the scope resolves to when the acting organization is absent;
# an implementation that quietly answered something truthy there would widen every
# policy keyed on `organization_id` (the very fail-OPEN the class's own header warns
# about for `delegate_missing_to`).
RSpec.describe UserContext do
  let(:organization) { create(:organization) }
  let(:user) { create(:user, organization: organization) }

  describe "#organization_id" do
    it "returns the acting organization's id" do
      expect(described_class.new(user, organization).organization_id).to eq(organization.id)
    end

    # fail-closed: no acting organization ⇒ no scope, never a truthy stand-in
    it "returns nil when no organization is in context" do
      expect(described_class.new(user, nil).organization_id).to be_nil
    end
  end

  describe "the user it carries" do
    # The header states this as a MEASUREMENT, not a preference: the context must not
    # stand in for the user, or `user.present?` — the base RBAC primitive of the codex
    # branch — would answer true around a nil user and invert every guard built on it.
    it "keeps the user itself, so nil stays nil" do
      expect(described_class.new(nil, organization).user).to be_nil
    end

    it "exposes the real user object rather than a wrapper" do
      expect(described_class.new(user, organization).user).to eq(user)
    end
  end
end
