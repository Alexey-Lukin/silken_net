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
    # Строк дії доказу за замовчуванням: тиждень покриває ретраї вироку, прогнаного одразу
    # після ескалації, і не тягне доказ на події, про які він нічого не каже. DAO-live.
    DEFAULT_EVIDENCE_VALIDITY_HOURS = 168

    # @param cluster [Cluster] кластер під оцінкою
    # @param contract [NaasContract] договір, під яким стоїть вирок. Обовʼязковий свідомо:
    #   без нього доказ не мав би часової межі, і пропущений аргумент мовчки обирав би
    #   гілку «палити», а не «морозити».
    # @param source_tree [Tree, nil] дерево-джерело (tree-death шлях) — резерв під
    #   майбутнє per-tree звуження; фаза-1 оцінює на рівні кластера (tamper-алерт
    #   несе cluster_id, тож cluster-scope його ловить).
    def initialize(cluster, contract:, source_tree: nil)
      @cluster = cluster
      @contract = contract
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
    #
    # 🔒 [SLASH-1, ⚖️ делеговано 2026-09-22] Закривати доказ тепер може тільки платформа
    # (`EwsAlert#closable_by?`), тож відкритий він живе, доки його не закриють. Звідси ДВІ
    # межі, і обидві несучі:
    #   · ТЕРМІН ДОГОВОРУ — доказ записано, поки ЦЕЙ договір був чинним (`start_date …
    #     cancelled_at || end_date`, і сам договір `active`). Без неї доказ спалив би договір,
    #     підписаний після інциденту, — і прострочений: `fulfill` не має викликача, тож
    #     договір по `end_date` лишається `active` і отримує тригери далі.
    #   · СТРОК ДІЇ — `slash_evidence_validity_hours` від запису. Ворота не знають, ЯКИЙ
    #     інцидент довів доказ, тож без строку він відчиняв би їх для будь-якого пізнішого,
    #     не повʼязаного тригера (природна посуха через пів року → незворотний слеш).
    #     Рецепт `06_08 §4.6` проганяє вирок інциденту одразу після ескалації.
    # Одноразовість усередині договору тримає не доказ, а РЕЄСТР: `BurnCarbonTokensWorker`
    # мовчить на `:sent`/`:confirmed` burn-інтенті без горизонту, сервіс — на `:manual_review`.
    # Хибний або відсутній вхід (нема дат, строк 0) дає «доказу немає» → freeze, ніколи burn.
    # ⚠️ Стеля: `created_at` — мить ЗАПИСУ доказу аудитором, не інциденту; інцидент під
    # договором, що встиг скінчитись до запису, ляже на договір, чинний у мить запису, а сам
    # скінчений не горить.
    def tamper_breach?
      window = evidence_window
      return false unless window

      @cluster.ews_alerts.critical
              .where(alert_type: EwsAlert::CATEGORY_A_EVIDENCE_TYPES)
              .where(created_at: window)
              .exists?
    end

    def evidence_window
      return unless @contract.status_active?

      term_end = @contract.cancelled_at || @contract.end_date
      return if @contract.start_date.nil? || term_end.nil?

      validity = SystemParameter.current(:slash_evidence_validity_hours,
                                         default: DEFAULT_EVIDENCE_VALIDITY_HOURS).to_i.hours
      [ @contract.start_date, validity.ago ].max..[ term_end, Time.current ].min
    end
  end
end
