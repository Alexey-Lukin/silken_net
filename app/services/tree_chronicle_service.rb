# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# = ===================================================================
# 📜 TREE CHRONICLE SERVICE (Digital Life Story)
# = ===================================================================
# Агрегує дані з AiInsight, EwsAlert, MaintenanceRecord та BlockchainTransaction
# для побудови хронологічної "історії" дерева. Генерує на льоту — жодної нової
# таблиці не потрібно.
#
# [МАСШТАБ]: При трильйонах дерев кожен запит обмежений per_page + ORDER BY DESC.
# Уникаємо повного сканування: кожна модель має індекси на created_at + tree_id.
#
# [i18n]: Всі текстові рядки формуються через TreeChronicle::TextFormatter.
# Мітки alert_type уже локалізовані (`alerts.types.*`); решта шаблонів —
# англомовні рядки, їхня локалізація трекається в 00_07 I18N.1.
#
# Використання:
#   result = TreeChronicleService.call(tree: tree, page: 1, per_page: 20)
#   result[:entries]  # => Array<TreeChronicleService::Entry>
#   result[:pagy]     # => Pagy instance
class TreeChronicleService < ApplicationService
  # Struct для одного запису хроніки
  Entry = Data.define(:date, :event_type, :icon, :title, :description, :severity, :source_type, :source_id)

  DEFAULT_PER_PAGE = 20

  def initialize(tree:, page: 1, per_page: DEFAULT_PER_PAGE)
    @tree = tree
    @page = [ page.to_i, 1 ].max
    @per_page = [ [ per_page.to_i, 1 ].max, 100 ].min
  end

  def perform
    entries = collect_all_entries
    entries.sort_by! { |e| e.date }.reverse!

    # Manual Pagy для масиву (без DB-запитів на весь масив)
    total = entries.size
    offset = (@page - 1) * @per_page
    page_entries = entries[offset, @per_page] || []

    pagy = Pagy::Offset.new(count: total, page: @page, limit: @per_page)

    { entries: page_entries, pagy: pagy }
  end

  private

  def collect_all_entries
    entries = []
    entries.concat(insight_entries)
    entries.concat(alert_entries)
    entries.concat(maintenance_entries)
    entries.concat(blockchain_entries)
    entries
  end

  # --- AiInsight entries ---
  def insight_entries
    @tree.ai_insights
         .daily_health_summary
         .order(target_date: :desc)
         .limit(50)
         .map { |insight| format_insight(insight) }
  end

  def format_insight(insight)
    if insight.fraud_detected?
      Entry.new(
        date: insight.target_date.to_time,
        event_type: :fraud,
        icon: "⚠",
        title: TreeChronicle::TextFormatter.fraud_title,
        description: TreeChronicle::TextFormatter.fraud_description(insight),
        severity: :critical,
        source_type: "AiInsight",
        source_id: insight.id
      )
    elsif insight.stress_index.present? && insight.stress_index >= BigDecimal("0.3")
      Entry.new(
        date: insight.target_date.to_time,
        event_type: :stress,
        icon: "△",
        title: TreeChronicle::TextFormatter.stress_title,
        description: TreeChronicle::TextFormatter.stress_description(insight),
        severity: insight.stress_index >= BigDecimal("0.8") ? :critical : :warning,
        source_type: "AiInsight",
        source_id: insight.id
      )
    else
      Entry.new(
        date: insight.target_date.to_time,
        event_type: :homeostasis,
        icon: "◉",
        title: TreeChronicle::TextFormatter.homeostasis_title,
        description: TreeChronicle::TextFormatter.homeostasis_description(insight),
        severity: :stable,
        source_type: "AiInsight",
        source_id: insight.id
      )
    end
  end

  # --- EwsAlert entries ---
  def alert_entries
    @tree.ews_alerts
         .order(created_at: :desc)
         .limit(30)
         .flat_map { |alert| format_alert(alert) }
  end

  def format_alert(alert)
    entries = []

    entries << Entry.new(
      date: alert.created_at,
      event_type: :alert,
      icon: TreeChronicle::TextFormatter.alert_icon(alert.alert_type),
      title: TreeChronicle::TextFormatter.alert_title(alert),
      description: TreeChronicle::TextFormatter.alert_description(alert),
      severity: chronicle_severity(alert),
      source_type: "EwsAlert",
      source_id: alert.id
    )

    if alert.status_resolved? && alert.resolved_at.present?
      entries << Entry.new(
        date: alert.resolved_at,
        event_type: :recovery,
        icon: "✓",
        title: TreeChronicle::TextFormatter.recovery_title,
        description: TreeChronicle::TextFormatter.recovery_description(alert),
        severity: :stable,
        source_type: "EwsAlert",
        source_id: alert.id
      )
    end

    entries
  end

  # --- MaintenanceRecord entries ---
  def maintenance_entries
    @tree.maintenance_records
         .includes(:user)
         .order(performed_at: :desc)
         .limit(20)
         .map { |record| format_maintenance(record) }
  end

  def format_maintenance(record)
    Entry.new(
      date: record.performed_at,
      event_type: :maintenance,
      icon: "⚙",
      title: TreeChronicle::TextFormatter.maintenance_title(record),
      description: TreeChronicle::TextFormatter.maintenance_description(record),
      severity: :info,
      source_type: "MaintenanceRecord",
      source_id: record.id
    )
  end

  # --- BlockchainTransaction entries (через wallet) ---
  def blockchain_entries
    wallet = @tree.wallet
    return [] unless wallet

    wallet.blockchain_transactions
          .where(status: :confirmed)
          .order(confirmed_at: :desc)
          .limit(20)
          .map { |tx| format_blockchain(tx) }
  end

  # 🔴 [ARCH.101] Напрямок ДЕРИВУЄТЬСЯ — тут стояв захардкоджений `:minting` на
  # КОЖЕН рядок гаманця, тож слеш-інтент (`create_slash_intent!` пише його на той
  # самий гаманець дерева й доводить до `:confirmed`) з'являвся в хроніці як
  # «Minted» із зеленим success-бейджем. Тобто сторінка дерева свідчила про
  # вилучення коштів як про емісію — рівно навпаки. Три осі мусять рухатись РАЗОМ:
  # тип (ключ підпису) · severity (тон) · іконка, інакше лишиться половина правди.
  def format_blockchain(tx)
    burn = tx.burn?

    Entry.new(
      date: tx.confirmed_at || tx.created_at,
      event_type: burn ? :burning : :minting,
      icon: burn ? "⬢" : "◆",
      title: TreeChronicle::TextFormatter.blockchain_title(tx),
      description: TreeChronicle::TextFormatter.blockchain_description(tx),
      severity: burn ? :warning : :stable,
      source_type: "BlockchainTransaction",
      source_id: tx.id
    )
  end

  # Хроніка веде ВЛАСНИЙ словник тяжкості (`:stable`/`:info`/`:warning`/
  # `:critical`) — його розуміє `Trees::Chronicle`. `EwsAlert#severity` веде
  # інший (`:low`/`:medium`/`:critical`), і сирий `to_sym` вливав чужі
  # значення просто так: `:medium` і `:low` не збігались із жодною гілкою
  # й діставали ту саму дефолтну зелень, що й `:stable`, — тобто тривога
  # середньої тяжкості малювалась як «усе гаразд». Перекладаємо на межі,
  # де обидва словники ще видно, а не в CSS-хелпері, який їх не знає.
  ALERT_SEVERITY_TO_CHRONICLE = { "low" => :info, "medium" => :warning, "critical" => :critical }.freeze

  def chronicle_severity(alert)
    ALERT_SEVERITY_TO_CHRONICLE.fetch(alert.severity.to_s, :warning)
  end
end
