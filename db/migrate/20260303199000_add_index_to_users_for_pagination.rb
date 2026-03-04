# frozen_string_literal: true

# Composite index to support efficient pagination of users ordered by
# (last_seen_at DESC, id DESC) within an organization.
# Without this, ORDER BY + LIMIT scans the full users table as org grows.
class AddIndexToUsersForPagination < ActiveRecord::Migration[8.1]
  def change
    add_index :users, [ :organization_id, :last_seen_at, :id ],
              name: "index_users_on_org_last_seen_id",
              order: { last_seen_at: :desc, id: :desc }
  end
end
