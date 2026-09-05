# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# [SILENCE-1] Dead-man switch Солдата: Rails сам детектить аномальну тишу вузла,
# не чекаючи, доки замовкне ВЕСЬ кластер (DailyHealthRouter#blackout? бачить лише
# cluster-wide зникнення → вкрадене/мертве дерево мінтило б, доки сусіди цокочуть).
# Per-Soldier дзеркало GatewayStalenessSweepWorker [ARCH.54 Шар 0] — з двома
# свідомими відмінностями (канон 06_08 §1.3):
#
#   1. Поріг НЕ виводиться з конфіга: Soldier спить між energy-sufficient циклами,
#      delta_t навмисно варіативний (стрес → повільніший заряд → довша тиша = САМ
#      сигнал) → SystemParameter :tree_silence_threshold_hours, 24h [transitional]
#      до bench-калібрування (00_07 SILENCE-1 / E.63).
#   2. Носій = per-tree :field_audit, НЕ новий alert-тип: новий critical-тип
#      потрапив би у critical_unmaintained? (BlockchainBurningService, blacklist-
#      предикат) за замовчуванням → тиша накручувала б penalty оператору, проти
#      канону «тиша НІКОЛИ не slash» (05_05). Статус дерева НЕ чіпаємо: dormant =
#      людське рішення, removed/deceased ЗАПУСКАЮТЬ slashing — «слухай, не карай».
#
# Симетрія: вузол знову в ефірі → машинний resolve! (user: nil → resolved_by NULL,
# дискримінатор gap-E) — транзієнтна тиша (дощ → повільний заряд) не жене лісника.
class TreeStalenessSweepWorker
  include Sidekiq::Job
  # alerts(2): народжує life-safety сигнали EWS (той самий ярус, що Queen-sweeper);
  # сам прохід — кілька легких запитів.
  sidekiq_options queue: "alerts", retry: 2

  # [ARCH.99] Число НЕ повторюємо: дім транзиційного порога — `Tree::SILENCE_THRESHOLD`,
  # той самий, що годує `scope :silent` і `Tree#fresh_signal?` у в'ю. Доти воркер ніс
  # власну «24», і кожен, хто рухав би поріг, мусив би вгадати, скільки домів у числа.
  DEFAULT_THRESHOLD_HOURS = Tree::SILENCE_THRESHOLD.in_hours.to_i

  # [SILENCE-1] Джерельний ключ ескалацій ЦЬОГО воркера — писач (escalate_silent_trees)
  # і резолвер (resolve_returned_trees) мусять ділити один дім, інакше звуження резолва
  # тихо розійдеться з тим, що воркер пише.
  SILENCE_MESSAGE_KEY = "tree_silent"

  def perform
    threshold = silence_threshold
    flagged   = escalate_silent_trees(threshold)
    resolved  = resolve_returned_trees(threshold)

    SilkenNet::Metrics::TREES_SILENT.set(Tree.silent(threshold).count)
    # [S2.4] Штамп ПІСЛЯ обох операцій: він свідчить не «воркер стартував», а
    # «прохід дійшов до кінця» — інакше падіння на середині лишало б свіжий
    # штамп над застиглим числом, тобто брехало б переконливіше за відсутність.
    SilkenNet::Metrics::TREE_SWEEP_TIMESTAMP.set(Time.current.to_i)

    Rails.logger.info(
      "🌳 [SILENCE-1] Tree staleness sweep: flagged=#{flagged} resolved=#{resolved} " \
      "(поріг #{threshold.in_hours.round} год)"
    )
  end

  private

  # Fail-safe до дефолту: misconfig значення (boolean/json/non-numeric string →
  # nil або ≤0) тихо давав би threshold→0 і flag'нув би ВЕСЬ флот — гірше за креш.
  def silence_threshold
    raw = SystemParameter.current(:tree_silence_threshold_hours, default: DEFAULT_THRESHOLD_HOURS)
    hours = Float(raw, exception: false)
    hours = DEFAULT_THRESHOLD_HOURS unless hours&.positive?
    hours.hours
  end

  # Мовчазні дерева без активної per-tree ескалації → field_audit. Анти-джойн
  # тримає прохід дешевим (дедуп-guard у escalate_field_audit! лишається — метод
  # safe standalone); `.where.not(tree_id: nil)` у сабквері ОБОВ'ЯЗКОВИЙ — інакше
  # cluster-level рядок (tree_id NULL) отруює NOT IN і скоуп порожніє.
  #
  # Dark-cluster suppression (анти-шторм, корельована тиша): gateway на кластер
  # один, дерев — тисячі. Queen падає → через поріг УВЕСЬ кластер «мовчазний» →
  # без глушника прохід породив би N critical-алертів + N notification-джобів +
  # N Phlex-рендерів разом. Per-tree тиша інформативна лише коли кластер ЧУЄ
  # (сусіди цокочуть, це дерево — ні); known-dark кластер уже ескальований
  # cluster-рівнем (queen_offline/uplink_lost — Queen-sweeper детектить за
  # хвилини, задовго до tree-порога; blackout → cluster-level field_audit).
  # Стеля: некорельований масовий перетин порога (глушилка при живій Королеві
  # ДО daily-blackout-крона) глушником не покритий — розкид delta_t розмазує
  # його в часі, cap не вводимо (YAGNI до реального інциденту).
  def escalate_silent_trees(threshold)
    count = 0
    dark_ids = dark_cluster_ids
    scope = silent_without_audit(threshold)
    scope = scope.where("cluster_id IS NULL OR cluster_id NOT IN (?)", dark_ids) if dark_ids.any?
    scope.includes(:cluster).find_each do |tree|
      silent_for_h = ((Time.current - tree.last_seen_at) / 1.hour).round
      alert = EwsAlert.escalate_field_audit!(
        cluster: tree.cluster, tree: tree,
        message_key: SILENCE_MESSAGE_KEY,
        message_params: { did: tree.did, silent_for_h: silent_for_h,
                          last_seen_at: tree.last_seen_at.utc.iso8601, threshold_h: threshold.in_hours.round }
      )
      if alert
        SilkenNet::Metrics::TREE_SILENCE_TOTAL.increment
        count += 1
      end
    end
    count
  end

  def silent_without_audit(threshold)
    Tree.silent(threshold).where.not(
      id: EwsAlert.unresolved.alert_type_field_audit.where.not(tree_id: nil).select(:tree_id)
    )
  end

  # Кластери, що ВЖЕ ескальовані cluster-рівнем як темні: Queen мовчить/без
  # uplink (comms-пара) або cluster-level Field-Audit, що СТВЕРДЖУЄ нечутність.
  #
  # 🔴 [ARCH.110] Фільтр за `SILENCE_ASSERTING_KEYS` несучий, а не оптимізація.
  # Доти сюди входив БУДЬ-ЯКИЙ cluster-level `field_audit`, тож slash-freeze,
  # порожній баланс чи озброєний страховий кандидат викидали ВСІ дерева кластера
  # з dead-man switch'а — тиша глушилась грішми, і машинного резолвера для
  # cluster-level `field_audit` не існує (`resolve_returned_trees` бʼє
  # `joins(:tree)`), тож глушник жив, доки алерт не закриє людина.
  # Канон [`06_08 §1.3`] описував намір саме так («cluster-level field_audit
  # (blackout)») — код лише тепер його виконує.
  def dark_cluster_ids
    EwsAlert.unresolved.where.not(cluster_id: nil)
            .where(alert_type: %i[queen_offline queen_uplink_lost])
            .or(EwsAlert.unresolved.where.not(cluster_id: nil)
                        .where(alert_type: :field_audit, tree_id: nil,
                               message_key: EwsAlert::SILENCE_ASSERTING_KEYS))
            .distinct.pluck(:cluster_id)
  end

  # Дві resolve-гілки: (1) вузол знову в ефірі — спростовуючий факт = сам ефір;
  # (2) вузол покинув active (dormant = людина приспала, removed/deceased =
  # кейс уже веде slashing) — критичний алерт інакше висів би вічно
  # (last_seen_at такого дерева більше не оновиться).
  #
  # [SILENCE-1 2026-08-30] Резолв звужено до ВЛАСНИХ ескалацій (SILENCE_MESSAGE_KEY):
  # «дерево заговорило» спростовує рівно тишу — воно НЕ спростовує чужу per-tree
  # ескалацію з іншою причиною. Сьогодні множини тотожні (єдиний per-tree продюсер
  # escalate_field_audit! — цей воркер), тож поведінка не міняється; без звуження
  # перший же майбутній per-tree продюсер діставав би тихе авто-закриття своїх
  # алертів першим ефіром дерева, і жоден гейт цього не бачив би.
  def resolve_returned_trees(threshold)
    count = 0
    base = EwsAlert.unresolved.alert_type_field_audit
                   .where(message_key: SILENCE_MESSAGE_KEY).joins(:tree)
    base.where(trees: { last_seen_at: threshold.ago.. })
        .or(base.where.not(trees: { status: :active }))
        .includes(:tree).find_each do |alert|
      tree = alert.tree
      # [I18N.1] Два КЛЮЧІ, не булевий параметр (в іншій мові гілки — різні
      # речення). `status` у params — сирий enum свідомо: це ops-нотатка, і токен
      # тут — ідентифікатор стану, той самий оголошений клас, що токен-параметри
      # алертів (⚖️ у `00_07` I18N.1).
      if tree.active?
        alert.resolve!(key: "tree_returned",
                       params: { did: tree.did, seen_at: tree.last_seen_at.utc.iso8601 })
      else
        alert.resolve!(key: "tree_left_active",
                       params: { did: tree.did, status: tree.status })
      end
      count += 1
    end
    count
  end
end
