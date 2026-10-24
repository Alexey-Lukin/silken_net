# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# [OPS.22] solid_cable 4.1.0 — the `solid_cable:update` generator's `remove_channel_index`.
# The listener matches by `channel_hash` since 4.1.0, so no read uses the `channel` index and
# every broadcast INSERT still pays for it. Upstream's template, in the concurrent form
# strong_migrations requires; `if_exists` because a cable DB born from the regenerated
# `db/cable_structure.sql` never had the index (`db:prepare` loads that file on a cold slot).
class RemoveChannelIndex < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    remove_index :solid_cable_messages, :channel, algorithm: :concurrently, if_exists: true
  end

  def down
    add_index :solid_cable_messages, :channel, algorithm: :concurrently, if_not_exists: true
  end
end
