# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Filecoin
  # =========================================================================
  # 📦 FILECOIN ARCHIVE SERVICE (Вічна Пам'ять Планети)
  # =========================================================================
  # Архівує AuditLog записи до децентралізованого сховища IPFS/Filecoin
  # через API-шлюз (Web3.storage / Pinata). Кожен заархівований запис
  # отримує унікальний CID (Content Identifier), який неможливо підробити.
  #
  # Навіть якщо сервери зникнуть, будь-який дослідник зможе завантажити
  # криптографічно підтверджений звіт через Filecoin Explorer.
  # =========================================================================
  class ArchiveService
    # [SEC.18 / DPIA M6] Ключ metadata, не оголошений у `AuditLog::ARCHIVED_METADATA_KEYS`,
    # у публічний пін не їде — перелік легальних ключів веде людина, не регекс.
    class UndeclaredMetadataError < StandardError; end

    # Pinata IPFS pinning endpoint (сумісний з Web3.storage та іншими шлюзами)
    # Може бути перевизначений через ENV для інших середовищ
    PINATA_API_URL = ENV.fetch("FILECOIN_PINNING_API_URL", "https://api.pinata.cloud/pinning/pinJSONToIPFS")

    # Таймаути для децентралізованого сховища (uploads бувають повільними)
    OPEN_TIMEOUT  = 15  # секунд на встановлення з'єднання
    READ_TIMEOUT  = 30  # секунд на очікування відповіді

    # Стабільні поля, над якими рахується детермінований content-CID (E.60).
    # БЕЗ `archived_at` (час пінінгу) і `metadata`/`telemetry_summary` (можуть
    # легітимно змінитись) — інакше CID був би невідтворюваний при верифікації.
    CONTENT_DIGEST_KEYS = %w[
      audit_log_id organization_id action chain_hash auditable_type auditable_id created_at
    ].freeze

    # Стабільний підпис аудит-запису — спільне джерело для пінінгу і верифікації
    # (один опис полів, нуль drift між archive і verify).
    def self.content_attrs(audit_log)
      {
        audit_log_id:    audit_log.id,
        organization_id: audit_log.organization_id,
        action:          audit_log.action,
        chain_hash:      audit_log.chain_hash,
        auditable_type:  audit_log.auditable_type,
        auditable_id:    audit_log.auditable_id,
        created_at:      audit_log.created_at&.iso8601
      }
    end

    # Детермінований CIDv1 над стабільним підписом (`05_02 §E.60`). Приймає
    # будь-який hash (символьні чи рядкові ключі) — зрізає лише CONTENT_DIGEST_KEYS.
    def self.content_cid(source)
      digest = source.transform_keys(&:to_s).slice(*CONTENT_DIGEST_KEYS)
      Filecoin::CidGenerator.cidv1(digest)
    end

    def initialize(audit_log)
      @audit_log = audit_log
    end

    # Головний метод — серіалізує AuditLog і завантажує на IPFS/Filecoin
    #
    # 🔴 ЦЕЙ РАННІЙ RETURN РОБИТЬ FORCE-REPIN НЕМОЖЛИВИМ, і разом із сусідом утворює
    # ЛАНЦЮГ, якого не видно з жодної його ланки окремо [INF.22, Phase-2 deferred]:
    #   1. `FilecoinVerificationSweepWorker` ВИЯВЛЯЄ недосяжний пін — і кладе цей факт
    #      у лічильник статистики та `Rails.logger.warn`, тобто НІКУДИ не персистить;
    #   2. отже `FilecoinReconcileWorker` не має що прочитати — стану «пін зник» у БД
    #      не існує, а `archive_requested_at` лишається виставленим і виглядає здоровим;
    #   3. а якби реконсиляція й дізналась — цей `return` мовчки нічого не зробив би,
    #      бо `ipfs_cid` присутній: сам факт минулого піну блокує повторний.
    # Тобто архів може бути НЕДОСЯЖНИМ, а тракт — зеленим на всіх трьох ланках. Лік
    # потребує персистованого стану verification-failure (колонка) + unpin-семантики,
    # і саме тому він Phase-2, а не однорядкова правка `return`'у.
    # ⚠️ Phase-1 — це forward-marker для НОВИХ логів, не backfill: рядки, створені до
    # міграції, мають `ipfs_cid = NULL` І `archive_requested_at = NULL`, тож невидимі
    # для reconcile взагалі; при launch їх піднімає ОДНОРАЗОВИЙ
    # `UPDATE audit_logs SET archive_requested_at = created_at
    #    WHERE ipfs_cid IS NULL AND auditable_type = 'BlockchainTransaction'`
    # (👤, свідомо повертає auditable_type-евристику рівно на цей один прохід).
    def archive!
      return if @audit_log.ipfs_cid.present?

      cid = self.class.pin_json!(
        build_content,
        name: "silkennet-audit-#{@audit_log.id}",
        keyvalues: {
          organization_id: @audit_log.organization_id.to_s,
          chain_hash: @audit_log.chain_hash.to_s
        }
      )

      @audit_log.update!(ipfs_cid: cid)

      Rails.logger.info "📦 [Filecoin] Archived AuditLog ##{@audit_log.id} → CID: #{cid}"

      cid
    end

    private

    # Формує content для піну (дані аудит-логу + добові зведення телеметрії).
    # У вміст вбудовується самоописовий `content_cid` (E.60): верифікатор згодом
    # перерахує CID і виявить ex-post підміну архіву (`05_02 §E.60`).
    # Pinata-обгортку (pinataContent/pinataMetadata) додає pin_json!.
    def build_content
      content = self.class.content_attrs(@audit_log).merge(
        metadata: declared_metadata,
        telemetry_summary: build_telemetry_summary,
        archived_at: Time.current.iso8601
      )
      content[:content_cid] = self.class.content_cid(content)
      content
    end

    # [SEC.18 / DPIA M6 проти R7] Межа незворотності. Відмова тут ГУЧНА свідомо:
    # тихий стрип змінив би сам доказ, а тихий пропуск — незворотний, тоді як raise
    # нічого не губить (`archive_requested_at` лишається, `FilecoinReconcileWorker`
    # підбирає, `FILECOIN_REPIN_TOTAL` росте). Дім переліку — модель, бо факт про
    # аудит-запис, а не про транспорт.
    def declared_metadata
      metadata = @audit_log.metadata || {}
      undeclared = metadata.keys.map(&:to_s) - AuditLog::ARCHIVED_METADATA_KEYS
      return metadata if undeclared.empty?

      raise UndeclaredMetadataError,
        "🛑 [SEC.18] AuditLog ##{@audit_log.id}: недекларовані ключі metadata для " \
        "публічного піна — #{undeclared.sort.join(', ')}. Оголоси їх у " \
        "AuditLog::ARCHIVED_METADATA_KEYS (з підставою) або не архівуй цей шлях."
    end

    # Збирає добове зведення телеметрії для організації на дату аудит-логу.
    # AiInsight (daily_health_summary) зберігає агреговані метрики по кожному дереву/кластеру.
    def build_telemetry_summary
      target_date = @audit_log.created_at&.to_date
      return nil unless target_date

      # 🔴 [ARCH.57] Глобальний системний ланцюг легітимно не має організації
      # (`AuditLog belongs_to :organization, optional: true` — `nil` там ЗНАЧИТЬ
      # «подія платформи», а не «організація невідома»), і саме тому цей рядок
      # мусить оголосити стан, а не звузити запит: Rails перекладає
      # `where(organization_id: nil)` у `IS NULL`, тобто у ФІЛЬТР, ЩО ЗБІГАЄТЬСЯ
      # з org-less кластерами, а не в порожню множину. Правило вже сформульоване
      # в цьому дереві двічі (`ApplicationPolicy#no_acting_organization?` [UI.7]
      # + `WalletPolicy`) — тут лишався єдиний сайт із легітимно-nil джерелом.
      # ⚠️ Сьогодні набір порожній ВИПАДКОВО, і випадковість трирівнева:
      # org-less кластерів нуль · `Cluster belongs_to :organization` без
      # `optional:` не дає створити такий кластер через AR · глобальний ланцюг
      # до архіву поки не доходить (`archive:` за замовчуванням `false`).
      # Ціна ненульова саме тут: артефакт іде в IPFS ЯК ДОКАЗ, тож перший
      # org-less кластер додав би до глобальної події «добове зведення
      # телеметрії організації», якої в тієї події немає.
      organization_id = @audit_log.organization_id
      return nil if organization_id.nil?

      org_cluster_ids = Cluster.where(organization_id: organization_id).select(:id)

      summaries = AiInsight
        .daily_health_summary
        .where(target_date: target_date)
        .where(analyzable_type: "Cluster", analyzable_id: org_cluster_ids)
        .select(:analyzable_id, :stress_index, :total_growth_points, :fraud_detected, :reasoning)

      return nil if summaries.empty?

      {
        date: target_date.iso8601,
        clusters: summaries.map do |insight|
          {
            cluster_id: insight.analyzable_id,
            stress_index: insight.stress_index&.to_f,
            # 🔴 [ARCH.84] Покриття їде РАЗОМ зі стресом, і саме тут воно найдорожче:
            # цей артефакт пінується в IPFS ЯК ДОКАЗ, тож аудитор, що його відкриє,
            # мусить бачити, про скільки дерев говорить середнє. Доти 1-із-5 і 5-із-5
            # були в архіві невідрізнимі. `nil` = інсайт старший за це поле.
            measured_trees: insight.measured_trees,
            total_trees: insight.total_trees,
            total_growth_points: insight.total_growth_points,
            # 🔴 [SEC.18] ВІЛЬНОГО ТЕКСТУ тут немає й бути не може — це стеля, а не
            # оптимізація. `AiInsight#summary` є відрендереним реченням, яке інтерполює
            # `cluster.name`: колонка `character varying`, валідована лише на presence
            # і uniqueness, тобто вільний рядок ЛЮДИНИ (назва сектора вміє нести
            # прізвище, господарство чи адресу). Пін незворотний — запінене не стирає
            # ані DSAR, ані `Gdpr::AnonymizeUserService`, — тож форму обрано за тим
            # самим дискримінатором, що й для `error` (⚖️ 2026-08-27): напрямок
            # дефолту на НЕЗВОРОТНІЙ поверхні. Тут він дає не класифікатор, а
            # ВІДСУТНІСТЬ поля: fail-closed за побудовою, бо текстового каналу немає.
            # ⊕ Доказ від цього не збіднів: решта рядка — ті самі величини, з яких
            # проза й рендериться, а єдина, що жила ТІЛЬКИ в реченні, піднята в
            # структуру (`fraud_trees`, `04_01 §7`). Проза лишається в БД і на екрані.
            # ⚠️ `telemetry_summary` не входить у `CONTENT_DIGEST_KEYS`, тож зміна
            # форми цього блоку НЕ зсуває жодного вже виданого `content_cid`.
            fraud_trees: insight.fraud_trees,
            fraud_detected: insight.fraud_detected
          }
        end
      }
    end

    # [E.60 Фаза 1б] One-Home Pinata-виклик: юзають audit-шлях (цей сервіс) і
    # телеметрія-батч-пін (TelemetryArchiveBatchWorker). Повертає CID.
    def self.pin_json!(content, name:, keyvalues: {})
      api_key = ENV["FILECOIN_API_KEY"].presence || Rails.application.credentials.filecoin_api_key
      raise "🛑 [Filecoin] Missing filecoin_api_key in credentials" if api_key.blank?

      response = Web3::HttpClient.post(PINATA_API_URL,
        body: {
          pinataContent: content,
          pinataMetadata: { name: name, keyvalues: keyvalues.merge(source: "silken_net") }
        },
        headers: { "Authorization" => "Bearer #{api_key}" },
        open_timeout: OPEN_TIMEOUT,
        read_timeout: READ_TIMEOUT,
        service_name: "Filecoin"
      )

      cid = response.parsed_body["IpfsHash"]
      raise "🛑 [Filecoin] No CID returned from IPFS pinning service" if cid.blank?

      cid
    end
  end
end
