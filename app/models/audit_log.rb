# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

class AuditLog < ApplicationRecord
  # --- КОНСТАНТИ ---
  # Namespace для pg_advisory_xact_lock — ізолює chain locks від інших advisory locks
  CHAIN_LOCK_NS = 827_549_841
  # Генезис-хеш для першого запису в ланцюзі організації
  GENESIS_HASH = "GENESIS"

  # --- ЗВ'ЯЗКИ ---
  belongs_to :user
  # [ARCH.57] nil = ГЛОБАЛЬНИЙ системний ланцюг (org-less привілейовані дії:
  # SystemParameter-зміни). Кожен ланцюг ізольований per organization_id;
  # NULL-група — окремий ланцюг з advisory-lock ключем 0 (org.id ≥ 1, колізії нема).
  belongs_to :organization, optional: true
  belongs_to :auditable, polymorphic: true, optional: true

  # --- ВАЛІДАЦІЇ ---
  validates :action, presence: true
  validates :ip_address, length: { maximum: 45 }, allow_blank: true

  # --- КОЛБЕКИ ---
  # Immutable Integrity Chain: кожен запис містить SHA-256 хеш
  # попереднього запису + payload, утворюючи локальний блокчейн per organization
  before_create :compute_chain_hash

  # [ARCH.57] Append-only: мутація бізнес-полів тихо ламає hash-ланцюг
  # (verify_chain_integrity), тож програмного шляху зміни не існує. Дозволені
  # лише архівні поля (Filecoin pin ставить ipfs_cid post-create). delete_all/
  # update_all обходять колбеки — org-каскад закрито restrict_with_error.
  ARCHIVAL_MUTABLE_COLUMNS = %w[ipfs_cid archive_requested_at updated_at].freeze

  # [SEC.18 / DPIA захід M6 проти ризику R7] Стеля на вміст `metadata`, що їде в
  # ПУБЛІЧНИЙ пін: запінене не відкликається, тож персональне поле, потрапивши сюди,
  # стає нестиральним фізично. Перелік — ДЕКЛАРАЦІЯ людини (той самий принцип, яким
  # стоїть PII-реєстр `04_01 §11`), а не вивід регексу: чи є значення персональним,
  # форма ключа не каже. Сьогодні archive-шлях має рівно одного писача —
  # `BlockchainTransaction#record_money_audit_trail`; `Auditable` дефолтить
  # `archive: false` свідомо (security/ops-метадані на публічний IPFS не йдуть — INF.22).
  # ⚠️ Стеля самої стелі лишається: цей перелік судить КЛЮЧІ, ніколи ЗНАЧЕННЯ. Але
  # єдиний ключ, що ніс ВІЛЬНИЙ текст, звужено на ПИСАЧІ — `error` тепер несе КОД
  # (`Web3::TransactionErrorClassifier`, ⚖️ 2026-08-27), тож стеля вже не має відомого
  # каналу витоку. 🔴 Звужено саме на писачі, а не на межі піна, свідомо: пін мусить
  # бути ВІРНОЮ копією аудит-запису — інакше аудитор, звіряючи пін із рядком, бачив би
  # розбіжність, і пін перестав би бути доказом. ✅ Другий вільнотекстовий канал того ж
  # піна — `telemetry_summary` (не `metadata`, тож ПОЗА цим переліком за побудовою) —
  # закрито 2026-08-27 іншим ліком: `AiInsight#summary` із піна ЗНЯТО зовсім, бо він
  # інтерполював `cluster.name`, а решта рядка й так несе величини, з яких проза
  # рендериться (дім — `Filecoin::ArchiveService#build_telemetry_summary`). 🔑 Два
  # канали, два різні ліки, і різницю робить не смак: `error` є ЄДИНИМ джерелом свого
  # факту, тож його звужують до коду; `summary` джерелом не був — тому дешевше зняти
  # поверхню, ніж класифікувати її вміст.
  ARCHIVED_METADATA_KEYS = %w[
    from to token_type amount tx_hash error telemetry_merkle_root
  ].freeze
  before_update :forbid_business_field_mutation!
  before_destroy { raise ActiveRecord::ReadOnlyRecord, "AuditLog append-only [ARCH.57]" }

  # --- СКОУПИ ---
  scope :recent, -> { order(created_at: :desc) }
  scope :by_action, ->(action) { where(action: action) if action.present? }
  scope :by_user, ->(user_id) { where(user_id: user_id) if user_id.present? }
  scope :by_ip, ->(ip) { where(ip_address: ip) if ip.present? }
  scope :for_period, ->(from, to) { where(created_at: from..to) if from.present? && to.present? }
  scope :archived, -> { where.not(ipfs_cid: nil) }
  scope :not_archived, -> { where(ipfs_cid: nil) }
  # [INF.22 крок 11] Outbox-eligibility: archivable = money/MRV-лог, який AuditLogWorker
  # явно позначив `archive_requested_at` у create-транзакції. Factory/console прямий `create!`
  # маркер НЕ ставлять → природно поза archive-периметром (без евристики по auditable_type).
  # pending_archive = archivable, ще не запінене — саме це дренажить FilecoinReconcileWorker
  # (partial index `index_audit_logs_pending_archive` дзеркалить цей предикат).
  scope :archivable, -> { where.not(archive_requested_at: nil) }
  scope :pending_archive, -> { archivable.not_archived }

  # ---------------------------------------------------------------------------
  # Hot-Path: асинхронний запис через Sidekiq (не блокує основну дію користувача)
  # ---------------------------------------------------------------------------
  # archive: true → AuditLogWorker ставить outbox-маркер `archive_requested_at` +
  # Filecoin/IPFS-пін (money/MRV-докази). archive: false → chain-only [ARCH.57]:
  # security/ops-метадані (ключі, ролі, актуатори) НЕ пінити на публічний IPFS
  # (INF.22 over-exposure клас) — tamper-evidence дає сам hash-ланцюг.
  def self.record_async!(attrs, archive: true)
    AuditLogWorker.perform_async(attrs.deep_stringify_keys, archive)
  end

  # ---------------------------------------------------------------------------
  # Hot-Path: масовий запис через insert_all (один INSERT замість N)
  # Chain hashes обчислюються послідовно per organization перед вставкою.
  # ---------------------------------------------------------------------------
  # ⚠️ [INF.22] bulk_record! НЕ виставляє `archive_requested_at` outbox-маркер і НЕ enqueue'ить
  # FilecoinArchiveWorker (обходить AuditLogWorker) → ці логи НЕ архівуються на IPFS і невидимі
  # FilecoinReconcileWorker. 0 prod-callers сьогодні (лише specs); якщо зʼявиться money/MRV
  # bulk-шлях, що потребує архівації — виставляти маркер тут + enqueue (або йти через record_async!).
  def self.bulk_record!(entries)
    return if entries.blank?

    now = Time.current
    rows = entries.map do |entry|
      entry.reverse_merge(created_at: now, updated_at: now, metadata: {}).stringify_keys
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

  # Канонічний payload для chain hash — детермінований рядок з бізнес-полів.
  # [ARCH.57] created_at/ip_address/user_agent У ЛАНЦЮЗІ: без них timestamp/actor-tamper
  # через update_all (повз append-only колбек) був невидимий для verify_chain_integrity.
  def chain_payload
    self.class.chain_payload_from_row(
      "organization_id" => organization_id,
      "user_id" => user_id,
      "action" => action,
      "auditable_type" => auditable_type,
      "auditable_id" => auditable_id,
      "metadata" => metadata,
      "created_at" => created_at,
      "ip_address" => ip_address,
      "user_agent" => user_agent
    )
  end

  # --- ПРИВАТНІ МЕТОДИ ---

  def self.chain_payload_from_row(row)
    # Сортуємо ключі metadata для детермінованого хешу,
    # бо PostgreSQL JSONB не гарантує порядок ключів
    meta = row["metadata"]
    meta_str = meta.is_a?(Hash) ? meta.sort_by { |k, _| k.to_s }.to_h.to_json : meta.to_s

    [
      row["organization_id"],
      row["user_id"],
      row["action"],
      row["auditable_type"],
      row["auditable_id"],
      meta_str,
      canonical_timestamp(row["created_at"]),
      row["ip_address"].to_s,
      row["user_agent"].to_s
    ].join("|")
  end

  # [ARCH.57] Канонічна форма timestamp'а для хешу: UTC + мікросекунди (iso8601(6)
  # ТРІМИТЬ ns → µs — та сама операція, що PG timestamp(6)-серіалізація, тож значення
  # до insert і після reload дають ідентичний рядок незалежно від таймзони процесу).
  # ⚠️ Стеля String-гілки: рядок МУСИТЬ нести явний offset (iso8601) — naive-рядок
  # Time.zone.parse інтерпретує в поточній зоні → хибний tamper при не-UTC Time.zone.
  def self.canonical_timestamp(value)
    return "" if value.blank?

    time = value.acts_like?(:time) ? value : Time.zone.parse(value.to_s)
    time.utc.iso8601(6)
  end

  private

  def forbid_business_field_mutation!
    illegal = changed - ARCHIVAL_MUTABLE_COLUMNS
    return if illegal.empty?

    raise ActiveRecord::ReadOnlyRecord,
          "AuditLog append-only [ARCH.57]: спроба змінити #{illegal.join(', ')}"
  end

  def compute_chain_hash
    # Advisory lock per organization запобігає race condition
    # при конкурентних записах (Sidekiq workers).
    # Prosopite.pause: ці запити виконуються в before_create колбеку і є
    # навмисно повторюваними (один раз на кожен новий запис у ланцюзі).
    Prosopite.pause if defined?(Prosopite)

    # [ARCH.57] created_at входить у payload → фіксуємо ДО хешування, щоб значення
    # в хеші гарантовано збіглося зі збереженим (незалежно від порядку AR-колбеків).
    self.created_at ||= Time.current

    # nil.to_i = 0 → глобальний (org-less) ланцюг має власний lock-ключ.
    self.class.connection.execute(
      "SELECT pg_advisory_xact_lock(#{CHAIN_LOCK_NS}, #{organization_id.to_i})"
    )

    previous_hash = self.class
                      .where(organization_id: organization_id)
                      .order(id: :desc)
                      .pick(:chain_hash) || GENESIS_HASH

    self.chain_hash = Digest::SHA256.hexdigest("#{previous_hash}|#{chain_payload}")
  ensure
    Prosopite.resume if defined?(Prosopite)
  end
end
