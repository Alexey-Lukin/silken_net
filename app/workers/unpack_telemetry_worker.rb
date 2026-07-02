# frozen_string_literal: true

require "base64"
require "openssl"

class UnpackTelemetryWorker
  include Sidekiq::Job
  # [SIDEKIQ PRO EXPIRES_IN]: Якщо база даних впала або черга переповнена,
  # телеметрія старша за 5 хвилин стає «застарілою» і лише витрачає CPU.
  # Sidekiq Pro автоматично відкидає такі джоби при dequeue.
  # У OSS-редакції (поточній) опція інертна — активується лише з Sidekiq Pro.
  sidekiq_options queue: "uplink", retry: 3, expires_in: 5.minutes

  # Розмір IV для AES-256-CBC (один AES-блок = 16 байт)
  AES_IV_SIZE = 16

  # === [L1 QATT] Trust-origin L1 — Queen-attestation батч-конверта ===
  # Канон: 05_02 «Trust-origin ladder» (рунг L1) + 03_05 §2.2 (wire);
  # firmware-дзеркало розкладки — firmware/common/queen_attest.h.
  # Підписаний payload: [ver:1][unix_ts:4 BE][flush_seq:4 BE][IV:16][ct][sig:64]
  # Encrypt-then-sign: підпис верифікується ДО decrypt (без padding-оракулів).
  # Повідомлення = DOMAIN_TAG ‖ uid_len ‖ uid ‖ <payload без хвостового sig> —
  # UID з CoAP URI вшито у підпис (батч не сплайснути між шлюзами).
  QATT_SIG_LEN    = 64
  QATT_HEADER_LEN = 9
  QATT_VERSION_1  = 0x01
  QATT_DOMAIN_TAG = "SLKN-QATT1".b.freeze
  # Residue-дискримінатор: legacy [IV][ct] ≡ 0 (mod 16), підписаний ≡ 9 —
  # довжини ніколи не перетинаються, magic-вгадування проти random-IV не треба.
  QATT_RESIDUE    = (QATT_HEADER_LEN + AES_IV_SIZE + QATT_SIG_LEN) % 16
  QATT_MIN_SIZE   = QATT_HEADER_LEN + AES_IV_SIZE + 16 + QATT_SIG_LEN
  # Replay-вікно: дубль підпису (SHA256-nonce, патерн M2M/S6.1) ріжеться
  # в межах TTL; replay ПІСЛЯ вікна — задокументований residual (03_05 §2.2),
  # строго кращий за «replay будь-коли» на L0.
  QATT_NONCE_TTL  = 30.days
  # Finalize-маркер двофазного nonce: батч розпаковано, будь-який повтор
  # (свій чи чужий) = replay. Колізія з owner-token структурно неможлива:
  # jid = 24 hex-символи, random-token = 16.
  QATT_NONCE_DONE = "done"

  # Сигнатура perform: encoded_payload, sender_ip, gateway_uid (необов'язково).
  # gateway_uid — незашифрований UID з CoAP URI-Path (/telemetry/batch/<UID>).
  # Дозволяє коректно ідентифікувати шлюзи за NAT / динамічним Starlink IP.
  def perform(encoded_payload, sender_ip, gateway_uid = nil)
    # Sentry context: tag with gateway UID for error correlation
    Sentry.set_tags(gateway_uid: gateway_uid || "unknown")

    # 1. ДЕКОДУВАННЯ (Extraction)
    # Отримуємо сирі байти, що прийшли через CoAP/UDP
    binary_payload = Base64.strict_decode64(encoded_payload)

    # 2. ІДЕНТИФІКАЦІЯ ШЛЮЗУ (The Queen Node)
    # Пріоритет: UID з заголовка пакета (стабільний) → IP (може змінитись після NAT)
    gateway = gateway_uid.present? ? Gateway.find_by(uid: gateway_uid.to_s.strip.upcase) : nil
    gateway ||= Gateway.find_by(ip_address: sender_ip)

    unless gateway
      Rails.logger.warn "⚠️ [Uplink] Невідоме джерело: UID=#{gateway_uid.inspect}, IP=#{sender_ip}. Скидання з'єднання."
      SilkenNet::Metrics::COAP_PACKETS_RECEIVED_TOTAL.increment(labels: { status: "unknown_device" })
      return
    end

    # 2.1 ЖИВИЙ ПОТІК У МАТРИЦЮ (ActionCable — raw hex stream)
    # [BUG FIX]: перенесено після верифікації шлюзу — невідомі IP не повинні заповнювати UI.
    broadcast_raw_hex(binary_payload, sender_ip)

    # Оновлюємо поточну IP-адресу (важливо для динамічних Starlink/LTE модемів)
    gateway.mark_seen!(new_ip: sender_ip)

    # 3. ДЕШИФРУВАННЯ БАТЧА (Dual-Key Logic)
    # Шукаємо ключі ідентичності для цієї Королеви
    key_record = HardwareKey.find_by(device_uid: gateway.uid)

    unless key_record
      Rails.logger.error "🚨 [Security] Відсутній HardwareKey для Королеви #{gateway.uid}!"
      return
    end

    # [L1 QATT] Підписаний конверт детектиться за residue довжини й
    # верифікується ДО decrypt. :reject = drop без retry (підпис не «одужає»);
    # :unverified = конверт є, але pubkey не зареєстровано → обробка як L0
    # (суворість нічого не дає, поки L0 приймається беззастережно) + метрика.
    gateway_attested = false
    if qatt_envelope?(binary_payload)
      verdict = verify_qatt_envelope(binary_payload, gateway, key_record)
      if verdict == :reject
        SilkenNet::Metrics::COAP_PACKETS_RECEIVED_TOTAL.increment(labels: { status: "attest_rejected" })
        return
      end

      gateway_attested = (verdict == :attested)
      binary_payload = binary_payload.byteslice(
        QATT_HEADER_LEN, binary_payload.bytesize - QATT_HEADER_LEN - QATT_SIG_LEN
      )
    end

    decrypted_data = attempt_decryption(binary_payload, key_record)

    unless decrypted_data
      Rails.logger.error "🛑 [Security] Критична помилка дешифрування від #{gateway.uid}. Пакет корумпований або ключ невірний."
      SilkenNet::Metrics::COAP_PACKETS_RECEIVED_TOTAL.increment(labels: { status: "decrypt_error" })
      return
    end

    # ⚡ [СИНХРОНІЗАЦІЯ]: Трансляція розшифрованої істини в Матрицю (UI)
    broadcast_to_matrix(gateway, decrypted_data)

    # 4. ПЕРЕДАЧА В СЕРВІС РОЗПАКОВКИ
    # Конвеєр: [DID:4][RSSI:1][Payload:16] x N
    # [L1 QATT] gateway_attested протягується до кожного TelemetryLog-рядка.
    TelemetryUnpackerService.call(decrypted_data, gateway.id, gateway_attested: gateway_attested)

    # [L1 QATT] Фаза 2: батч розпаковано — nonce стає незворотним ("done").
    finalize_qatt_nonce! if @qatt_nonce_digest

    # [S2.4] Track successful CoAP packet processing for Prometheus
    SilkenNet::Metrics::COAP_PACKETS_RECEIVED_TOTAL.increment(labels: { status: "success" })

  rescue ArgumentError => e
    Rails.logger.warn "🛑 [Uplink] Корупція Base64 від #{sender_ip}: #{e.message}"
  rescue StandardError => e
    # [ВИПРАВЛЕНО: Broad Rescue Trace]: Додано перші 10 рядків трейсу для швидкої діагностики у продакшені
    backtrace_summary = e.backtrace.first(10).join("\n")
    Rails.logger.error "🚨 [Uplink Critical] Збій обробки батча: #{e.message}\n#{backtrace_summary}"

    # Ми прокидаємо помилку далі, щоб Sidekiq міг зробити retry
    raise e
  end

  private

  # [L1 QATT] Чи payload — підписаний конверт? Residue довжини — детерміністичний
  # дискримінатор (legacy ≡ 0 mod 16; підписаний ≡ QATT_RESIDUE).
  def qatt_envelope?(payload)
    payload.bytesize >= QATT_MIN_SIZE && (payload.bytesize % 16) == QATT_RESIDUE
  end

  # [L1 QATT] Верифікація Ed25519-підпису батча проти зареєстрованого при
  # provisioning pubkey шлюзу (HardwareKey.ed25519_public_key_hex — той самий
  # ключ, що в M2M-auth). Повертає :attested / :unverified (обробити як L0) /
  # :reject (drop). ts/seq з header'а — observability (Queen без RTC: ts=0
  # легітимний «ще не синхронізовано», 03_02 §5а) — НЕ основний anti-replay.
  def verify_qatt_envelope(payload, gateway, key_record)
    unless key_record.ed25519_public_key_hex.present?
      Rails.logger.warn "⚠️ [L1 QATT] #{gateway.uid}: підписаний батч, але pubkey не зареєстровано — обробка як L0."
      SilkenNet::Metrics::COAP_PACKETS_RECEIVED_TOTAL.increment(labels: { status: "attest_no_pubkey" })
      return :unverified
    end

    version = payload.getbyte(0)
    unless version == QATT_VERSION_1
      # Невідома версія конверта = невідома розкладка → чесний drop, гучна
      # метрика. Backend деплоїться ПЕРЕД firmware (Kamal vs OTA/bench).
      Rails.logger.error "🚨 [L1 QATT] #{gateway.uid}: невідома версія конверта 0x#{version.to_s(16)}."
      SilkenNet::Metrics::COAP_PACKETS_RECEIVED_TOTAL.increment(labels: { status: "attest_unknown_version" })
      return :reject
    end

    signature = payload.byteslice(-QATT_SIG_LEN, QATT_SIG_LEN)
    body      = payload.byteslice(0, payload.bytesize - QATT_SIG_LEN)
    uid       = gateway.uid.to_s
    message   = QATT_DOMAIN_TAG + [ uid.bytesize ].pack("C") + uid.b + body

    valid = Ed25519Crypto::SigningService.verify(
      key_record.ed25519_public_key_hex, signature.unpack1("H*"), message
    )

    unless valid
      # Невалідний підпис при зареєстрованому ключі = підробка/пошкодження —
      # подія безпеки, Grafana-алерт на цей лейбл.
      Rails.logger.error "🚨 [L1 QATT] #{gateway.uid}: НЕВАЛІДНИЙ Ed25519-підпис батча (можлива підробка)."
      SilkenNet::Metrics::COAP_PACKETS_RECEIVED_TOTAL.increment(labels: { status: "attest_bad_signature" })
      return :reject
    end

    case claim_qatt_nonce(signature, gateway)
    when :replay
      return :reject
    when :resumed
      Rails.logger.info "🔁 [L1 QATT] #{gateway.uid}: crash-retry власного батча (#{qatt_owner_token}) — resume без спалення nonce."
    end

    _ver, unix_ts, flush_seq = payload.unpack("CNN")
    gateway.update_column(:last_attested_at, Time.current)
    Rails.logger.info "🛡️ [L1 QATT] #{gateway.uid}: батч атестовано (ts=#{unix_ts}, seq=#{flush_seq})."
    :attested
  rescue Ed25519Crypto::SigningService::SigningError => e
    # Малформлений ЗБЕРЕЖЕНИЙ pubkey (наша misprovisioning-помилка, не атака:
    # sig з дроту завжди рівно 64 байти) → не караємо телеметрію, L0 + алерт.
    Rails.logger.error "🚨 [L1 QATT] #{gateway.uid}: битий збережений pubkey: #{e.message}"
    SilkenNet::Metrics::COAP_PACKETS_RECEIVED_TOTAL.increment(labels: { status: "attest_bad_stored_key" })
    :unverified
  end

  # [L1 QATT] Anti-replay: SHA256(sig) як природний nonce (підпис детермінований
  # над унікальним повідомленням — HRNG IV свіжий щофлешу). Двофазний
  # інтент-маркер (патерн ARCH.45): claim ДО unpack тримає owner-token,
  # finalize ПІСЛЯ успішного unpack перезаписує на "done" — інакше краш
  # TelemetryUnpackerService + Sidekiq-retry спалював би nonce і губив
  # атестований батч назавжди (Королева кеш уже звільнила по ACK 2.04).
  #
  # Фаза 1 (claim): Redis SET NX (атомарно, патерн M2M/S6.1) → Solid-Cache
  # fallback при Redis-аутеджі (свідоме TOCTOU-вікно у degraded mode).
  # Ключ зайнятий → GET: наш token = crash-retry цього ж джоба (:resumed);
  # будь-що інше ("done" / чужий jid / легасі "1") = :replay.
  def claim_qatt_nonce(signature, gateway)
    digest = Digest::SHA256.hexdigest(signature)
    @qatt_nonce_digest = digest

    status =
      begin
        redis     = Kredis.redis(config: :shared)
        nonce_key = Kredis.namespaced_key("qatt_nonce:#{digest}")
        if redis.set(nonce_key, qatt_owner_token, nx: true, ex: QATT_NONCE_TTL.to_i)
          :acquired
        else
          redis.get(nonce_key) == qatt_owner_token ? :resumed : :replay
        end
      rescue Redis::BaseConnectionError, RedisClient::ConnectionError => e
        SilkenNet::Metrics::QATT_NONCE_FALLBACK_TOTAL.increment
        Rails.logger.warn "⚠️ [L1 QATT] Redis недоступний, nonce через Solid Cache: #{e.message}"
        claim_qatt_nonce_fallback(digest)
      end

    if status == :replay
      Rails.logger.warn "⚠️ [L1 QATT] #{gateway.uid}: REPLAY підписаного батча заблоковано."
      SilkenNet::Metrics::COAP_PACKETS_RECEIVED_TOTAL.increment(labels: { status: "attest_replay" })
    end

    status
  end

  # Дзеркало claim у degraded mode (read→compare→write не атомарні — як і було).
  def claim_qatt_nonce_fallback(digest)
    fallback_key = "qatt_nonce_fallback:#{digest}"
    existing = Rails.cache.read(fallback_key)
    return :resumed if existing == qatt_owner_token
    return :replay unless existing.nil?

    Rails.cache.write(fallback_key, qatt_owner_token, expires_in: QATT_NONCE_TTL)
    :acquired
  end

  # [L1 QATT] Фаза 2 (finalize): після успішного unpack і чужі replay, і
  # власний post-success retry ріжуться однаково. Безумовний SET безпечний:
  # NX у claim гарантує, що ключ тримає саме наш token. Rescue обов'язковий —
  # без нього Redis-аутедж ПІСЛЯ успішного unpack ішов би в retry → resume →
  # подвійний unpack (over-credit growth_points).
  def finalize_qatt_nonce!
    nonce_key = Kredis.namespaced_key("qatt_nonce:#{@qatt_nonce_digest}")
    Kredis.redis(config: :shared).set(nonce_key, QATT_NONCE_DONE, ex: QATT_NONCE_TTL.to_i)
  rescue Redis::BaseConnectionError, RedisClient::ConnectionError => e
    Rails.logger.warn "⚠️ [L1 QATT] Redis недоступний на finalize, done-маркер у Solid Cache: #{e.message}"
    Rails.cache.write("qatt_nonce_fallback:#{@qatt_nonce_digest}", QATT_NONCE_DONE, expires_in: QATT_NONCE_TTL)
  end

  # Owner-token: jid стабільний крізь Sidekiq-retry (retry re-push'ить той
  # самий job hash) → retry впізнає власний claim. Прямий виклик
  # (.new.perform — консоль, спеки) отримує випадковий токен: resume
  # неможливий, лише claim/reject (fail-closed).
  def qatt_owner_token
    @qatt_owner_token ||= jid.presence || SecureRandom.hex(8)
  end

  # Логіка "М'якої Ротації": пробуємо новий ключ, потім старий
  def attempt_decryption(payload, key_record)
    # Спроба 1: Основний (новий) ключ
    result = decrypt_aes(payload, key_record.cached_binary_key)

    if result
      # Якщо новий ключ спрацював — підтверджуємо успішну ротацію (закриваємо Grace Period)
      key_record.clear_grace_period!
      return result
    end

    # Спроба 2: Попередній ключ (якщо він є у банку пам'яті)
    if key_record.binary_previous_key
      result = decrypt_aes(payload, key_record.binary_previous_key)
      if result
        Rails.logger.info "🔄 [KeyRotation] Пристрій #{key_record.device_uid} все ще використовує старий ключ."
        return result
      end
    end

    nil
  end

  def decrypt_aes(payload, key)
    # Формат пакета від Королеви: [IV:16][Зашифрований батч: N*16 байт]
    # де батч вирівняний до 16 байт нульовим padding на стороні прошивки.
    #
    # AES-256-CBC усуває ECB-вразливість: однакові блоки даних
    # (характерно для телеметрії) тепер дають різний шифротекст завдяки IV.
    return nil if payload.bytesize < AES_IV_SIZE * 2

    iv         = payload.byteslice(0, AES_IV_SIZE)
    ciphertext = payload.byteslice(AES_IV_SIZE..)

    # Шифротекст має бути вирівняний до розміру AES-блоку
    return nil unless (ciphertext.bytesize % AES_IV_SIZE).zero?

    cipher = OpenSSL::Cipher.new("aes-256-cbc")
    cipher.decrypt
    cipher.key     = key
    cipher.iv      = iv
    # Прошивка використовує нульовий padding (не PKCS7).
    # TelemetryUnpackerService сам ігнорує неповні 21-байтні чанки наприкінці буфера.
    cipher.padding = 0

    cipher.update(ciphertext) + cipher.final
  rescue OpenSSL::Cipher::CipherError
    nil
  rescue StandardError
    nil
  end

  def broadcast_to_matrix(gateway, binary_data)
    hex_payload = binary_data.unpack1("H*").upcase

    # Turbo Stream трансляція для "живого" дашборду телеметрії
    Turbo::StreamsChannel.broadcast_prepend_to(
      "telemetry_stream",
      target: "telemetry_feed",
      html: Telemetry::LogEntry.new(
        gateway: gateway,
        hex_payload: hex_payload,
        timestamp: Time.current
      ).call
    )

    Turbo::StreamsChannel.broadcast_remove_to("telemetry_stream", target: "feed_placeholder")
  end

  def broadcast_raw_hex(binary_payload, sender_ip)
    ActionCable.server.broadcast("telemetry_live_stream", {
      hex: binary_payload.unpack1("H*").scan(/../).join(" "),
      ip: sender_ip,
      size: binary_payload.bytesize,
      at: Time.current.strftime("%H:%M:%S.%L")
    })
  end
end
