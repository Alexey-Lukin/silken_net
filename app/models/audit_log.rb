# frozen_string_literal: true

class AuditLog < ApplicationRecord
  # --- КОНСТАНТИ ---
  # Namespace для pg_advisory_xact_lock — ізолює chain locks від інших advisory locks
  CHAIN_LOCK_NS = 827_549_841
  # Генезис-хеш для першого запису в ланцюзі організації
  GENESIS_HASH = "GENESIS"

  # --- ЗВ'ЯЗКИ ---
  belongs_to :user
  belongs_to :organization
  belongs_to :auditable, polymorphic: true, optional: true

  # --- ВАЛІДАЦІЇ ---
  validates :action, presence: true
  validates :ip_address, length: { maximum: 45 }, allow_blank: true

  # --- КОЛБЕКИ ---
  # Immutable Integrity Chain: кожен запис містить SHA-256 хеш
  # попереднього запису + payload, утворюючи локальний блокчейн per organization
  before_create :compute_chain_hash

  # --- СКОУПИ ---
  scope :recent, -> { order(created_at: :desc) }
  scope :by_action, ->(action) { where(action: action) if action.present? }
  scope :by_user, ->(user_id) { where(user_id: user_id) if user_id.present? }
  scope :by_ip, ->(ip) { where(ip_address: ip) if ip.present? }
  scope :for_period, ->(from, to) { where(created_at: from..to) if from.present? && to.present? }

  # ---------------------------------------------------------------------------
  # Hot-Path: асинхронний запис через Sidekiq (не блокує основну дію користувача)
  # ---------------------------------------------------------------------------
  def self.record_async!(attrs)
    AuditLogWorker.perform_async(attrs.deep_stringify_keys)
  end

  # ---------------------------------------------------------------------------
  # Hot-Path: масовий запис через insert_all (один INSERT замість N)
  # Chain hashes обчислюються послідовно per organization перед вставкою.
  # ---------------------------------------------------------------------------
  def self.bulk_record!(entries)
    return if entries.blank?

    now = Time.current
    rows = entries.map do |entry|
      entry.reverse_merge(created_at: now, updated_at: now).stringify_keys
    end

    transaction do
      rows_by_org = rows.group_by { |r| r["organization_id"] }

      rows_by_org.each do |org_id, org_rows|
        # Advisory lock per organization — паралельні org'и не блокуються
        connection.execute(
          "SELECT pg_advisory_xact_lock(#{CHAIN_LOCK_NS}, #{org_id.to_i})"
        )

        previous_hash = where(organization_id: org_id)
                          .order(id: :desc)
                          .pick(:chain_hash) || GENESIS_HASH

        org_rows.each do |row|
          payload = chain_payload_from_row(row)
          row["chain_hash"] = Digest::SHA256.hexdigest("#{previous_hash}|#{payload}")
          previous_hash = row["chain_hash"]
        end
      end

      insert_all(rows)
    end
  end

  # ---------------------------------------------------------------------------
  # Integrity Verification: перевіряє цілісність ланцюга per organization
  # Повертає { valid: true, verified_count: N } або { valid: false, broken_at: ID }
  # ---------------------------------------------------------------------------
  def self.verify_chain_integrity(organization_id)
    logs = where(organization_id: organization_id)
             .where.not(chain_hash: nil)
             .order(:id)

    previous_hash = GENESIS_HASH
    count = 0

    logs.find_each do |log|
      expected = Digest::SHA256.hexdigest("#{previous_hash}|#{log.chain_payload}")
      if expected != log.chain_hash
        return { valid: false, broken_at: log.id, expected: expected, actual: log.chain_hash }
      end

      previous_hash = log.chain_hash
      count += 1
    end

    { valid: true, verified_count: count }
  end

  # Канонічний payload для chain hash — детермінований рядок з бізнес-полів
  def chain_payload
    self.class.chain_payload_from_row(
      "organization_id" => organization_id,
      "user_id" => user_id,
      "action" => action,
      "auditable_type" => auditable_type,
      "auditable_id" => auditable_id,
      "metadata" => metadata
    )
  end

  # --- ПРИВАТНІ МЕТОДИ ---

  # Формує канонічний payload з хеша атрибутів (для bulk_record! та chain_payload)
  def self.chain_payload_from_row(row)
    [
      row["organization_id"],
      row["user_id"],
      row["action"],
      row["auditable_type"],
      row["auditable_id"],
      (row["metadata"].is_a?(Hash) ? row["metadata"].to_json : row["metadata"].to_s)
    ].join("|")
  end

  private

  def compute_chain_hash
    # Advisory lock per organization запобігає race condition
    # при конкурентних записах (Sidekiq workers)
    self.class.connection.execute(
      "SELECT pg_advisory_xact_lock(#{CHAIN_LOCK_NS}, #{organization_id.to_i})"
    )

    previous_hash = self.class
                      .where(organization_id: organization_id)
                      .order(id: :desc)
                      .pick(:chain_hash) || GENESIS_HASH

    self.chain_hash = Digest::SHA256.hexdigest("#{previous_hash}|#{chain_payload}")
  end
end
