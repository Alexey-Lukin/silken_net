# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# [TEST.12] `trees.did` дістає NOT NULL слідом за presence-валідацією моделі
# (присуд founder 2026-08-20). Доти nullable-схема лишала «дерево без DID»
# досяжним рівно для рядка повз AR (insert_all/update_column — клас ARCH.75),
# і фолбек власника у Wallets::Index пінив «власників», яких не буває.
# Після цього фолбек стереже лише те, чого схема не виражає, і названий
# захисним — обидві його гілки тепер недосяжні й для рядка повз валідацію.
class AddNotNullToTreesDid < ActiveRecord::Migration[8.1]
  def change
    safety_assured { change_column_null :trees, :did, false }
  end
end
