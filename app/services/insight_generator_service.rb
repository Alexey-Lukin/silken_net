# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

class InsightGeneratorService < ApplicationService
  MODEL_PATH = Rails.root.join("lib/assets/silken_forest.marshal").freeze
  MODEL_DIGEST_PATH = Rails.root.join("lib/assets/silken_forest.marshal.sha256").freeze

  def initialize(date = AiInsight.reporting_date)
    @date = date
    @start_time = date.beginning_of_day
    @end_time = date.end_of_day
    @processed_count = 0
    @ai_model = load_ai_model
  end

  # Синхронний режим: обробляє ВСІ кластери в одному процесі.
  # Підходить для малих датасетів або прямого виклику через InsightGeneratorService.call(date).
  # Для масштабу 10M+ дерев використовуйте InsightGeneratorOrchestratorWorker (Sidekiq::Batch).
  # 🔴 [ARCH.84] Вердикт за добу мусить дістати КОЖНЕ дерево, а обидва шляхи
  # писача обходять лише кластери з даними (`cluster_baselines.keys`) — тож
  # повністю мовчазний кластер не відвідується взагалі, і його дерева тримали б
  # учорашній стрес: «постаріла підміна виміру», яку `Cluster#recalculate_health_index!`
  # (`04_01 §3`) називає небезпечнішою за очевидну, бо вона правдоподібна.
  #
  # Один set-based UPDATE, а не обхід флоту: межа `IS NOT NULL` лишає в наборі
  # тільки рядки, які справді треба занулити (10¹²-масштаб — `00_01 §1.1`).
  # ⚠️ `cluster_id IS NULL` враховано ЯВНО: `belongs_to :cluster, optional: true`,
  # а `NOT IN` такі рядки мовчки виключає — та сама сліпота, що [ARCH.98].
  # 🔴 [ARCH.84] `update_all` колбеків не пускає, тож маркери цих дерев лишались
  # би з учорашнім кольором на відкритому дашборді — і глядач не відрізнив би
  # «ще не виміряли» від «броадкаст зламався», тобто фікс чесного кольору не
  # доїжджав би саме там, де мав.
  #
  # ⚠️ Множину для броадкасту звужено ДВІЧІ, і обидва звуження принципові:
  # (а) `where.not(latest_stress_index: nil)` уже стоїть — оновлюємо лише те,
  #     що справді змінюється; (б) `geolocated` — дерево без координат маркера
  #     не має взагалі (`broadcast_map_update` сам це гейтує), тож вантажити його
  #     означало б платити за вузол, якого на мапі немає.
  # ⛔ І НЕ `tree.reload` перед броадкастом: `update_all` щойно поставив рівно
  # одну колонку у відоме значення, тож перечитувати рядок означало б додати по
  # SELECT-у на дерево — N+1 рівно на тому шляху, заради ефективності якого
  # set-based `UPDATE` тут і стоїть. Синхронізуємо в памʼяті.
  # Ціна: один SELECT id-шок на добовий прогін.
  def self.reset_stress_outside(cluster_ids)
    base = Tree.where.not(latest_stress_index: nil)
    scope = if cluster_ids.blank?
              base
    else
              base.where.not(cluster_id: cluster_ids).or(base.where(cluster_id: nil))
    end

    remapped = scope.geolocated.to_a
    affected = scope.update_all(latest_stress_index: nil)
    remapped.each do |tree|
      tree.latest_stress_index = nil
      tree.broadcast_map_update
    end
    affected
  end

  def perform
    Rails.logger.info "🧠 [Insight Generator] Початок масової агрегації за #{@date}..."

    # ⚡ [ОПТИМІЗАЦІЯ N+1]: Завантажуємо Базлайни ВСІХ кластерів одним запитом перед циклом.
    # Це прибирає сотні важких JOIN запитів усередині Cluster.find_each.
    @baselines_map = prefetch_cluster_baselines

    # 2. ПОКЛАСТЕРНА ОБРОБКА З AI-GUARD
    # [ОПТИМІЗАЦІЯ]: Обробляємо тільки кластери з даними замість Cluster.find_each
    processed_cluster_ids = @baselines_map.keys

    # [P1 FIX DATA-LOSS]: Транзакційний swap — якщо процес впаде під час регенерації,
    # транзакція відкочується і старі інсайти залишаються неушкодженими.
    ActiveRecord::Base.transaction do
      # 1. ІДЕМПОТЕНТНІСТЬ: Очищуємо старі інсайти за цю дату перед перерахунком
      AiInsight.where(target_date: @date, insight_type: :daily_health_summary).delete_all

      # [ARCH.84] Дерева поза обробленими кластерами — теж вердикт за цю добу.
      self.class.reset_stress_outside(processed_cluster_ids)

      unless processed_cluster_ids.empty?
        Cluster.where(id: processed_cluster_ids).find_each do |cluster|
          process_cluster_trees(cluster, @baselines_map[cluster.id])
        end

        # 3. АГРЕГАЦІЯ КЛАСТЕРІВ — тільки для кластерів з даними (без повторної ітерації)
        aggregate_clusters!(processed_cluster_ids)
      end
    end

    Rails.logger.info "✅ [Insight Generator] Цикл завершено. Оброблено вузлів: #{@processed_count}"
    { processed_count: @processed_count, date: @date }
  end

  # =========================================================================
  # PUBLIC API ДЛЯ БАТЧЕВОГО РЕЖИМУ (Sidekiq::Batch)
  # =========================================================================
  # Використовується GenerateClusterInsightWorker для обробки чанку кластерів.
  # Кожен воркер отримує масив cluster_ids та обробляє їх незалежно.

  # Повертає Hash { cluster_id => { temp:, z: } } для кластерів, що мають дані.
  # Якщо cluster_ids передано — фільтрує тільки вказані кластери.
  def cluster_baselines(cluster_ids = nil)
    prefetch_cluster_baselines(cluster_ids)
  end

  # Обробляє чанк кластерів: створює tree-level та cluster-level AiInsight.
  # Ідемпотентний: видаляє старі інсайти для вказаних кластерів перед перерахунком.
  # @param cluster_ids [Array<Integer>] масив ID кластерів для обробки
  # @return [Integer] кількість оброблених вузлів
  def process_cluster_batch(cluster_ids)
    baselines = prefetch_cluster_baselines(cluster_ids)

    Cluster.where(id: cluster_ids).find_each do |cluster|
      cluster_baseline = baselines[cluster.id]
      next unless cluster_baseline

      # Ідемпотентність: очищуємо старі інсайти для дерев ТА кластера
      tree_ids = cluster.trees.select(:id)
      AiInsight.where(analyzable_type: "Tree", analyzable_id: tree_ids,
                      insight_type: :daily_health_summary, target_date: @date).delete_all
      AiInsight.where(analyzable_type: "Cluster", analyzable_id: cluster.id,
                      insight_type: :daily_health_summary, target_date: @date).delete_all

      process_cluster_trees(cluster, cluster_baseline)
      aggregate_cluster!(cluster)
    end

    @processed_count
  end

  # ⛔ [ARCH.59, ⚖️ 2026-08-21] DELETE-шляху над `telemetry_logs` тут БІЛЬШЕ НЕМАЄ, і це
  # присуд, а не прибирання мертвого коду. Стояв `cleanup_old_logs!` — `delete_all`
  # батчами по рядках, старших 7 днів, з єдиним гардом на `oracle_status`.
  #
  # Ретеншн сирої телеметрії робить ВИКЛЮЧНО дроп місячних партицій, і причина не
  # смакова: тракт архіву вже ОЧІКУЄ саме цієї події й має для неї чесний стан
  # (`TelemetryArchiveBatch.retention_expired` = «листя менше, бо партиції дропнуто —
  # НЕ tamper»). Другий механізм зникнення рядків зробив би той статус неоднозначним,
  # тобто зіпсував би єдиний прилад, яким ми відрізняємо ретеншн від підміни.
  #
  # ⚠️ Дві ціни семиденного вікна, виміряні окремо й обидві поза цим файлом:
  # `Mrv::LineageReportService` гілки «джерельні рядки застаріли» не має взагалі й
  # видав би зовнішньому аудитору `unprovable_regrouped` («дерево змінило кластер»);
  # а пін архівного батча їде чергою `low`, тож видалення встигало б випередити його —
  # і `archiveRoot`, уже записаний on-chain, лишався б без офчейн-свідка.
  # Механізм дропу — `00_07` ARCH.70; носій цієї заборони — `spec/quality/telemetry_retention_home_spec.rb`.

  private

  # ⚡ [ANTI-N+1]: Агрегація базлайнів одним GROUP BY.
  # Якщо cluster_ids передано — фільтрує тільки вказані кластери.
  def prefetch_cluster_baselines(cluster_ids = nil)
    scope = TelemetryLog.joins(:tree)
                        .where(created_at: @start_time..@end_time)
    scope = scope.where(trees: { cluster_id: cluster_ids }) if cluster_ids

    scope.group("trees.cluster_id")
         .select(
           "trees.cluster_id",
           "AVG(temperature_c) as avg_temp",
           "AVG(z_value) as avg_z"
         ).each_with_object({}) do |row, hash|
           hash[row.cluster_id] = {
             temp: row.avg_temp.to_f,
             z: row.avg_z.to_f
           }
         end
  end

  # ⚡ [ANTI-N+1]: Агрегація статистики для всіх дерев кластера одним GROUP BY
  def prefetch_tree_stats(cluster)
    TelemetryLog.where(tree_id: cluster.trees.select(:id))
                .where(created_at: @start_time..@end_time)
                .group(:tree_id)
                .select(
                  "tree_id",
                  "AVG(temperature_c) as avg_temp",
                  "AVG(voltage_mv) as avg_vcap",
                  "AVG(z_value) as avg_z",
                  "AVG(vpd) as avg_vpd",
                  "MAX(acoustic_events) as max_acoustic",
                  "SUM(growth_points) as total_growth",
                  "MAX(bio_status) as max_status"
                ).each_with_object({}) do |row, hash|
                  hash[row.tree_id] = row
                end
  end

  # ⚡ [ANTI-N+1]: Агрегуємо статистику для ВСІХ дерев кластера одним SQL-запитом,
  # потім ітеруємо дерева й генеруємо tree-level інсайти. Спільний хот-патч для
  # синхронного #perform та батчевого #process_cluster_batch (DRY).
  def process_cluster_trees(cluster, cluster_baseline)
    tree_stats_map = prefetch_tree_stats(cluster)

    cluster.trees.find_each do |tree|
      stats = tree_stats_map[tree.id]

      # 🔴 [ARCH.84] Дерево без телеметрії за добу дістає ЯВНИЙ `nil`, а не пропуск.
      # Доти тут стояв `next unless stats` — і денормалізований стрес лишався
      # стояти з попереднього прогону НАЗАВЖДИ: понеділковий 0.42 на вівторковій
      # темряві. Це підміна виміру, лише постаріла, і тим небезпечніша, що
      # правдоподібна — дослівно те, чого уникає дзеркальний
      # `Cluster#recalculate_health_index!` (`04_01 §3`), і чого ця колонка не
      # уникала. Ціна нульова за скануванням: цикл уже обходить КОЖНЕ дерево
      # кластера, `prefetch_tree_stats` — один згрупований запит; додається
      # лише запис, і лише для мовчазної меншості (поріг тиші — 24 год).
      unless stats
        # [ARCH.84] `update_column` колбеків не пускає, тож броадкаст явний —
        # інакше маркер лишався б учорашнім кольором до перезавантаження.
        # Гард `unless nil?` уже означає «значення змінилось», тож зайвих не буде.
        unless tree.latest_stress_index.nil?
          tree.update_column(:latest_stress_index, nil)
          tree.broadcast_map_update
        end
        next
      end

      @processed_count += 1 if generate_for_tree(tree, cluster_baseline, stats)
    end
  end

  def generate_for_tree(tree, baseline, stats)
    return false unless stats&.avg_temp

    # 🛡️ [AI FRAUD GUARD]: Перевірка на "занадто ідеальні" показники
    is_fraud = detect_fraud?(stats, baseline)

    # Якщо виявлено фрод - ми блокуємо ріст і максимізуємо стрес
    final_growth = is_fraud ? 0 : stats.total_growth.to_i

    # Розраховуємо індекс стресу (враховуючи відхилення Z Атрактора та Фрод)
    # $$Stress = \min(1.0, \text{base\_stress} + \text{anomaly\_penalties})$$
    stress_index = is_fraud ? 1.0 : calculate_stress_index(stats.max_status.to_i, stats.avg_temp.to_f, stats.max_acoustic.to_i, stats.avg_z.to_f, stats.avg_vcap.to_i)

    # [VPD weather-confounder, 05_05 §7] Discount-only weather gate so a humid
    # spell cannot push a cluster over the slash threshold. Inert until firmware
    # sends VPD + ground-truth calibration (see #apply_weather_confounder).
    # ⚠️ Друга умова гейта — метаболічне відхилення — виміру не має, тож дисконт
    # не спрацює й після VPD-калібрування; тригер той самий, що у фрод-гарда.
    unless is_fraud
      stress_index = apply_weather_confounder(stress_index, stats.avg_vpd&.to_f)
    end

    summary = is_fraud ? "🚨 КРИТИЧНО: Виявлено фрод-телеметрію (аномальне відхилення від кластера)." : generate_summary(stats.max_status.to_i, stats.avg_temp.to_f)

    AiInsight.create!(
      analyzable: tree,
      insight_type: :daily_health_summary,
      target_date: @date,
      average_temperature: stats.avg_temp.to_f.round(2),
      stress_index: stress_index,
      total_growth_points: final_growth,
      summary: summary,
      fraud_detected: is_fraud,
      reasoning: {
        avg_z: stats.avg_z.to_f.round(4),
        max_acoustic: stats.max_acoustic.to_i,
        avg_vcap: stats.avg_vcap.to_i,
        avg_vpd: stats.avg_vpd&.to_f&.round(3) # nil доки firmware не шле VPD (HW.32)
      }
    )

    # [ВИПРАВЛЕНО: N+1 TreeBlueprint#current_stress]:
    # Денормалізуємо stress_index прямо в таблицю trees (аналогічно latest_voltage_mv).
    # Це усуває N+1 запит для кожного дерева при серіалізації (TreeBlueprint, MapNode).
    # Використовуємо update_column для швидкодії без callbacks (hot path для мільйонів дерев).
    # 🔴 [ARCH.84] І саме тому броадкаст мапи тут ЯВНИЙ: `update_column` не пускає
    # `after_update_commit`, тож чесний колір стресу не доїжджав до відкритого
    # дашборда ЖОДНОГО разу. Фаєримо лише на РЕАЛЬНІЙ зміні — прогін щоденний, а
    # дерево, чий стрес не зрушив, перемальовувати нема за чим.
    stress_changed = tree.latest_stress_index != stress_index
    tree.update_column(:latest_stress_index, stress_index)
    tree.broadcast_map_update if stress_changed

    # ⚡ [ВИПРАВЛЕНО: Жорсткий Slashing]:
    # Ми більше не "вбиваємо" дерево миттєво. Створюємо критичну тривогу для перевірки.
    # Це захищає інвестора від помилок ШІ, але зупиняє виплати до вердикту людини.
    if is_fraud
      AlertDispatchService.create_fraud_alert!(tree, @date)
    end

    true
  rescue StandardError => e
    Rails.logger.error "🛑 [Insight] Помилка для Дерева #{tree.did}: #{e.message}"
    false
  end

  # 🔴 ІНЕРТНИЙ, і це ОГОЛОШЕНО, а не випадково. Дизайн вимагає ДВОХ незалежних
  # осей відхилення від кластерного базлайну, і вимога несуча: одна вісь означає
  # «це дерево тепліше за сусідів», а так буває з краю насадження на сонці — гард
  # на одній осі виробляв би хибні звинувачення, тобто був би ГІРШИЙ за мовчання.
  # Другої осі сьогодні немає: `sap_flow` не мав жодного писача (нема в жодному
  # wire-форматі) і знятий. Доти безпеку тримала АРИФМЕТИКА — `AVG` по самих NULL
  # давав 0.0, і гард мовчки коротко замикався; тепер причина названа.
  #
  # ⚠️ Наслідки не косметичні — `is_fraud` обнуляє `final_growth` і виставляє
  # `stress_index = 1.0`, тобто це грошовий шлях.
  # ⊕ Живий антифрод НЕ тут, і він справжній: DCI-парність device-Z ≡ server-Z
  # ([`05_02`](../../docs/05_02_Proof_of_Growth_Pipeline.md)) — незалежна від цього гарда.
  # 🔓 Тригер повернення: поява ДРУГОГО виміряного пер-деревного сигналу.
  def detect_fraud?(_stats, _baseline)
    false
  end

  # 🔴 [ARCH.103] Нуль викликачів у `app/` — але це residual ЗНЯТТЯ, не забуття:
  # єдиним споживачем була фрод-арифметика, оголошена інертною двома методами вище.
  # Лишено з тригером, а не зрізано, тим самим рішенням, що й сусід `detect_fraud?`:
  # утиліта чиста, і оживе автоматично разом із гардом, коли зʼявиться другий
  # виміряний пер-деревний сигнал. ⛔ Не додавай сюди виклику раніше за нього.
  # 🔓 Тригер той самий, що в `detect_fraud?` вище.
  def calculate_deviation(value, base)
    return 0.0 if base.zero?
    ((value - base).abs / base).round(4)
  end

  # [VPD weather-confounder gate — 04_02 §VPD, 05_05 §7] DISCOUNT-ONLY.
  # Lowers stress_index when a low sap_flow is explained by WEATHER, not disease:
  # saturated air (rain/fog → low VPD) gives near-zero transpiration pull, so sap
  # legitimately drops on a HEALTHY tree. Without this, a regional humid spell
  # would push a whole cluster past the 20% slash threshold — a FALSE slash
  # against the forester. Never RAISES stress (discount-only invariant).
  #
  # INERT (returns stress unchanged) when ANY holds — by design we ship NO guessed
  # kPa threshold into the slashing path:
  #   • avg_vpd nil       → firmware not yet emitting VPD (HW.32 / 03_01)
  #   • calibration nil   → ground-truth thresholds unset (07_03 §1.4)
  #   • VPD not low        → normal/high VPD = no weather excuse for low sap
  #   • sap near baseline  → nothing weather could account for
  #
  # ⚠️ Activate ONLY after all three land: firmware VPD + ML-retrain (vpd feature
  # in silken_forest.marshal) + ground-truth calibration. Until then a wired,
  # tested no-op. NB: the heuristic still ignores sap entirely (GAP, 05_05 §7) —
  # a signed low-sap (not |dev|) test is part of that calibration follow-up.

  # 🔴 ІНЕРТНИЙ, і причина названа. Гейт існує, щоб ЗНИЖУВАТИ стрес, коли
  # пригнічений метаболізм пояснюється погодою (насичене повітря → нульова
  # транспіраційна тяга), а не хворобою. Тобто його передумова — ДВА входи:
  # погода І метаболічне відхилення. Другого немає: `sap_flow` не мав жодного
  # писача і знятий, а дисконтувати стрес лише за вологим днем означало б
  # вибачати посуху погодою без жодного підтвердження з дерева.
  # ⚠️ Напрямок несучий: гейт тільки ЗНИЖУЄ, тож його інертність безпечна —
  # вона лишає стрес як є, а не вигадує його.
  # 🔓 Тригер: поява метаболічного виміру на рівні дерева (E.63 `delta_t`).
  def apply_weather_confounder(stress_index, _avg_vpd)
    stress_index
  end

  # ⚠️ Порядок фіч — КОНТРАКТ із тренером (`lib/tasks/ai_train.rake`): міняючи його,
  # міняй обидва боки одним ходом, інакше модель дістане чужу вісь під своїм іменем.
  def calculate_stress_index(max_status, avg_temp, max_acoustic, avg_z, avg_vcap = 0)
    if @ai_model
      features = Numo::DFloat.cast([ [ avg_temp.to_f, avg_vcap.to_f, avg_z.to_f, max_acoustic.to_f ] ])
      proba = @ai_model.predict_proba(features)
      stress_class_index = @ai_model.classes.to_a.index(1)

      unless stress_class_index
        Rails.logger.error "🛑 [Insight] ML-модель не містить клас 1 (stress). Fallback на евристику."
        return calculate_stress_index_heuristic(max_status, avg_temp, max_acoustic, avg_z)
      end

      proba[0, stress_class_index].round(3)
    else
      calculate_stress_index_heuristic(max_status, avg_temp, max_acoustic, avg_z)
    end
  end

  # [E.64] Conformance with 05_05 §7 "Z alone never slashes" (audit #3).
  # `_avg_temp`/`_avg_z` accepted for signature symmetry with the ML path but
  # NO LONGER used by the heuristic — both were confounds (see below).
  def calculate_stress_index_heuristic(max_status, _avg_temp, _max_acoustic, _avg_z)
    # [SLASH-1] vm_error (status 3) = софт-збій прошивки (mruby crash / unprovisioned),
    # NOT bio-stress and NOT tamper: the old `>= 3 → 1.0` short-circuit put a firmware
    # bug ABOVE the slash threshold (0.83) — a cluster-wide bad OTA read as max-stress
    # on every tree (slash trigger + damage sizing at once). The status channel on a
    # vm_error day is simply UNKNOWN → contribute 0, let DIRECT signals speak; the
    # ops-side lives in the :firmware_fault EwsAlert (AlertDispatchService). Deliberate
    # conservatism: MAX(bio_status) with vm_error masks a same-day stress/anomaly —
    # undercounting stress < falsely slashing («не карати жертву»).
    # [E.64] Removed two confounded terms: the always-on `avg_z>2 → +0.2` (z_eq=ρ−1≥9,
    # so it never discriminated — a constant sitting at the 0.20 threshold) and the
    # ambient `temp → +0.1` weather term (humid/extreme weather suppresses sap on a
    # HEALTHY tree — the VPD gate DISCOUNTS for that; weather must never ADD stress).
    # Stress now = status-category (Z-categorical, ρ-relative E.64) + DIRECT signals.
    # A Z-derived ANOMALY (status 2) does NOT slash alone: bounded 0.6 < 0.83 tree
    # slash threshold (05_05 §3) — only DIRECT signals (sap / cavitation) can carry
    # it past the threshold.
    # Єдине місце поза enum'ом, що трактує bio_status-інти (SQL MAX-агрегат) —
    # тримаємо прив'язку до TelemetryLog.bio_statuses, не голі літерали.
    stress_code  = TelemetryLog.bio_statuses.fetch("stress")
    anomaly_code = TelemetryLog.bio_statuses.fetch("anomaly")
    # 🔴 [ARCH.102] Прямих сигналів у евристиці НЕМАЄ, і це СТЕЛЯ, не пропуск.
    # Обидва кандидати відпали з однієї причини — величини, про яку вони мали
    # свідчити, ніхто не міряє: `sap_flow` не мав писача взагалі, а `acoustic_events`
    # писача має, але канал ЗМІШАНИЙ — прошивка інкрементує той самий uint8 і на
    # кавітації (`ml_event_id == 2`), і на бензопилі (`== 3`, обидві зони
    # впевненості), тож «посуха» з нього не деривується ЖОДНИМ порогом.
    # ⛔ Наслідок мусить бути видно саме звідси: евристичний шлях має стелю
    # 0.6 < 0.83 (поріг слешингу дерева, 05_05 §3) — слешинг ним НЕДОСЯЖНИЙ.
    # Повертати прямий терм — лише з роздільним лічильником на дроті
    # (кавітація ⊥ пилка), не з новою калібровкою → 00_07 ARCH.102.
    max_status.between?(stress_code, anomaly_code) ? 0.6 : 0.0
  end

  def aggregate_clusters!(cluster_ids)
    Cluster.where(id: cluster_ids).find_each do |cluster|
      aggregate_cluster!(cluster)
    end
  end

  # Створює cluster-level AiInsight на основі tree-level інсайтів.
  # Використовується як у синхронному perform, так і в батчевому process_cluster_batch.
  #
  # 🔴 [ARCH.84] Цей рядок — СЕРЕДНЄ по деревах, що вийшли в ефір, тож він правдивий
  # про них і НІМИЙ про решту. Доти єдиним місцем, де ця різниця взагалі існувала,
  # була ПРОЗА `summary` («Оброблено N вузлів»): кластер із одним виміряним деревом
  # із пʼяти давав той самий `stress_index`, той самий `clusters.health_index` і те
  # саме `Cluster.health_coverage(measured: 1, total: 1)`, що й кластер, виміряний
  # повністю — виміряно рантаймом, обидва кінці діапазону дали ІДЕНТИЧНИЙ машинний
  # вивід. А читачів цього числа троє, і всі несучі: `Cluster#recalculate_health_index!`
  # (звідти в комерційний `backing_asset.cluster_health`), `Celo::CommunityRewardService`
  # (реальна виплата) і `Filecoin::ArchiveService` (незмінний D-MRV доказ в IPFS).
  # ⊕ Форма ліку НЕ нова: `ApplicationComponent#measurement_coverage` уже несе це
  # правило дослівно, а `Cluster.health_coverage` — його ратифікований зразок ПОВЕРХОМ
  # ВИЩЕ (`04_01 §3`). Бракувало саме кластерного члена родини.
  #
  # ⚠️ Популяція — `trees.active`, як у ВСІХ трьох денних читачів (`DailyHealthRouter#insights`,
  # `BlockchainBurningService#calculate_damage_ratio`). Доти писач брав `cluster.trees`
  # цілком, тож інсайт мертвого дерева входив у середнє ЖИВОГО лісу — те саме
  # «кладовище розбавляло», що ⚖️ 2026-07-30 зняв на слешинг-шляху й не зняв тут.
  # ⚠️ `total` іде ЖИВИМ `COUNT`, а не денормалізованим `active_trees_count`: рядок
  # годує гроші й доказ, а лічильник тримають колбеки, які `update_all`/`update_columns`
  # обходять — той самий вибір, що в `calculate_damage_ratio` (тригер має право читати
  # лічильник, розмір — ні).
  #
  # ⛔ СТЕЛЯ, названа явно й ВИМІРЯНА (спроба збудувати пін її й показала):
  # `average(:stress_index)` усереднює РЯДКИ, а `measured` рахує ДЕРЕВА (`.distinct`,
  # дзеркало `DailyHealthRouter#critical_count`). Розійтись вони могли б лише на
  # дублікаті одного дерева за добу, який unique-індекс легалізує через nullable
  # `model_source` — але такий рядок до цього підрахунку НЕ ДОЖИВАЄ: `#perform`
  # починається з тотального `AiInsight…delete_all` по добі, тобто зносить і чужі
  # `model_source`. Отже `.distinct` тут — не виправлення живого дефекту, а дзеркало
  # ратифікованої форми на випадок, коли ідемпотентний зріз перестане бути тотальним.
  # 🔓 Тригер перегляду ОБОХ: перший писач денного інсайту поза цим сервісом.
  def aggregate_cluster!(cluster)
    active_tree_ids = cluster.trees.active.select(:id)

    tree_insights = AiInsight.where(
      analyzable_type: "Tree",
      analyzable_id: active_tree_ids,
      insight_type: :daily_health_summary,
      target_date: @date
    )

    measured_trees = tree_insights.select(:analyzable_id).distinct.count
    return if measured_trees.zero?

    total_trees = cluster.trees.active.count
    # ⚡ [ОПТИМІЗАЦІЯ]: Використовуємо boolean колонку замість JSONB @> оператора
    fraud_trees = tree_insights.where(fraud_detected: true).select(:analyzable_id).distinct.count

    summary = if fraud_trees > 0
                "⚠️ Сектор #{cluster.name}: Виявлено #{fraud_trees} вузлів із фрод-телеметрією."
    else
                "Сектор #{cluster.name}: Оброблено #{measured_trees} вузлів. Стан стабільний."
    end

    AiInsight.create!(
      analyzable: cluster,
      insight_type: :daily_health_summary,
      target_date: @date,
      stress_index: tree_insights.average(:stress_index).to_f.round(3),
      total_growth_points: tree_insights.sum(:total_growth_points),
      summary: summary,
      reasoning: { measured_trees: measured_trees, total_trees: total_trees }
    )
  end

  def generate_summary(status, temp)
    case status
    when 3 then "ЗБІЙ ПРОШИВКИ: пристрій не зміг порахувати біостатус (mruby VM error) — потрібен re-flash/OTA."
    # ⛔ Рядок називає СТАН, не причину: атрактор класифікує положення Z відносно
    # обвідної (03_04 §4.2) і про світ за цим сигналом не свідчить. Доти тут стояли
    # «хвороба або шкідники» (класу «комаха» в TinyML немає взагалі) та «реагує на
    # зовнішнє середовище» при супутній температурі — обидва читались як діагноз,
    # і обидва йдуть у `AiInsight#summary` просто на екран.
    when 2 then "АНОМАЛІЯ: Z вийшов за обвідну гомеостазу; причину сигнал не називає."
    when 1 then "СТРЕС: Z нижче критичного мінімуму (супутня температура #{temp.round(1)}°C)."
    else "ГОМЕОСТАЗ: Стан дерева ідеальний."
    end
  end

  def load_ai_model
    return nil unless File.exist?(MODEL_PATH)

    model_data = File.binread(MODEL_PATH)
    verify_model_integrity!(model_data)

    Marshal.load(model_data) # rubocop:disable Security/MarshalLoad
  rescue StandardError => e
    Rails.logger.warn "⚠️ [Insight] Не вдалося завантажити ML-модель: #{e.message}. Використовуємо евристику."
    nil
  end

  def verify_model_integrity!(model_data)
    unless File.exist?(MODEL_DIGEST_PATH)
      raise "SHA256-дайджест моделі не знайдено: #{MODEL_DIGEST_PATH}"
    end

    expected_digest = File.read(MODEL_DIGEST_PATH).strip
    actual_digest = OpenSSL::Digest::SHA256.hexdigest(model_data)

    unless ActiveSupport::SecurityUtils.secure_compare(actual_digest, expected_digest)
      raise "SHA256-дайджест моделі не збігається (можлива підміна файлу)"
    end
  end
end
