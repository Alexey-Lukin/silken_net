# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "bigdecimal"

class ParametricInsurance < ApplicationRecord
  include AASM

  # --- ЗВ'ЯЗКИ ---
  # Організація-страховик (напр. Swiss Re або децентралізований пул)
  belongs_to :organization
  belongs_to :cluster      # Лісовий масив під захистом Aegis

  # =========================================================================
  # ETHERISC DIP ORACLE MODE
  # =========================================================================
  # Коли `etherisc_policy_id` присутній, система переключається в режим Oracle:
  # замість емісії внутрішніх токенів (SCC/SFC), InsurancePayoutWorker
  # тригерить зовнішній claim через Etherisc Decentralized Insurance Protocol,
  # який виплачує USDC з децентралізованого пулу ліквідності на Polygon.
  # Це запобігає інфляції внутрішніх токенів при страхових виплатах.

  # @return [Boolean] true якщо страховка прив'язана до зовнішнього Etherisc policy
  def uses_etherisc?
    etherisc_policy_id.present?
  end

  # --- СТАТУСИ ТА ТРИГЕРИ ---
  enum :status, { active: 0, triggered: 1, paid: 2, expired: 3 }, prefix: true

  # =========================================================================
  # ЖИТТЄВИЙ ЦИКЛ СТРАХУВАННЯ (AASM State Machine)
  # =========================================================================
  aasm column: :status, enum: true, whiny_persistence: true do
    state :active, initial: true
    state :triggered
    state :paid
    state :expired

    # Тригер страхового випадку (D-MRV verification)
    event :trigger do
      transitions from: :active, to: :triggered
    end

    # Виплата здійснена
    event :pay do
      before do
        self.paid_at = Time.current
      end
      transitions from: :triggered, to: :paid
    end

    # Строк дії вичерпано
    event :expire do
      transitions from: :active, to: :expired
    end
  end

  # ⛔ 2 ЗАРЕЗЕРВОВАНЕ — не бери його під новий перил (значення лягає в колонку).
  # ⚠️ Перил існує лише тоді, коли існує його арм-сутність: `EwsAlert`-тип, який
  # читає `InsurancePayoutWorker#awaiting_independent_confirmation?`. Перил без
  # неї не «недоробка», а кандидат, що висить вічно.
  enum :trigger_event, { critical_fire: 0, extreme_drought: 1 }

  # Тип токена виплати — обирається інвестором при підписанні контракту
  enum :token_type, { carbon_coin: 0, forest_coin: 1 }, prefix: true

  # --- ВАЛІДАЦІЇ ---
  validates :payout_amount, :threshold_value, presence: true
  validates :threshold_value, numericality: { greater_than: 0, less_than_or_equal_to: 100 }
  validates :required_confirmations, numericality: { greater_than: 0 }
  # [INS.1] Застрахований перил задається ПРИ СТВОРЕННІ полісу (00_04 §5) — без нього
  # peril-honest маршрутизація (fire → FIRMS / не-пожежа → Field-Audit) і audit-трейл
  # сліпі. Прод-шляху створення полісів ще немає (E.20-майбутнє) — валідація гарантує,
  # що будь-який майбутній шлях перил проставить.
  validates :trigger_event, presence: true

  # Поліморфний зв'язок: виплата буде зафіксована в блокчейні
  has_one :blockchain_transaction, as: :sourceable

  # =========================================================================
  # АВТОНОМНИЙ ОРАКУЛ (D-MRV) — Trigger-1 двотригерного страхування
  # =========================================================================
  # [INS.1] Викликається `InsuranceOracleWorker` (per-cluster fan-out з денного
  # ланцюга, за прапором :parametric_insurance_oracle_enabled). НЕ платить сам:
  # AI `stress_index` — це НАШ сигнал (Trigger-1, loss-proximate); за dual-trigger
  # (05_05 §6 «ніколи лише за одним внутрішнім сигналом») гроші рухає лише
  # НЕЗАЛЕЖНЕ підтвердження (Trigger-2: dClimate satellite / Field-Audit людина).
  # Тому тут — лише arm-кандидат + field_audit; settlement — InsurancePayoutWorker.
  # [ARCH.100] Якір доби — `AiInsight.reporting_date` (доба, якою інсайти ЗАПИСАНІ).
  def evaluate_daily_health!(target_date = AiInsight.reporting_date)
    return unless status_active?

    # [SLASH-1] Спільне денне читання (DRY зі slash-шляхом A) + blackout-рішення.
    router = DailyHealthRouter.new(cluster, target_date)
    return if router.skipped? # немає активних дерев

    # [INS.1 no-data guard / «не карати жертву»] Катастрофа знищила сенсори → дерево
    # замовкло (blackout). НЕ рахуємо тихо damage_ratio = 0 (це кривдило б жертву
    # мовчанням) → ескалюємо у Field Audit (дзеркало flag_data_blackout!, 05_05 §6).
    # «Тиша замовклого дерева — теж його голос».
    return escalate_no_data_field_audit!(target_date) if router.blackout?

    # Аномальні дерева у вікні критичного стану. Insurance-поріг 0.8 свідомо ШИРШИЙ за
    # slash-поріг 0.83 — РІЗНІ концепти (кандидат на виплату vs slash-тригер), не
    # дублікат значення (00_07 SLASH-1 — задокументований spread).
    anomalous_insights = router.insights.where(stress_index: 0.8..1.0)

    # =========================================================================
    # ORACLE CONSENSUS (Захист від помилки одиночного Оракула)
    # =========================================================================
    # Кандидат озброюється лише якщо required_confirmations незалежних AI-джерел
    # (різних моделей) підтвердили аномалію для кожного дерева — внутрішній multi-signal
    # проти помилки одного Оракула. Це Trigger-1; payout усе одно чекає Trigger-2.
    min_sources = required_confirmations

    confirmed_anomalous_count = if min_sources <= 1
      anomalous_insights.select(:analyzable_id).distinct.count
    else
      # GROUP BY analyzable_id, HAVING COUNT(DISTINCT model_source) >= required_confirmations
      anomalous_insights
        .where.not(model_source: nil)
        .group(:analyzable_id)
        .having("COUNT(DISTINCT model_source) >= ?", min_sources)
        .count
        .size
    end

    # [BigDecimal]: точна арифметика — для страхування мікропохибка Float неприпустима.
    damage_ratio = (BigDecimal(confirmed_anomalous_count.to_s) / router.total_active_trees * 100).round(2)

    arm_candidate!(damage_ratio) if damage_ratio >= threshold_value
  end

  # [НОВЕ]: Визначаємо гаманець отримувача (Власника лісу)
  def recipient_wallet_address
    cluster.organization.crypto_public_address
  end

  private

  # [INS.1 dual-trigger] AI-оракул перетнув поріг → озброюємо КАНДИДАТА (Trigger-1
  # спрацював), але НЕ платимо: гроші чекають НЕЗАЛЕЖНОГО підтвердження (Trigger-2 —
  # dClimate satellite для пожежі / Field-Audit людина для решти). Settlement —
  # InsurancePayoutWorker, коли незалежний тригер підтвердить. Закриває basis-risk /
  # moral-hazard: не рухаємо гроші лише за власним сигналом (05_05 §6).
  def arm_candidate!(percentage)
    # [INS.1] `trigger!` + field_audit-ескалація АТОМАРНО в одній транзакції: якщо алерт не
    # створиться, `:triggered` відкочується → наступний прогін переозброїть (без orphaned-
    # кандидата без audit-сигналу). Тут немає Redis-enqueue (на відміну від старого
    # `activate_payout!`), тож PG↔Redis race відсутній — обидва DB-writes у транзакції.
    transaction do
      trigger! # AASM :active → :triggered (кандидат, ще НЕ payout)
      # Dedup-хелпер: якщо кластер уже під активним Field-Audit (blackout/freeze) —
      # аудит-виїзд спільний, дубль не створюємо; insurance-контекст лишається в лозі.
      EwsAlert.escalate_field_audit!(
        cluster: cluster,
        message_key: "insurance_candidate_armed",
        message_params: { id: id, percentage: percentage }
      )
      Rails.logger.warn "🎯 [INSURANCE] Кандидат ##{id} озброєно (#{percentage}% за AI-оракулом) — чекаємо НЕЗАЛЕЖНОГО підтвердження (Trigger-2); payout НЕ запускаємо."
    end
  end

  # [INS.1 no-data guard] Активні дерева Є, інсайтів немає (катастрофа знищила сенсори).
  # Ескалюємо у Field Audit замість тихого damage_ratio = 0 — щоб не кривдити жертву
  # мовчанням, і щоб «знищ сенсори → заяви катастрофу» не давав авто-виплати (ескалація
  # НЕ платить; 05_05 §5: going-dark-після-P0 = tamper, а не безумовна виплата).
  def escalate_no_data_field_audit!(target_date)
    Rails.logger.warn "🌐 [INSURANCE] Кластер ##{cluster.id} / страховка ##{id}: data blackout (#{target_date}) — дерево замовкло. Ескалюємо у Field Audit; НЕ платимо й НЕ обнуляємо."

    EwsAlert.escalate_field_audit!(
      cluster: cluster,
      message_key: "insurance_no_data",
      message_params: { id: id, target_date: target_date }
    )
  end
end
