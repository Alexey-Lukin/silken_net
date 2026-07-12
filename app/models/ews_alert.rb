# frozen_string_literal: true

class EwsAlert < ApplicationRecord
  include AASM

  # --- ЗВ'ЯЗКИ ---
  # [FIX]: cluster optional — дерево може бути без кластера (одиноке дерево / тестова інсталяція)
  belongs_to :cluster, optional: true
  belongs_to :tree, optional: true
  belongs_to :resolver, class_name: "User", foreign_key: "resolved_by", optional: true

  # --- СТАТУСИ ТА РІВНІ ---
  # [СИНХРОНІЗОВАНО]: prefix: true гарантує виклики status_active? та status_resolved?
  enum :status, { active: 0, resolved: 1, ignored: 2 }, prefix: true
  enum :severity, { low: 0, medium: 1, critical: 2 }, prefix: true

  enum :alert_type, {
    severe_drought: 0,    # Гідрологічний стрес
    insect_epidemic: 1,   # Короїд (TinyML)
    # [SLASH-1] Відкриття корпусу / доведений tamper — ЄДИНИЙ позитивний Кат-A сигнал
    # (Slashing::CauseEvidence#positive_a? → необоротний slash). ⚠️ Автоматичного джерела
    # НАРАЗІ НЕМАЄ: wire status=3 = vm_error (софт-збій, НЕ tamper → firmware_fault нижче),
    # а справжня пилка їде panic→chainsaw_detected (поза A-сетом до field-validation).
    # Створюється лише вручну — Field-Audit C→A ескалація (console, 06_08 §4) — або
    # майбутнім validated-джерелом (chainsaw після DAO-ратифікації / HW tamper-канал).
    # Тип живий свідомо: ворота positive-A лишаються wired, чесно-порожні.
    vandalism_breach: 2,
    fire_detected: 3,     # Пожежа
    seismic_anomaly: 4,   # Землетрус
    system_fault: 5,      # Поломка шлюзу/актуатора/сенсора
    entropy_anomaly: 6,   # Зниження ентропії Z-розподілу (передстресовий сигнал)
    # [SLASH-1] Аудит на місці — причина невизначена: дерево замовкло (no-data blackout),
    # freeze без прямого доказу Категорії A, або страховий кандидат чекає незалежного
    # підтвердження. Свідомо ОКРЕМИЙ від system_fault (поломка заліза/зв'язку), щоб дедуп не
    # конфлатив сигнали і freeze-алерт не накручував penalty_factor через comms_no_ack? (gap-D).
    # «Тиша замовклого дерева — теж його голос» — ескалюємо слухати, не караємо наосліп.
    field_audit: 7,
    # [ARCH.54 Шар 0] Rails сам помітив тишу шлюзу (dead-man switch,
    # GatewayStalenessSweepWorker): last_seen_at прострочив sleep-інтервал з
    # люфтом → кластер осліп, permanence-моніторинг NaaS провис. ОКРЕМИЙ від
    # system_fault (там Королева ДОПОВІЛА про свій збій; тут вона МОВЧИТЬ —
    # протилежні сигнали для тріажу лісника).
    queen_offline: 8,
    # [ARCH.34 Шар 2] Королева САМА кричить через Helium LoRaWAN, що втратила
    # всі власні uplink'и (Starlink/LTE + Q2Q) — телеметрія буферизується у
    # Flash-ринг, потрібна ескалація (виїзд). Дзеркальний до queen_offline:
    # там мовчання, тут — крик через чужі hotspot'и (06_08 §1.2 L3).
    queen_uplink_lost: 9,
    # [SLASH-1] Акустична аномалія БЕЗ термального сигналу (TinyML chainsaw/cavitation
    # → StatusByte anomaly при нормальній температурі) — вирубка, не вогонь. До спліту
    # жила у fire_detected → FIRMS бачив «ясне небо» → жертву вирубки таврував
    # rejected_fraud; тепер non-fire маршрут → Field-Audit (перевірити пеньки).
    # ⚠️ НЕ в A-сет slash'а до field-validation TinyML (клас = synthetic placeholder,
    # 03_03 §4.2) — DAO-ратифікація, Slashing::CauseEvidence лишається tamper-only.
    chainsaw_detected: 10,
    # [SLASH-1] Софт-збій прошивки пристрою: wire status=3 (BIO_STATUS_VM_ERROR —
    # mruby-crash / VM-OOM / unprovisioned). Vendor-attributable, ops-тріаж (re-flash /
    # OTA), НЕ біо-сигнал і НЕ вина оператора: не в A-сеті (vandalism_breach ↑), не в
    # comms_no_ack? whitelist (вузол ЖИВИЙ — радіо працює, зламаний лише mruby) і
    # виключений з critical_unmaintained? — не карати оператора за наш баг.
    firmware_fault: 11,
    # [SEC.20] Auto-fallback стався: вузол стер биту OTA-версію і біжить embedded
    # baseline (wire fw-report: reverted-біт). ОКРЕМИЙ від firmware_fault —
    # той транзієнтний (vm_error щоцикл, гасне сам), цей ТЕРМІНАЛЬНИЙ: вихід
    # лише через re-issue OTA з версією СТРОГО вищою за спалену (anti-rollback
    # приплив 0x15 не воскрешає стару — 03_06 §4 bump-інваріант). Різні
    # ops-дії = різні типи. Slash-виключення дзеркалять firmware_fault:
    # vendor-attributable, не A-сет, не comms_no_ack?, не critical_unmaintained?.
    firmware_reverted: 12,
    # [SEC.21] Спрацювала стек-канарка (__stack_chk_fail → reset → 0x57):
    # переписаний кадр стека на attacker-reachable парсері = потенційна
    # СПРОБА експлойту, але НЕ фізичний tamper корпусу → НЕ A-сет (доказ
    # не positive-A), не comms (вузол живий), не critical_unmaintained?
    # (виїзд не лікує софт-атаку; тріаж = security-ревізія + Field-Audit
    # ескалація вручну). Trust L0-observational (ECB без MIC) — подія
    # ніколи не рухає money-path.
    firmware_canary_trip: 13
  }, prefix: true

  # [COSMIC EYE]: Статус супутникової верифікації через dClimate.
  # Подвійний консенсус для запобігання страховому шахрайству.
  enum :satellite_status, {
    unverified: 0,      # Очікує перевірки супутником
    verified: 1,        # Підтверджено супутником (fire_confirmed)
    rejected_fraud: 2,  # Відхилено — ясне небо, без пожежі (slashing)
    inconclusive: 3     # Хмарність/кронопокрив — потрібен DAO-аудит
  }, prefix: :satellite

  # =========================================================================
  # ЖИТТЄВИЙ ЦИКЛ ТРИВОГИ (AASM State Machine)
  # =========================================================================
  aasm column: :status, enum: true, whiny_persistence: true do
    state :active, initial: true
    state :resolved
    state :ignored

    event :mark_resolved do
      transitions from: :active, to: :resolved
    end

    event :ignore do
      transitions from: :active, to: :ignored
    end

    event :reopen do
      transitions from: [ :resolved, :ignored ], to: :active
    end
  end

  # --- ВАЛІДАЦІЇ ---
  validates :severity, :alert_type, :message, presence: true

  # [STORM PROTECTION]: Захист від каскадних дублікатів.
  # Якщо один кластер накриває задимлення, сотні дерев згенерують fire_detected.
  # Ця валідація гарантує лише одну активну тривогу на [tree_id, alert_type].
  # Підкріплено частковим унікальним індексом на рівні БД (див. міграцію).
  validates :alert_type,
            uniqueness: { scope: [ :tree_id, :status ], message: "вже є активним для цього вузла" },
            if: -> { tree_id.present? && status_active? }

  # Троттлінг WebSocket-трансляцій: не частіше ніж раз на N секунд,
  # щоб уникнути "шторму" повідомлень при масових інцидентах.
  BROADCAST_THROTTLE_SECONDS = 5

  # --- КОЛБЕКИ (Zero-Lag Awareness) ---
  # Сакральна асинхронність: сповіщення летять лише після COMMIT
  after_create_commit :dispatch_notifications!

  # [COSMIC EYE]: Запуск супутникової верифікації через dClimate
  after_create_commit :schedule_satellite_verification!

  # Real-time: новий алерт з'являється у стрічці кластера миттєво
  after_create_commit :broadcast_new_alert

  # Миттєве оновлення мапи та стрічки новин у Цитаделі
  after_update_commit :broadcast_status_change, if: :saved_change_to_status?

  # Real-time broadcast: оновлюємо дашборди всіх операторів при будь-яких змінах алерту
  after_update_commit :broadcast_alert_update

  # --- СКОУПИ ---
  scope :unresolved, -> { status_active }
  scope :critical, -> { severity_critical.unresolved }
  scope :recent, -> { order(created_at: :desc).limit(20) }

  # [SLASH-1] One-Home cluster-level Field-Audit ескалації з dedup-ключем
  # (cluster_id, :field_audit, :active, tree_id: nil): щоденні crons (freeze
  # slash-гейта / blackout / insurance no-data) при тривалій деградації плодили
  # дубль щодоби. Одна АКТИВНА ескалація на кластер — resolve відкриває наступну.
  # Race-safety = частковий unique-index (..._unique_active_cluster_field_audit).
  # Повертає алерт або nil (dedup-skip) — виклик-сайти на nil НЕ реагують
  # (аудит-виїзд спільний, контекст лишається у їхніх логах).
  def self.escalate_field_audit!(cluster:, message:)
    existing = active_cluster_field_audit_for(cluster)
    if existing
      Rails.logger.info "🔍 [SLASH-1] Field-Audit по кластеру ##{cluster.id} вже активний (##{existing.id}) — дубль не створюємо."
      return nil
    end

    # SAVEPOINT обов'язковий: викликач може тримати ВІДКРИТУ транзакцію
    # (ParametricInsurance#arm_candidate! — trigger! + ескалація атомарно). Без
    # requires_new програна unique-гонка отруює зовнішню транзакцію на рівні PG —
    # Ruby-rescue її не лікує, імпліцитний COMMIT тихо стає ROLLBACK і trigger!
    # зникає без жодного ексепшена.
    transaction(requires_new: true) do
      create!(cluster: cluster, severity: :critical, alert_type: :field_audit, message: message)
    end
  rescue ActiveRecord::RecordNotUnique
    Rails.logger.info "🔍 [SLASH-1] Field-Audit dedup-гонку по кластеру ##{cluster.id} програно — активна ескалація вже існує."
    nil
  end

  # Виокремлено з escalate_field_audit! (тестований шов гонки: спек стабить nil
  # при реальному дублі в БД → форсує RecordNotUnique з індексу).
  def self.active_cluster_field_audit_for(cluster)
    cluster.ews_alerts.critical.alert_type_field_audit.where(tree_id: nil).first
  end

  # =========================================================================
  # МЕТОДИ (The Lens of Truth)
  # =========================================================================

  # Протокол завершення інциденту
  def resolve!(user: nil, notes: "Закрито системою")
    # [СИНХРОНІЗАЦІЯ З REDIS]: Знімаємо "режим тиші", щоб Оракул знову міг
    # слухати це дерево після його відновлення.
    clear_silence_filter!

    self.resolved_at = Time.current
    self.resolver = user
    self.resolution_notes = notes

    # AASM state transition з валідацією (only from :active)
    mark_resolved!

    # [SELF-HEALING]: Атомарно закриваємо MaintenanceRecord
    close_associated_maintenance!

    true
  end

  # [ВИПРАВЛЕНО]: Навігація в тумані.
  # Якщо дерево втратило GPS, ми фокусуємо патруль на центрі сили кластера.
  # nil-safe: cluster — optional (одиноке дерево / тестова інсталяція). Без
  # `cluster&.geo_center` друга гілка крашне NoMethodError при cluster == nil.
  def coordinates
    if tree&.latitude.present? && tree.longitude.present?
      [ tree.latitude, tree.longitude ]
    elsif (center = cluster&.geo_center)
      [ center[:lat], center[:lng] ]
    else
      # Нульова точка для запобігання помилкам Leaflet.js
      [ 0.0, 0.0 ]
    end
  end

  # Чи потребує цей інцидент негайного втручання актуаторів?
  def actionable?
    severity_critical? && (alert_type_fire_detected? || alert_type_severe_drought?)
  end

  # [COSMIC EYE / INS.1]: Чи потребує цей алерт НЕЗАЛЕЖНОГО Trigger-2-підтвердження (поза нашим AI)?
  # 3 страхові перили (пожежа/посуха/шкідник) + chainsaw ([SLASH-1] — НЕ страховий, але
  # критичний акустичний детект вимагає незалежної перевірки). Маршрут РІЗНИЙ
  # (Dclimate::VerificationService): fire → dClimate FIRMS-супутник; не-пожежа
  # (drought/insect/chainsaw) → Field Audit (fire-супутник не адьюдикує).
  def requires_satellite_consensus?
    alert_type_fire_detected? || alert_type_severe_drought? || alert_type_insect_epidemic? ||
      alert_type_chainsaw_detected?
  end

  private

  def dispatch_notifications!
    AlertNotificationWorker.perform_async(self.id)
  end

  # [COSMIC EYE / INS.1]: Планує незалежну Trigger-2-перевірку з затримкою 1 годину (орбітальний проліт)
  # для всіх 3 страхових перилів. Сервіс маршрутизує: fire → FIRMS-вердикт; не-пожежа → Field Audit.
  def schedule_satellite_verification!
    return unless requires_satellite_consensus?

    DclimateVerificationWorker.perform_in(1.hour, self.id)
  end

  # [REAL-TIME]: Новий алерт з'являється у стрічці кластера миттєво.
  # broadcast_prepend_later_to вставляє рядок на початок списку тривог.
  #
  # Codex citations: a freshly-created alert has zero citations yet — pass
  # an empty array so `Alerts::Row` skips the per-broadcast lookup. This
  # also keeps Prosopite happy when many alerts broadcast in sequence
  # (e.g. fraud-detection batch in `InsightGeneratorService`).
  def broadcast_new_alert
    return unless cluster

    Turbo::StreamsChannel.broadcast_prepend_later_to(
      [ cluster, :alerts ],
      target: "alerts_list",
      html: render_phlex(Alerts::Row.new(alert: self, citations: []))
    )
  end

  # [ОПТИМІЗАЦІЯ]: Очищення Redis-блокувальника
  def clear_silence_filter!
    return unless tree_id.present?

    silence_key = "ews_silence:#{tree_id}:#{alert_type}"
    Rails.cache.delete(silence_key)
  end

  # [ВИПРАВЛЕНО]: Turbo Transmission.
  # Видаляємо тривогу зі стрічки новин (Live Feed), як тільки вона вирішена.
  def broadcast_status_change
    alert_dom_id = ActionView::RecordIdentifier.dom_id(self)

    # Оновлення бейджа статусу на карті/деталях
    Turbo::StreamsChannel.broadcast_replace_to(
      "ews_updates_#{cluster_id}",
      target: alert_dom_id,
      html: render_phlex(Alerts::Badge.new(alert: self))
    )

    # Повне видалення вирішеного інциденту з Live Feed Архітектора
    if status_resolved?
      Turbo::StreamsChannel.broadcast_remove_to(
        "ews_live_feed",
        target: "alert_row_#{id}"
      )
    end
  end

  # [ВИПРАВЛЕНО]: MaintenanceRecord не має колонки status.
  # Використовуємо update_all для швидкодії — MaintenanceRecord не несе
  # фінансових зобов'язань та не має after_update колбеків, тому update_all безпечний.
  def close_associated_maintenance!
    MaintenanceRecord.where(ews_alert_id: id).update_all(
      performed_at: Time.current,
      notes: "Автозакрито через EWS Recovery Protocol"
    )
  end

  # [THROTTLED]: Real-time broadcast для всіх операторів організації.
  # При масових інцидентах WebSocket-канал може «лягти» від потоку оновлень.
  # Троттлінг гарантує мінімальний інтервал між некритичними broadcast.
  # nil-safe: cluster — optional. Без cluster немає org-channel і немає
  # [cluster, :alerts] stream — для одиноких дерев broadcast no-op.
  def broadcast_alert_update
    return unless cluster
    return unless should_broadcast?

    alert_html = render_phlex(Alerts::Row.new(alert: self))
    alert_dom_id = ActionView::RecordIdentifier.dom_id(self)

    Turbo::StreamsChannel.broadcast_replace_to(
      "ews_alerts_org_#{cluster.organization_id}",
      target: alert_dom_id,
      html: alert_html
    )

    # Оновлення рядка алерту на сторінці кластера
    Turbo::StreamsChannel.broadcast_replace_to(
      [ cluster, :alerts ],
      target: alert_dom_id,
      html: alert_html
    )
  end

  # Троттлінг: не частіше ніж раз на BROADCAST_THROTTLE_SECONDS.
  def should_broadcast?
    cache_key = "ews_alert_broadcast_throttle:#{id}"
    return false if Rails.cache.exist?(cache_key)

    Rails.cache.write(cache_key, true, expires_in: BROADCAST_THROTTLE_SECONDS.seconds)
    true
  end

  # Рендеринг Phlex-компонента через контролерний контекст (потрібен для route helpers)
  def render_phlex(component)
    ApplicationController.renderer.render(component, layout: false)
  end
end
