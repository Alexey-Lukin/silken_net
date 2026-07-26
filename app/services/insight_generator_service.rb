# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

class InsightGeneratorService < ApplicationService
  # Поріг відхилення. Якщо вологість/температура дерева відрізняється від
  # середньої по кластеру більше ніж на 30%, це класифікується як фрод/аномалія.
  FRAUD_DEVIATION_THRESHOLD = 0.30

  MODEL_PATH = Rails.root.join("lib/assets/silken_forest.marshal").freeze
  MODEL_DIGEST_PATH = Rails.root.join("lib/assets/silken_forest.marshal.sha256").freeze

  def initialize(date = Time.current.utc.to_date - 1)
    @date = date
    @start_time = date.beginning_of_day
    @end_time = date.end_of_day
    @processed_count = 0
    @ai_model = load_ai_model
  end

  # Синхронний режим: обробляє ВСІ кластери в одному процесі.
  # Підходить для малих датасетів або прямого виклику через InsightGeneratorService.call(date).
  # Для масштабу 10M+ дерев використовуйте InsightGeneratorOrchestratorWorker (Sidekiq::Batch).
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

      unless processed_cluster_ids.empty?
        Cluster.where(id: processed_cluster_ids).find_each do |cluster|
          process_cluster_trees(cluster, @baselines_map[cluster.id])
        end

        # 3. АГРЕГАЦІЯ КЛАСТЕРІВ — тільки для кластерів з даними (без повторної ітерації)
        aggregate_clusters!(processed_cluster_ids)
      end
    end

    # 4. КЕНОЗИС: Очищення сирих логів (поза транзакцією — ідемпотентна операція
    # на іншому діапазоні дат, не потребує атомарності з інсайтами)
    cleanup_old_logs!

    Rails.logger.info "✅ [Insight Generator] Цикл завершено. Оброблено вузлів: #{@processed_count}"
    { processed_count: @processed_count, date: @date }
  end

  # =========================================================================
  # PUBLIC API ДЛЯ БАТЧЕВОГО РЕЖИМУ (Sidekiq::Batch)
  # =========================================================================
  # Використовується GenerateClusterInsightWorker для обробки чанку кластерів.
  # Кожен воркер отримує масив cluster_ids та обробляє їх незалежно.

  # Повертає Hash { cluster_id => { temp:, sap:, z: } } для кластерів, що мають дані.
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

  # Очищення сирих логів старше 7 днів (публічний для виклику з InsightBatchCallbacks).
  # [БЕЗПЕКА]: Не видаляємо логи з oracle_status = 'dispatched' — вони очікують
  # Chainlink callback для завершення Proof of Growth pipeline.
  # Видалення таких логів призведе до втрати мінтингу SCC (RecordNotFound
  # в OracleCallbacksController при зворотному виклику оракула).
  def self.cleanup_old_logs!
    threshold = 7.days.ago.end_of_day
    # [Batch Delete]: delete_all на мільйонах рядків може заблокувати таблицю.
    # in_batches видаляє по 10 000 записів за раз, знижуючи навантаження на Lock Manager.
    TelemetryLog.where("created_at <= ?", threshold)
                .where.not(oracle_status: "dispatched")
                .in_batches(of: 10_000, &:delete_all)
  end

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
           "AVG(sap_flow) as avg_sap",
           "AVG(z_value) as avg_z"
         ).each_with_object({}) do |row, hash|
           hash[row.cluster_id] = {
             temp: row.avg_temp.to_f,
             sap: row.avg_sap.to_f,
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
                  "AVG(sap_flow) as avg_sap",
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
      next unless stats

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
    stress_index = is_fraud ? 1.0 : calculate_stress_index(stats.max_status.to_i, stats.avg_temp.to_f, stats.max_acoustic.to_i, stats.avg_z.to_f, stats.avg_vcap.to_i, calculate_deviation(stats.avg_sap.to_f, baseline[:sap]), signed_deviation(stats.avg_sap.to_f, baseline[:sap]))

    # [VPD weather-confounder, 05_05 §7] Discount-only weather gate so a
    # humid spell (low VPD → suppressed sap on a HEALTHY tree) cannot push a
    # cluster over the slash threshold. Inert until firmware sends VPD + ML
    # retrain + ground-truth calibration (see #apply_weather_confounder). Fraud
    # stays pinned at 1.0 — weather never excuses anomalous deviation.
    unless is_fraud
      stress_index = apply_weather_confounder(
        stress_index, stats.avg_vpd&.to_f, calculate_deviation(stats.avg_sap.to_f, baseline[:sap])
      )
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
        avg_vpd: stats.avg_vpd&.to_f&.round(3), # nil доки firmware не шле VPD (HW.32)
        deviation_from_baseline: calculate_deviation(stats.avg_sap.to_f, baseline[:sap])
      }
    )

    # [ВИПРАВЛЕНО: N+1 TreeBlueprint#current_stress]:
    # Денормалізуємо stress_index прямо в таблицю trees (аналогічно latest_voltage_mv).
    # Це усуває N+1 запит для кожного дерева при серіалізації (TreeBlueprint, MapNode).
    # Використовуємо update_column для швидкодії без callbacks (hot path для мільйонів дерев).
    tree.update_column(:latest_stress_index, stress_index)

    # ⚡ [ВИПРАВЛЕНО: Жорсткий Slashing]:
    # Ми більше не "вбиваємо" дерево миттєво. Створюємо критичну тривогу для перевірки.
    # Це захищає інвестора від помилок ШІ, але зупиняє виплати до вердикту людини.
    if is_fraud
      AlertDispatchService.create_fraud_alert!(tree, "Виявлено фрод-телеметрію за #{@date}")
    end

    true
  rescue StandardError => e
    Rails.logger.error "🛑 [Insight] Помилка для Дерева #{tree.did}: #{e.message}"
    false
  end

  def detect_fraud?(stats, baseline)
    return false if baseline[:sap].zero?
    sap_deviation = calculate_deviation(stats.avg_sap.to_f, baseline[:sap])
    temp_deviation = calculate_deviation(stats.avg_temp.to_f, baseline[:temp])
    (sap_deviation > FRAUD_DEVIATION_THRESHOLD) && (temp_deviation > FRAUD_DEVIATION_THRESHOLD)
  end

  def calculate_deviation(value, base)
    return 0.0 if base.zero?
    ((value - base).abs / base).round(4)
  end

  # Signed relative deviation: NEGATIVE = below baseline (the stress direction for
  # sap_flow — suppressed transpiration). Distinct from calculate_deviation, which
  # is the absolute magnitude used for fraud detection + the ML feature. 0.0 when
  # baseline is zero.
  def signed_deviation(value, base)
    return 0.0 if base.zero?
    ((value - base) / base).round(4)
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
  def apply_weather_confounder(stress_index, avg_vpd, sap_deviation)
    return stress_index if avg_vpd.nil?

    calibration = vpd_confounder_calibration
    return stress_index unless calibration
    return stress_index unless avg_vpd <= calibration[:low_kpa]
    return stress_index unless sap_deviation.to_f.positive?

    discounted = stress_index * (1.0 - calibration[:max_discount])
    [ discounted, stress_index ].min.round(3) # discount-only: never above input
  end

  # Calibration-pending config for the VPD gate. Returns nil (→ gate inert) until
  # BOTH ground-truth values are supplied (07_03 §1.4) via ENV — deliberately not
  # hardcoded, so no guessed threshold can silently enter slashing. low_kpa =
  # "saturated air" VPD floor (kPa); max_discount = max stress reduction (0..1].
  def vpd_confounder_calibration
    low = ENV["VPD_CONFOUNDER_LOW_KPA"]&.to_f
    discount = ENV["VPD_CONFOUNDER_MAX_DISCOUNT"]&.to_f
    return nil unless low&.positive? && discount&.positive?

    { low_kpa: low, max_discount: [ discount, 1.0 ].min }
  end

  # sap_deviation = ABSOLUTE deviation (ML feature, unchanged — model trained on it).
  # sap_signed_deviation = SIGNED (negative = below baseline) — fed only to the
  # heuristic's sap term (#sap_stress_contribution), which the ML path doesn't need
  # (its trained feature already carries sap).
  def calculate_stress_index(max_status, avg_temp, max_acoustic, avg_z, avg_vcap = 0, sap_deviation = 0.0, sap_signed_deviation = 0.0)
    if @ai_model
      features = Numo::DFloat.cast([ [ avg_temp.to_f, avg_vcap.to_f, avg_z.to_f, sap_deviation.to_f, max_acoustic.to_f ] ])
      proba = @ai_model.predict_proba(features)
      stress_class_index = @ai_model.classes.to_a.index(1)

      unless stress_class_index
        Rails.logger.error "🛑 [Insight] ML-модель не містить клас 1 (stress). Fallback на евристику."
        return calculate_stress_index_heuristic(max_status, avg_temp, max_acoustic, avg_z, sap_signed_deviation)
      end

      proba[0, stress_class_index].round(3)
    else
      calculate_stress_index_heuristic(max_status, avg_temp, max_acoustic, avg_z, sap_signed_deviation)
    end
  end

  # [E.64] Conformance with 05_05 §7 "Z alone never slashes" (audit #3).
  # `_avg_temp`/`_avg_z` accepted for signature symmetry with the ML path but
  # NO LONGER used by the heuristic — both were confounds (see below).
  def calculate_stress_index_heuristic(max_status, _avg_temp, max_acoustic, _avg_z, sap_signed_deviation = 0.0)
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
    base_stress = (max_status.between?(stress_code, anomaly_code) ? 0.6 : 0.0) # bounded < slash 0.83
    # sap_flow↓ and cavitation↑ are CORRELATED drought signals (one root cause) →
    # take the STRONGER, never SUM (00_01 SLASH-SAFETY: corroboration, not double-penalty).
    # Both inert until ENV-calibrated.
    base_stress += [ sap_stress_contribution(sap_signed_deviation),
                    acoustic_stress_contribution(max_acoustic) ].max
    [ base_stress, 0.99 ].min
  end

  # [Sap-flow stress term — closes the 05_05 §7 GAP where the heuristic ignored
  # sap entirely.] Low sap_flow (below cluster baseline) is the PRIMARY DIRECT
  # drought/disease signal — more grounded than the unproven Lorenz-Z. Only LOW
  # sap (signed dev ≤ −threshold) adds stress; high sap is vigour, never penalised.
  # BOUNDED so sap CORROBORATES but never SOLELY triggers slashing — a status-0
  # tree maxes at this weight (≈0.2 ≪ 0.83), honouring the de-risk "≥1 direct
  # corroborating signal, not Z alone". The VPD gate later discounts this when the
  # low sap is weather-driven (#apply_weather_confounder) → the full sap↔weather loop.
  #
  # INERT by default (0.0): like the VPD gate, NO guessed weight enters live
  # slashing — activates only once ground-truth calibration sets ENV
  # STRESS_SAP_LOW_THRESHOLD + STRESS_SAP_WEIGHT (07_03 §1.4).
  def sap_stress_contribution(sap_signed_deviation)
    calibration = sap_stress_calibration
    return 0.0 unless calibration
    return 0.0 unless sap_signed_deviation <= -calibration[:threshold] # only LOW sap

    calibration[:weight]
  end

  # Calibration-pending config for the sap-stress term. nil (→ term inert) until
  # BOTH ground-truth values are set via ENV (07_03 §1.4): threshold = fraction below
  # baseline that counts as drought-stress (e.g. 0.30); weight = stress increment
  # (e.g. 0.2). Deliberately not hardcoded — no guessed weight in live slashing.
  def sap_stress_calibration
    threshold = ENV["STRESS_SAP_LOW_THRESHOLD"]&.to_f
    weight = ENV["STRESS_SAP_WEIGHT"]&.to_f
    return nil unless threshold&.positive? && weight&.positive?

    { threshold: threshold, weight: [ weight, 0.99 ].min }
  end

  # [Acoustic (cavitation) stress term — closes the acoustic half of the 05_05 §7
  # heuristic GAP, symmetric to the sap term.] acoustic_events = COUNT of phloem
  # cavitation events (TinyML, uint8 saturating at 255; 03_04) — a DIRECT drought /
  # water-tension signal (high cavitation = xylem under stress).
  # ⚠️ This field is CAVITATION only; chainsaw/tamper rides a separate panic /
  # PANIC_FLAG path — so this term NEVER slashes a forester for third-party logging.
  # Only HIGH cavitation (≥ calibrated count) adds stress; bounded + max()'d with the
  # sap term so drought CORROBORATES but never SOLELY slashes. INERT by default —
  # activates only via ground-truth ENV STRESS_ACOUSTIC_THRESHOLD + STRESS_ACOUSTIC_WEIGHT
  # (07_03 §1.4); the max() in the heuristic already prevents same-root-cause stacking.
  def acoustic_stress_contribution(max_acoustic)
    calibration = acoustic_stress_calibration
    return 0.0 unless calibration
    return 0.0 unless max_acoustic.to_i >= calibration[:threshold] # only HIGH cavitation

    calibration[:weight]
  end

  # Calibration-pending config for the acoustic-stress term. nil (→ inert) until both
  # ground-truth values are set via ENV (07_03 §1.4): threshold = cavitation event count
  # that counts as drought-stress (e.g. 50); weight = stress increment (e.g. 0.2).
  # Deliberately not hardcoded — no guessed count in live slashing.
  def acoustic_stress_calibration
    threshold = ENV["STRESS_ACOUSTIC_THRESHOLD"]&.to_i
    weight = ENV["STRESS_ACOUSTIC_WEIGHT"]&.to_f
    return nil unless threshold&.positive? && weight&.positive?

    { threshold: threshold, weight: [ weight, 0.99 ].min }
  end

  def aggregate_clusters!(cluster_ids)
    Cluster.where(id: cluster_ids).find_each do |cluster|
      aggregate_cluster!(cluster)
    end
  end

  # Створює cluster-level AiInsight на основі tree-level інсайтів.
  # Використовується як у синхронному perform, так і в батчевому process_cluster_batch.
  def aggregate_cluster!(cluster)
    tree_insights = AiInsight.where(
      analyzable_type: "Tree",
      analyzable_id: cluster.trees.select(:id),
      insight_type: :daily_health_summary,
      target_date: @date
    )

    return if tree_insights.empty?

    # ⚡ [ОПТИМІЗАЦІЯ]: Використовуємо boolean колонку замість JSONB @> оператора
    fraud_count = tree_insights.where(fraud_detected: true).count

    summary = if fraud_count > 0
                "⚠️ Сектор #{cluster.name}: Виявлено #{fraud_count} вузлів із фрод-телеметрією."
    else
                "Сектор #{cluster.name}: Оброблено #{tree_insights.count} вузлів. Стан стабільний."
    end

    AiInsight.create!(
      analyzable: cluster,
      insight_type: :daily_health_summary,
      target_date: @date,
      stress_index: tree_insights.average(:stress_index).to_f.round(3),
      total_growth_points: tree_insights.sum(:total_growth_points),
      summary: summary
    )
  end

  def cleanup_old_logs!
    self.class.cleanup_old_logs!
  end

  def generate_summary(status, temp)
    case status
    when 3 then "ЗБІЙ ПРОШИВКИ: пристрій не зміг порахувати біостатус (mruby VM error) — потрібен re-flash/OTA."
    when 2 then "АНОМАЛІЯ: Атрактор вказує на хворобу або шкідників."
    when 1 then "СТРЕС: Вузол реагує на зовнішнє середовище (#{temp.round(1)}°C)."
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
