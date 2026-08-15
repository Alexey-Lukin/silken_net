# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

class MaintenanceRecord < ApplicationRecord
  include GeoLocatable
  # [SEC.28] Evidence-мутації входять у ланцюг аудиту (присуд власника 2026-08-14).
  # Периметр `Auditable` будувався під governance/money/hardware, і фотодоказ
  # виглядав вужчим класом — але він несе ДОКАЗОВУ БАЗУ D-MRV, тобто саме те,
  # заради чого ланцюг існує (критерій місії: «невідбирано»).
  #
  # 🔴 Вагу тут дає ПАРА властивостей, не одна: видалення незворотне
  # (`purge_later` → S3) І безслідне. Разом це множник — та сама помилка
  # авторизації коштує тут дорожче, ніж на сусідніх поверхнях, бо наслідок не
  # відновлюється й не розслідується. Слід знімає другу половину; перша
  # (м'яке видалення) свідомо відкладена до `SEC.18` — ретеншен і GDPR-стирання
  # це ОДНА політика, і вирішувати її тут означало б завести другий дім.
  #
  # ⚠️ **`include Auditable` тут свідомо НЕМА, і це не пропуск.** Concern віддає
  # рівно один метод — `record_audit_trail!`, обгортку над `record_async!`. Але
  # слід про знищення доказу мусить бути СИНХРОННИМ (інакше при зупиненому
  # Sidekiq фото зникає незворотно, а сліду не лишається взагалі — тобто
  # асинхронність відтворює рівно ту пару властивостей, проти якої SEC.28 і
  # стоїть), тож писач іде через `AuditLog.create!` — той самий прецедент, що
  # `organizations_controller#record_switch!`. Дім виклику —
  # `MaintenanceRecordPhotosController#record_audit_trail_for_purge!`;
  # включений concern був би тут мертвим кодом.
  #
  # ⚠️ Хук-форма (`after_update_commit if: :saved_change_to_X?`) до цієї осі не
  # застосовна за побудовою: зникає ВКЛАДЕННЯ, а не колонка.
  # --- ЗВ'ЯЗКИ ---
  belongs_to :user
  belongs_to :maintainable, polymorphic: true
  belongs_to :ews_alert, optional: true

  # Evidence Protocol (Trust Protocol) — фото до/після для аудиту Series C.
  # Variant :thumb генерується VIPS у фоні (queued job), не блокуючи запит.
  # При десятках мільйонів записів: зберігання на S3 + GCS mirror, роздача через CDN.
  has_many_attached :photos do |attachable|
    attachable.variant :thumb, resize_to_limit: [ 200, 200 ]
  end

  # --- ТИПИ РОБІТ (The Intervention) ---
  # biomass_extraction (5) — Afterlife Economy: extraction of dead wood for
  # Puro.earth Biochar CORC certification. Triggers D-MRV "Biomass Passport"
  # generation via PuroEarthPassportWorker, anchoring provenance on-chain.
  enum :action_type, {
    installation: 0,      # Монтаж
    inspection: 1,        # Огляд
    cleaning: 2,          # Очищення (панелі/датчики)
    repair: 3,            # Ремонт заліза
    decommissioning: 4,   # Демонтаж
    biomass_extraction: 5  # Вилучення біомаси (Puro.earth Biochar)
  }, prefix: true

  # [I18N.1] Людська назва ДІЇ обслуговування — найбільша enum-родина дерева.
  # Скоуп належить домену МОДЕЛІ, не компоненту (`04_04 §12.14`).
  #
  # ⚠️ Мітка ≠ значення: сире значення лишається в URL-параметрі фільтра
  # (`maintenance_records_path(action_type: type)`) і в логіці
  # (`%w[repair installation].include?`) — локалізувати треба ПОКАЗ, і плутати ці
  # три роди вжитку тут особливо легко, бо вони стоять в одному файлі.
  ACTION_TYPE_LABEL_SCOPE = "maintenance.action_types"

  # ОДНА деривація ключа. Fail-open: новий член enum'а рендериться сирим значенням,
  # доки мітка не доїде в локалі — і саме це червонить гейт парності.
  def self.action_type_label(action_type)
    value = action_type.to_s
    I18n.t("#{ACTION_TYPE_LABEL_SCOPE}.#{value}", default: value)
  end

  def action_type_label
    self.class.action_type_label(action_type)
  end

  # --- ВАЛІДАЦІЇ ---
  validates :action_type, :performed_at, presence: true
  validates :notes, presence: true, length: { minimum: 10 }
  validates :performed_at, comparison: { less_than_or_equal_to: -> { Time.current } }

  # OpEx-метрики для unit-економіки (Series C Financial Tracking)
  validates :labor_hours, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :parts_cost,  numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  # Hardware State Sync
  validates :hardware_verified, inclusion: { in: [ true, false ] }

  # Afterlife Economy: biomass yield is mandatory for extraction records (D-MRV proof)
  validates :biomass_yield_kg, presence: true,
            numericality: { greater_than: 0 },
            if: :action_type_biomass_extraction?

  # Evidence Protocol: фото обов'язкові при монтажі та ремонті.
  # Виняток для системних записів несе КОЛОНКА `system_generated`, а не
  # транзієнтна ознака: валідація оголошена без `on:`, тож біжить на кожен
  # `save`, і виняток, що не переживає reload, робить запис невиправно
  # невалідним після першого ж `find` [ARCH.91].
  validate :photos_required_for_critical_actions

  # Тип вкладень — тільки зображення, max 20 МБ кожне, max 10 фото на запис
  # [I18N.4] `message:` тут СВІДОМО немає: `active_storage_validations` везе власні
  # i18n-ключі (`errors.messages.content_type_invalid` / `file_size_not_less_than` /
  # `limit_out_of_range`) у 17 локалях, включно з `uk`. Зашитий рядок їх ПЕРЕКРИВАВ —
  # тобто англієць бачив українську, — і заразом губив числа: гемове повідомлення
  # несе `%{max}` і `%{file_size}`, наше не несло. `lv`/`lt` гем не має, тож вони
  # перекриті в `config/locales/errors/{lv,lt}.yml`.
  validates :photos,
            content_type: { in: %w[image/jpeg image/png image/webp image/heic image/heif] },
            size: { less_than: 20.megabytes },
            limit: { max: 10 }

  # --- СКОУПИ ---
  scope :recent,            -> { order(performed_at: :desc) }
  scope :by_type,           ->(type) { where(action_type: type) }
  scope :hardware_verified, -> { where(hardware_verified: true) }
  scope :with_gps,          -> { where.not(latitude: nil, longitude: nil) }

  # =========================================================================
  # КОЛБЕКИ (The Healing Protocol)
  # =========================================================================

  # [ВИПРАВЛЕНО]: Ми відмовилися від heal_ecosystem! всередині моделі.
  # Замість цього запускаємо асинхронний воркер, що гарантує 100% доставку
  # змін статусу навіть при тимчасових збоях бази даних.
  after_create_commit :trigger_ecosystem_healing!

  # =========================================================================
  # МЕТОДИ
  # =========================================================================

  # OpEx-вартість одного запису для звітності Series C.
  # Базова ставка 50 $/год — override через ENV для регіональних ринків.
  LABOR_RATE_PER_HOUR = ENV.fetch("PATROL_LABOR_RATE", 50).to_f

  def total_cost
    (labor_hours.to_f * LABOR_RATE_PER_HOUR) + parts_cost.to_f
  end

  # [UI.6] Дім правила «хто може мутувати цей запис»: автор або admin+.
  #
  # Правило доти жило приватним методом контролера, тож UI дістати його не міг — і саме
  # тому кнопки `verify`/`edit`/«×» рендерились кожному, хто відкрив сторінку. Тут воно
  # доступне ОБОМ споживачам (гард і компонент), тобто не форкається; роль-формулу теж
  # не форкає — кличе `User#admin_or_above?` ([`04_03 §3`](04_03_REST_API_v1_Reference)).
  #
  # ⚠️ Про тенансі цей предикат мовчить СВІДОМО: приналежність тримає асоціативний скоуп
  # у викликача (`acting_organization!.clusters` → `set_record`), і це канонічний поділ
  # двох ідіомів — предикат відповідає на «роль × авторство», асоціація на «чиє це».
  # Отже викликач ЗОБОВ'ЯЗАНИЙ дістати запис org-скоупленим запитом: adminʼу чужої
  # організації цей метод скаже `true`, бо про організацію його не питали.
  def mutable_by?(actor)
    return false if actor.blank?

    actor.admin_or_above? || user_id == actor.id
  end

  private

  def trigger_ecosystem_healing!
    # Викликаємо "М'яз зцілення" (NAM-ŠID Healing).
    # Він обробить і логіку актуаторів, і закриття EwsAlert із вірними префіксами (status_resolved?).
    EcosystemHealingWorker.perform_async(self.id)
  end

  # Trust Protocol: ремонт і монтаж без фото — не proof of care, а просто слова.
  # Платформа камери не має, тому її власні записи звільнені — і саме тому
  # `system_generated` не входить у `maintenance_params`: інакше клієнт знімав
  # би з себе Evidence Protocol одним полем форми.
  def photos_required_for_critical_actions
    return if system_generated?
    return unless action_type_repair? || action_type_installation?
    return if photos.any?

    errors.add(:photos, :required_for_action_type)
  end
end
