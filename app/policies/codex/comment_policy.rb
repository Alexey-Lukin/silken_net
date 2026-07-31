# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# Codex::CommentPolicy — author-edits ≤ 24h; admin+ may *hide* (never
# destroy) per docs/04_01 §7b. Anonymous users may not even read the thread
# (the host node already requires auth, so this is just a defence in depth).
module Codex
  class CommentPolicy < ApplicationPolicy
    def index?
      user.present?
    end

    def show?
      user.present? && (!record.hidden? || admin_or_above?)
    end

    def create?
      user.present?
    end

    def update?
      author_within_grace? || admin_or_above?
    end

    def destroy?
      author_within_grace? || admin_or_above?
    end

    def hide?
      admin_or_above?
    end

    class Scope < ::ApplicationPolicy::Scope
      def resolve
        return scope.all if user&.admin_or_above?
        scope.visible
      end
    end

    private

    def author_within_grace?
      user.present? && record.user_id == user.id &&
        record.created_at >= ::Codex::Comment::EDIT_GRACE.ago
    end
  end
end
