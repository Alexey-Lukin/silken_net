# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Slashing
  # [SLASH-1 §3.2] Positive-A-evidence gate (Категорія A — халатність/зловмисність).
  #
  # Дім ОДНОГО питання: чи є ≥1 ПРЯМИЙ доказ Категорії A для кластера? Чокпоінт
  # `BlockchainBurningService` пропускає НЕОБОРОТНИЙ `slash()` лише коли `positive_a?`;
  # інакше → freeze (Field Audit, Категорія C — `05_05 §2/§5`). Це відновлює канонічний
  # safety-дефолт (`00_01 §6`: «не карати жертву; вирок вимагає прямого сигналу»), а не
  # палить-поки-не-відведено. Асиметрія свідома: burn необоротний, freeze — ні.
  #
  # Фаза 1 свідомо КОНСЕРВАТИВНА — лише `vandalism_breach` (tamper) як єдиний однозначний
  # сигнал A у поточному коді. [SLASH-1 P0] Автоматичного ДЖЕРЕЛА vandalism_breach наразі
  # НЕМАЄ: wire status=3 виявився BIO_STATUS_VM_ERROR (софт-збій → :firmware_fault,
  # AlertDispatchService), а справжня пилка їде panic→`chainsaw_detected`. Ворота лишаються
  # wired і чесно-порожні: до наповнення A-сету КОЖЕН slash-тригер іде freeze/Field-Audit.
  # Джерела vandalism_breach: ручна C→A ескалація Field-Audit (console-рецепт, `06_08 §4.6`) зараз;
  # chainsaw після field-validation TinyML (клас = synthetic placeholder, `03_03 §4.2`;
  # slash() необоротний) та майбутній HW tamper-канал (tamper-switch/SE05x) — потім.
  # `critical_unmaintained?` досі рахує й force-majeure-типи (aged `fire_detected` без
  # maintenance → пропустив би burn на природній пожежі). Розширення A-сету (scoped
  # unmaintained, chainsaw після field-validation) — 👤 DAO-ратифікація (`05_05 §3.2`,
  # рейка `ProtocolParameters` → `SystemParameter`, `05_06`).
  #
  # DCI-divergence / fraud-алерт (`system_fault`) НЕ є самостійним сигналом A — `05_05 §6`
  # (divergence сам ≠ burn; потрібен 2-й некорельований сигнал).
  class CauseEvidence
    # @param cluster [Cluster] кластер під оцінкою
    # @param source_tree [Tree, nil] дерево-джерело (tree-death шлях) — резерв під
    #   майбутнє per-tree звуження; фаза-1 оцінює на рівні кластера (tamper-алерт
    #   несе cluster_id, тож cluster-scope його ловить).
    def initialize(cluster, source_tree: nil)
      @cluster = cluster
      @source_tree = source_tree
    end

    # ≥1 прямий доказ Категорії A. Сьогодні = tamper (розкриття корпусу).
    def positive_a?
      tamper_breach?
    end

    # Символ-причина для аудиту/логу (nil, якщо доказу A немає).
    def reason
      :tamper if tamper_breach?
    end

    private

    # Tamper / розкриття корпусу: живий critical-алерт `vandalism_breach` — однозначна
    # ознака людського втручання (Категорія A, `05_05 §6` hardware tamper → авто-A).
    # [SLASH-1 P0] Автоматичний writer знято (wire status=3 = vm_error, не tamper);
    # алерт створює лише людина (Field-Audit C→A, `06_08 §4.6`) або майбутнє
    # validated-джерело — див. шапку класу.
    def tamper_breach?
      @cluster.ews_alerts.critical.alert_type_vandalism_breach.exists?
    end
  end
end
