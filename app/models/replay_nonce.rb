# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# [SEC.39, ⚖️ founder 2026-10-24] Атомарний анти-повтор на пару (scope, digest) — форма SEC.40
# (`CcmReplayWindow`). Канон — 03_05 §2.1.
#
# Один оператор `INSERT … ON CONFLICT`: з двох конкурентних перших записів виграє рівно один, а
# прострочений ключ перезахоплюється тим самим оператором — тож коректність від прибиральника
# (`ReplayNoncePurgeWorker`) не залежить, він лише тримає таблицю малою. Доти сайти тримали nonce у
# Solid Cache, де `unless_exist:` не атомарний, а збій бази кешу повертав `false`, тобто «повтор».
#
# ⛔ Збій БД тут НЕ ковтається: «сховище впало» і «це повтор» — різні відповіді, і що робити на
# збої, вирішує кожен сайт (Sidekiq-ретрай · гучна втрата в лозі · відмова), а не ця модель.
class ReplayNonce < ApplicationRecord
  UPSERT_SQL = <<~SQL.squish
    INSERT INTO replay_nonces AS n (scope, digest, owner, expires_at, created_at, updated_at)
    VALUES (:scope, :digest, :owner, :expires_at, :now, :now)
    ON CONFLICT (scope, digest) DO UPDATE SET
      owner = EXCLUDED.owner, expires_at = EXCLUDED.expires_at, updated_at = EXCLUDED.updated_at
  SQL
  CLAIM_SQL = "#{UPSERT_SQL} WHERE n.expires_at <= :now RETURNING 1".freeze

  class << self
    # true — ключ тепер наш (свіжий або прострочений); false — живий ключ уже стоїть.
    # `uncached`: це запис у вигляді SELECT, і кеш запитів не сміє віддати чужу відповідь.
    def claim!(scope:, digest:, ttl:, owner: nil)
      connection.uncached { connection.select_value(statement(CLAIM_SQL, scope:, digest:, owner:, ttl:)) } == 1
    end

    # Власник живого ключа — двофазним сайтам, щоб відрізнити свій crash-retry від чужого повтору.
    def owner_of(scope:, digest:)
      where(scope:, digest:).where("expires_at > ?", Time.current).pick(:owner)
    end

    # Фаза 2: термінальний маркер і свіжий TTL. Upsert, не UPDATE: ключ буває взято поза цією
    # таблицею (Redis-шлях QATT), і тоді рядка немає — голий UPDATE мовчки не писав би нічого.
    def finalize!(scope:, digest:, owner:, ttl:)
      connection.execute(statement(UPSERT_SQL, scope:, digest:, owner:, ttl:))
    end

    private

    def statement(sql, scope:, digest:, owner:, ttl:)
      now = Time.current
      sanitize_sql([ sql, { scope:, digest:, owner:, expires_at: now + ttl, now: } ])
    end
  end
end
