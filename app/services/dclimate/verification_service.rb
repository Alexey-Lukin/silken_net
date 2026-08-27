# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Dclimate
  # [COSMIC EYE]: Помилка орбітальної затримки — супутник не зміг верифікувати
  # через хмарність або кронопокрив. Sidekiq ретраїтиме до 48+ годин.
  class OrbitalLagError < StandardError; end

  # = ===================================================================
  # 🛰️ DCLIMATE VERIFICATION SERVICE (Cosmic Eye — Double Consensus)
  # = ===================================================================
  # Верифікація EWS-алертів через супутникові дані dClimate.
  # Запобігає страховому шахрайству шляхом подвійного консенсусу:
  #   1. fire_confirmed   → satellite_verified  → InsurancePayoutWorker
  #   2. clear_sky_no_fire → rejected_fraud      → BurnCarbonTokensWorker (Slashing)
  #   3. obscured_by_clouds → OrbitalLagError    → Sidekiq retry (до 48 годин)
  #
  # HTTP-інтеграція з dClimate API (FIRMS — Fire Information for Resource
  # Management System). Використовує Web3::HttpClient (HTTPX) — єдиний
  # HTTP-клієнт проєкту з persistent connections та thread-safe sessions.
  #
  # Використання:
  #   Dclimate::VerificationService.new(ews_alert).perform
  class VerificationService
    OUTCOMES = %i[fire_confirmed clear_sky_no_fire obscured_by_clouds].freeze

    # --- dClimate FIRMS API Configuration ---
    # Base URL для dClimate REST API (перевизначається через ENV для staging/test).
    DCLIMATE_BASE_URL = ENV.fetch("DCLIMATE_BASE_URL", "https://api.dclimate.net")

    # Датасет NASA FIRMS (Near Real-Time Global Active Fire) через dClimate.
    # VIIRS (Visible Infrared Imaging Radiometer Suite) на Suomi NPP — роздільна
    # здатність 375 м, проліт кожні ~12 годин, затримка даних ~3 години.
    FIRMS_DATASET = ENV.fetch("DCLIMATE_FIRMS_DATASET", "firms_nrt_global-area_v2")

    # --- Порогові значення інтерпретації супутникових даних ---
    # FRP (Fire Radiative Power) у МВт — основний індикатор активного вогню.
    # ≥ 10 МВт = значна активність вогню (NASA FIRMS standard classification).
    FIRE_FRP_THRESHOLD_MW = 10.0

    # Рівень довіри детекції пожежі (0–100%).
    # ≥ 50% = помірна-висока впевненість, що це реальний вогонь, а не артефакт.
    FIRE_CONFIDENCE_THRESHOLD = 50

    # Хмарність у відсотках, яка робить спостереження ненадійним.
    # > 70% = поверхню не видно, дані неможливо інтерпретувати.
    CLOUD_COVER_THRESHOLD = 70.0

    # 🔭 [ARCH.111] Півширина часового вікна запиту до FIRMS, у добах: питаємо
    # `[дата_алерту − N, дата_алерту + N]`. Константа існує окремо саме тому, що
    # ЦЕ Й Є ВИБІРКА — множина, з якої береться вердикт, і обирає її ВИКЛИКАЧ,
    # а не супутник. FIRMS на будь-яке вікно відповідає чесно; питання лише в
    # тому, чи містить воно подію.
    #
    # ⚠️ Чому симетрична, а не «від дати алерту вперед»: `date` деривується з
    # `@alert.created_at`, тобто з моменту, коли МИ помітили, а не коли ГОРІЛО.
    # Між подією і алертом лежить сон Солдата + батчинг Королеви + черга, тож
    # алерт регулярно народжується вже наступної UTC-доби. Вікно, що починається
    # опівночі дати алерту, тоді стартує ПІСЛЯ пожежі — і `interpret_fire_data`
    # чесно віддає `:clear_sky_no_fire`, тобто `rejected_fraud` + slash-enqueue.
    # Асиметрія ціни однобічна: розширення назад робить хибний фрод-вердикт
    # менш імовірним, звуження — більш; тому мінімальне чесне вікно ≥ періоду
    # прольоту VIIRS (~12 год) плюс NRT-затримка (~3 год), тобто одна доба.
    FIRMS_WINDOW_DAYS = 1

    # --- HTTP Timeouts (суворі для Sidekiq-воркерів) ---
    OPEN_TIMEOUT = 10  # секунд на TCP/TLS handshake
    READ_TIMEOUT = 15  # секунд на відповідь (FIRMS API зазвичай < 5с)

    def initialize(alert)
      @alert = alert
      @satellite_metadata = {}
    end

    def perform
      # [INS.1] Cosmic Eye = FIRMS fire-супутник → верифікує ЛИШЕ пожежу. Не-пожежний перил
      # (сьогодні лише `severe_drought`) НЕ спростовується відсутністю вогню → НІКОЛИ rejected_fraud/trigger_slashing;
      # ескалюємо у незалежний Field Audit (Кат-C, 05_05 §5). Дзеркало SLASH-1 (indeterminate → Field Audit).
      return escalate_non_fire_to_field_audit! unless @alert.alert_type_fire_detected?

      outcome = query_dclimate_api

      case outcome
      when :fire_confirmed
        handle_fire_confirmed
      when :clear_sky_no_fire
        handle_clear_sky_no_fire
      when :obscured_by_clouds
        handle_obscured_by_clouds
      when :coordinates_unknown
        handle_coordinates_unknown
      end
    end

    private

    # ---------------------------------------------------------------
    # 🛰️ HTTP-запит до dClimate API (FIRMS — Fire Radiative Power)
    # ---------------------------------------------------------------
    # Витягує координати алерту (tree → cluster geo_center → [0,0]),
    # формує GET-запит до dClimate FIRMS endpoint із симетричним часовим вікном
    # довкола дати алерту (`FIRMS_WINDOW_DAYS` — там же підстава ширини), парсить
    # JSON-відповідь та інтерпретує супутникові дані через порогові значення
    # FRP/confidence/cloud_cover.
    #
    # При будь-якій мережевій помилці (timeout, HTTP 5xx, DNS failure)
    # повертає :obscured_by_clouds → OrbitalLagError → Sidekiq retry.
    def query_dclimate_api
      coords = @alert.coordinates
      # 🔴 [ARCH.82] Немає координат — немає ЧОГО верифікувати, і це окремий
      # результат, а не хмарність. Доти `EwsAlert#coordinates` віддавав
      # `[0.0, 0.0]`, тож запит ішов у Гвінейську затоку, а його вердикт лягав
      # на алерт як `satellite_status`, тобто як доказ про іншу півкулю.
      #
      # ⚠️ Повертати `:obscured_by_clouds` тут БУЛО Б ХИБНО, і різниця не
      # косметична: та гілка кидає `OrbitalLagError` → Sidekiq-ретрай «до
      # наступного прольоту». Але брак координат чеканням не лікується —
      # алерт їх не набуде. Тому результат ТЕРМІНАЛЬНИЙ: `inconclusive`, стан,
      # що вже означає «потрібен DAO-аудит», без ретраю.
      return :coordinates_unknown if coords.nil?

      lat, lng = coords
      date = @alert.created_at.to_date

      response_data = fetch_firms_data(lat, lng, date)
      @satellite_metadata = response_data["metadata"] || {}

      interpret_fire_data(response_data)
    rescue Web3::HttpClient::RequestError => e
      # Мережеві збої / HTTP 5xx / таймаути → безпечний fallback.
      # Sidekiq ретраїтиме через OrbitalLagError до наступного прольоту.
      Rails.logger.warn "☁️ [Cosmic Eye] dClimate API unavailable for alert ##{@alert.id}: #{e.message}"
      :obscured_by_clouds
    end

    # GET-запит до dClimate FIRMS endpoint з координатами та часовим вікном.
    # Авторизація через Bearer-токен з Rails credentials.
    def fetch_firms_data(lat, lng, date)
      api_key = ENV["DCLIMATE_API_KEY"].presence || Rails.application.credentials.dig(:dclimate, :api_key)

      url = build_firms_url(lat, lng, date)

      headers = { "Accept" => "application/json" }
      headers["Authorization"] = "Bearer #{api_key}" if api_key.present?

      response = Web3::HttpClient.get(url,
        headers: headers,
        open_timeout: OPEN_TIMEOUT,
        read_timeout: READ_TIMEOUT,
        service_name: "dClimate"
      )

      response.parsed_body
    end

    # Формує URL для FIRMS point query.
    # dClimate geo-temporal API: /v4/geo/grid-history/{dataset}?lat=...&lon=...
    # 🔭 [ARCH.111] Вікно СИМЕТРИЧНЕ довкола дати алерту — підстава в
    # `FIRMS_WINDOW_DAYS`. ⛔ Не зводь нижню межу на саму дату алерту: питання до
    # супутника почалося б після півночі тієї доби, коли ми ПОМІТИЛИ, і подія
    # попереднього вечора не входила б у вибірку взагалі. Носій — приклад
    # «питає симетричне вікно довкола дати алерту» (мутаційно перевірений).
    def build_firms_url(lat, lng, date)
      # 🔭 [ARCH.111] One-Home самого вікна: обчислюється РІВНО тут і тут же
      # запамʼятовується, щоб поїхати в `dclimate_ref` разом із вердиктом.
      # Оголошена константа стереже наступного програміста; аудиторові, який
      # тримає в руках `rejected_fraud`, вона не каже нічого — тому вибірка
      # мусить бути В ЗАПИСІ, а не лише в коді.
      window_from = (date - FIRMS_WINDOW_DAYS.days).iso8601
      window_to   = (date + FIRMS_WINDOW_DAYS.days).iso8601
      @queried_window = "#{window_from}..#{window_to}"

      params = URI.encode_www_form(
        latitude: lat,
        longitude: lng,
        start_date: window_from,
        end_date: window_to
      )

      "#{DCLIMATE_BASE_URL}/v4/geo/grid-history/#{FIRMS_DATASET}?#{params}"
    end

    # ---------------------------------------------------------------
    # 🔥 Oracle Logic: інтерпретація супутникових даних FIRMS
    # ---------------------------------------------------------------
    # Мапінг відповіді dClimate → один з трьох outcomes:
    #
    # 1. Немає даних (порожній масив / null) → :obscured_by_clouds
    #    Причина: супутник не пролетів над цим регіоном у вказаний час,
    #    або дані ще не оброблені (затримка NRT ~3 години).
    #
    # 2. Високий cloud_cover (> 70%) → :obscured_by_clouds
    #    Причина: оптичний сенсор VIIRS не може "пробити" хмари.
    #    Sidekiq ретраїтиме до наступного ясного прольоту.
    #
    # 3. Є дані, FRP ≥ 10 MW + confidence ≥ 50% → :fire_confirmed
    #    NASA FIRMS детекція: значна термальна аномалія з високою
    #    впевненістю. Тригерить InsurancePayoutWorker.
    #
    # 4. Є дані, ясне небо, але жодної термальної аномалії → :clear_sky_no_fire
    #    Супутник бачить поверхню, але вогню немає. Можливе шахрайство.
    #    Тригерить BurnCarbonTokensWorker (Slashing Protocol).
    def interpret_fire_data(response_data)
      entries = extract_entries(response_data)

      # Немає даних → супутник не покрив цей регіон або NRT-затримка
      return :obscured_by_clouds if entries.empty?

      # Перевірка хмарності — оптичний сенсор не може верифікувати через хмари
      cloud_cover = extract_cloud_cover(response_data)
      return :obscured_by_clouds if cloud_cover && cloud_cover > CLOUD_COVER_THRESHOLD

      # Шукаємо активний вогонь серед FIRMS-детекцій
      fire_detected = entries.any? do |entry|
        frp = entry["frp"].to_f
        confidence = parse_confidence(entry["confidence"])
        frp >= FIRE_FRP_THRESHOLD_MW && confidence >= FIRE_CONFIDENCE_THRESHOLD
      end

      fire_detected ? :fire_confirmed : :clear_sky_no_fire
    end

    # Витягує масив детекцій з відповіді dClimate.
    # Підтримує два формати: {"data": [...]} та GeoJSON {"features": [...]}.
    def extract_entries(response_data)
      data = response_data["data"]
      return data if data.is_a?(Array)

      features = response_data["features"]
      return features.filter_map { |f| f["properties"] } if features.is_a?(Array)

      []
    end

    # Витягує cloud_cover з метаданих відповіді.
    # dClimate може повертати його у metadata або як поле верхнього рівня.
    def extract_cloud_cover(response_data)
      cc = response_data.dig("metadata", "cloud_cover") || response_data["cloud_cover"]
      cc&.to_f
    end

    # Парсить confidence з FIRMS — може бути числом (0–100) або рядком ("high"/"nominal"/"low").
    # VIIRS використовує рядкові значення, MODIS — числові.
    # Невідомі значення → 0 (безпечний fallback: краще пропустити, ніж хибно підтвердити пожежу).
    def parse_confidence(value)
      case value
      when Numeric then value
      when "high" then 90
      when "nominal" then 50
      when "low" then 20
      else
        Rails.logger.warn "⚠️ [Cosmic Eye] Unexpected FIRMS confidence format: #{value.inspect}" unless value.nil?
        value.to_i
      end
    end

    # Супутник підтвердив пожежу/посуху → виплата страховки
    def handle_fire_confirmed
      @alert.update!(
        satellite_status: :verified,
        dclimate_ref: generate_dclimate_ref
      )

      Rails.logger.info "🛰️ [Cosmic Eye] Алерт ##{@alert.id} підтверджено супутником. Ініціація виплати."

      # [ARCH.53] update!-first тут СВІДОМО (на відміну від handle_clear_sky_no_fire slash-reorder):
      # загублений payout-enqueue відновлює InsurancePayoutRecoveryWorker (sweep :triggered). Slashing
      # такої крони не має → там reorder. Asymmetry навмисна, не баг.
      trigger_insurance_payout
    end

    # Супутник бачить ясне небо без пожежі → шахрайство → slashing
    def handle_clear_sky_no_fire
      Rails.logger.warn "🚨 [Cosmic Eye] Алерт ##{@alert.id} відхилено — ясне небо. Slashing Protocol."

      # [ARCH.53/B2] Slash enqueue ПЕРЕД update!: інакше краш між update!(:rejected_fraud)
      # і trigger_slashing лишав би slash застрендженим — worker-guard `satellite_unverified?`
      # на retry робить early-return, burn ніколи не enqueue (recovery-крони нема). Slash
      # першим → guard лишається «unverified» доки update! не закомітиться → retry переграє
      # enqueue ідемпотентно (BurnCarbonTokensWorker skip :breached); вичерпані 15 retry →
      # :inconclusive → DAO-аудит (sidekiq_retries_exhausted), не тиха втрата.
      trigger_slashing

      @alert.update!(
        satellite_status: :rejected_fraud,
        dclimate_ref: generate_dclimate_ref
      )
    end

    # Хмарність/кронопокрив → ретрай через Sidekiq (48h orbital window), АЛЕ:
    # [E.41] критичний fire-алерт НЕ може чекати повні 48h retry — це life-safety
    # (пожежа спалить ліс раніше). ⛔ Дрон-bounty як Резервний Оракул — won't-do
    # (E.20): платити свідкові за зміст його ж свідчення. Тому критичний obscured
    # fire → негайний Field Audit (дзеркало escalate_non_fire_to_field_audit! / INS.1:
    # :inconclusive = HOLD, людський/DAO-вердикт, fail-safe — НЕ авто-payout/slash).
    # Non-critical obscured → retry (48h вікно прийнятне; exhaustion → worker
    # sidekiq_retries_exhausted теж кладе :inconclusive).
    def handle_obscured_by_clouds
      return escalate_obscured_critical_fire! if @alert.severity_critical?

      Rails.logger.info "☁️ [Cosmic Eye] Алерт ##{@alert.id} — хмарність/кронопокрив. Очікуємо наступний проліт."

      raise Dclimate::OrbitalLagError,
            "Satellite pass obscured by clouds/canopy for alert ##{@alert.id}. Retrying on next orbit."
    end

    # 🔴 [ARCH.82] Координат немає — верифікувати НЕМА ЧОГО, і це термінально.
    #
    # Відмінність від хмарності несуча: та кидає `OrbitalLagError` і чекає
    # наступного прольоту, бо небо проясниться. Координати не «проясняться» —
    # алерт їх не набуде, тож ретрай тут був би вічним. Пишемо `inconclusive`
    # (стан, який уже означає «потрібен DAO-аудит») і виходимо тихо.
    #
    # ⚠️ Дзеркалимо `escalate_obscured_critical_fire!` для критичних: людський
    # вердикт потрібен тим самим шляхом, лише привід інший — не затемнення, а
    # відсутність координати. Життєва безпека не чекає ні орбіти, ні геоданих.
    def handle_coordinates_unknown
      Rails.logger.warn(
        "🛰️ [Cosmic Eye] Алерт ##{@alert.id} — КООРДИНАТ НЕМА (ні дерева з lat/lng, " \
        "ні geo_center кластера). Супутникова верифікація неможлива; ретраю не буде."
      )

      return escalate_obscured_critical_fire! if @alert.severity_critical?

      @alert.update!(satellite_status: :inconclusive)
    end

    # [E.41] Критичний fire-алерт затемнений → негайний Field Audit замість 48h orbital
    # retry. :inconclusive HOLD-ить InsurancePayoutWorker (людський вердикт), тривога вже
    # пішла окремо (edge panic-TX + backend alert, 04_02 §11), тож life-safety не чекає орбіти.
    def escalate_obscured_critical_fire!
      # [I18N.1] Ключ замість укр. прози: у БД їде ідентифікатор події, фраза —
      # локаллю глядача в момент показу; час — поле самого запису.
      @alert.log_resolution(key: "obscured_critical_fire")
      @alert.update!(satellite_status: :inconclusive)
      escalate_to_field_audit!(message_key: "obscured_critical_fire")

      Rails.logger.warn "🛰️ [Cosmic Eye] Алерт ##{@alert.id} — критичний obscured fire → негайний Field Audit " \
                        "(Кат-C, 05_05 §5), без 48h orbital retry."
    end

    # [INS.1] Не-пожежний перил (сьогодні лише `severe_drought`): FIRMS fire-супутник не може його ні підтвердити,
    # ні спростувати → ескалюємо у незалежний Field Audit (Кат-C DAO peer-review, 05_05 §5), а НЕ
    # rejected_fraud (це таврувало б жертву force-majeure фродом і слало у trigger_slashing). Вердикт
    # :inconclusive — наявний стан «потрібен людський/DAO-аудит», на якому InsurancePayoutWorker уже
    # HOLD-ить, а повістку для людини несе окремий `EwsAlert(:field_audit)` нижче.
    # ⛔ Дрон-bounty як фізичний fallback — won't-do (E.20); реальний drought-оракул
    # = North-Star (S3.2 / ДСНС-API UNI.12). Без FIRMS-запиту (нерелевантний).
    def escalate_non_fire_to_field_audit!
      # [I18N.1] Ключ замість укр. прози. Тип перила у фразу НЕ інтерпольовано
      # свідомо: він видно з самого алерту, а сирий enum у перекладеному реченні —
      # окремий оголошений клас (⚖️ у `00_07` I18N.1).
      @alert.log_resolution(key: "non_fire_peril")
      @alert.update!(satellite_status: :inconclusive)
      escalate_to_field_audit!(message_key: "non_fire_peril")

      Rails.logger.info "🛰️ [Cosmic Eye] Алерт ##{@alert.id} (#{@alert.alert_type}) — не-пожежний перил, " \
                        "fire-супутник не адьюдикує → Field Audit (Кат-C, 05_05 §5)."
    end

    # Спільна нога обох ескалацій вище: `:inconclusive` — це стан ГРОШЕЙ (він HOLD-ить
    # `InsurancePayoutWorker`), і єдиний його читач саме там. Повістку для ЛЮДИНИ несе
    # окремий `EwsAlert(:field_audit)` — без нього «ескалація» зупиняла виплату й нікого
    # не кликала.
    #
    # ⛔ **Cluster-scoped СВІДОМО, `tree:` не передавати.** `TreeStalenessSweepWorker`
    # оголошує стелю: всі per-tree `field_audit` походять звідти, тож його
    # `resolve_returned_trees` авто-закриє будь-яку per-tree ескалацію, щойно дерево
    # вийде в ефір. Для пожежі це означало б «вузол відповів по LoRa» ≡ «ліс не горить».
    # Дискримінатора джерела не існує — доки його немає, tree-гілка тут заборонена.
    #
    # Гард на `cluster` — не косметика: `belongs_to :cluster, optional: true`, а
    # cluster-гілка дедупу ходить у `cluster.ews_alerts` (той самий ідіом, що
    # `trigger_insurance_payout`/`trigger_slashing` нижче).
    def escalate_to_field_audit!(message_key:)
      unless @alert.cluster
        Rails.logger.warn "🛰️ [Cosmic Eye] Алерт ##{@alert.id} — Field-Audit не створено: алерт без кластера."
        return
      end

      EwsAlert.escalate_field_audit!(
        cluster: @alert.cluster,
        message_key: message_key,
        message_params: { alert_id: @alert.id }
      )
    end

    # Генерує dclimate_ref з метаданими супутника для аудит-трейлу.
    # Формат: "dclimate:firms:{satellite}:{timestamp}:{nonce}"
    # 🔭 [ARCH.111] Останній сегмент — ВИБІРКА, з якої виведено вердикт: часове
    # вікно запиту до FIRMS. Він тут не для повноти, а тому що без нього
    # `satellite_status` є твердженням без множини: аудитор бачить «ясне небо,
    # вогню немає» й не може спитати «за яку добу питали». `UNKNOWN` тут чесний
    # стан — шляхи без запиту (немає координат) вікна не мають за конструкцією.
    def generate_dclimate_ref
      timestamp = Time.current.utc.strftime("%Y%m%dT%H%M%SZ")
      satellite = @satellite_metadata&.dig("satellite") || "UNKNOWN"
      window = @queried_window || "UNKNOWN"
      "dclimate:firms:#{satellite}:#{timestamp}:#{SecureRandom.hex(8)}:#{window}"
    end

    # Знаходимо активні страховки кластера та тригеримо виплату
    def trigger_insurance_payout
      return unless @alert.cluster

      ParametricInsurance.where(cluster: @alert.cluster, status: :triggered).find_each do |insurance|
        InsurancePayoutWorker.perform_async(insurance.id)
      end
    end

    # Ініціюємо slashing через BurnCarbonTokensWorker
    def trigger_slashing
      return unless @alert.cluster

      organization = @alert.cluster.organization
      return unless organization

      NaasContract.where(cluster: @alert.cluster).where.not(status: :breached).find_each do |contract|
        BurnCarbonTokensWorker.perform_async(organization.id, contract.id, @alert.tree_id)
      end
    end
  end
end
