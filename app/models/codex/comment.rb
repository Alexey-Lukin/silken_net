# frozen_string_literal: true

# Codex::Comment — single-level threaded discussion attached polymorphically
# to any "commentable" Codex resource (Phase 2 only writes nodes; the column
# shape leaves room for future surfaces — e.g. Match recap, Discovery toast).
#
# Moderation philosophy (per docs/04_05 §5):
#   * authors may edit/delete their own row within 24h;
#   * admin+ moderators *hide* (`hidden_at` + `hidden_by_admin_id`) — never
#     destroy — preserving a tamper-evident moderation trail.
#
# Threading is bounded to one nesting level; this is enforced in the model
# (not the schema), so Phase 4's "deep threads" experiment can remove it
# without a migration.
module Codex
  class Comment < ApplicationRecord
    self.table_name = "codex_comments"

    BODY_MAX = 2 * 1024
    EDIT_GRACE = 24.hours

    FLAG_REASONS = %w[spam abuse offtopic other].freeze

    belongs_to :user
    belongs_to :commentable, polymorphic: true, counter_cache: :comments_count
    belongs_to :parent,
               class_name: "Codex::Comment",
               optional: true,
               inverse_of: :replies
    has_many   :replies,
               class_name: "Codex::Comment",
               foreign_key: :parent_id,
               inverse_of: :parent,
               dependent: :destroy
    belongs_to :hidden_by_admin,
               class_name: "User",
               optional: true

    validates :body_md, presence: true, length: { maximum: BODY_MAX }
    validates :flag_reason, inclusion: { in: FLAG_REASONS }, allow_nil: true
    validate  :parent_must_be_top_level
    validate  :parent_must_share_commentable

    scope :visible,    -> { where(hidden_at: nil) }
    scope :hidden,     -> { where.not(hidden_at: nil) }
    scope :top_level,  -> { where(parent_id: nil) }
    scope :chronological, -> { order(:created_at) }

    def hidden? = hidden_at.present?
    def editable_by?(other_user)
      return false if other_user.blank?
      user_id == other_user.id && created_at >= EDIT_GRACE.ago
    end

    private

    # One nesting level only — the schema can store deeper trees but the
    # UI/UX assumes a single reply tier. Trying to reply to a reply is a
    # validation error (HTTP 422) rather than a silent data corruption.
    def parent_must_be_top_level
      return if parent_id.blank?
      return if parent.present? && parent.parent_id.nil?

      errors.add(:parent_id, "must reference a top-level comment")
    end

    # A reply must hang off the same commentable as its parent; otherwise
    # `comments_count` would diverge from the visible thread.
    def parent_must_share_commentable
      return if parent.blank?
      return if parent.commentable_type == commentable_type &&
                parent.commentable_id == commentable_id

      errors.add(:parent_id, "must belong to the same commentable")
    end
  end
end
