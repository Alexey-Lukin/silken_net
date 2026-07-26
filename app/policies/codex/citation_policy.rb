# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# Codex::CitationPolicy — full RBAC for the citations surface (create/destroy via
# API; reads happen inline in target view components, no dedicated read endpoint).
# `update?` has no live caller yet — no admin edit route exists for citations.
#
# Read: any authenticated user.
# Create: forester+ (operational citation = treats lore as production data).
# Update / destroy: own ≤ 24h, or admin+.
module Codex
  class CitationPolicy < ApplicationPolicy
    def index?
      user.present?
    end

    def show?
      user.present?
    end

    def create?
      forester_or_above?
    end

    def update?
      owner_within_grace? || admin_or_above?
    end

    def destroy?
      owner_within_grace? || admin_or_above?
    end

    private

    def owner_within_grace?
      record.created_by_user_id == user.id && record.created_at >= 24.hours.ago
    end
  end
end
