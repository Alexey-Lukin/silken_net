# frozen_string_literal: true

class AlertDispatchService
  # Фізичні пороги
  FIRE_TEMP_THRESHOLD_C = 60
  SEISMIC_ACOUSTIC_THRESHOLD = 200 # Використовуємо акустичне насичення мікрофона (0-255) як маркер ударної хвилі
  PEST_ACOUSTIC_THRESHOLD = 50

  def self.analyze_and_trigger!(telemetry_log)
    tree = telemetry_log.tree
    cluster = tree.cluster

    # 1. ВАНДАЛІЗМ (Tamper Detection - Найвищий пріоритет)
    # Згідно з нашим протоколом, якщо status_code == 3 (зарезервовано) або напруга впала до 0 при живому пінг-у
    if telemetry_log.status_code == 3 || telemetry_log.vcap_voltage < 100
      create_and_dispatch_alert!(
        cluster: cluster,
        tree: tree,
        severity: :critical,
        alert_type: :vandalism_breach,
        message: "КРИТИЧНО: Зафіксовано відкриття титанового корпусу S-NET або втрату живлення! Можливе викрадення. Дерево DID: #{tree.did}"
      )
      return # Зупиняємо подальший аналіз, бо датчики можуть брехати
    end

    # 2. ПОЖЕЖА або РОБОТА ПИЛКОЮ (status_code == 2 від TinyML)
    if telemetry_log.temperature >= FIRE_TEMP_THRESHOLD_C || telemetry_log.status_code == 2
      create_and_dispatch_alert!(
        cluster: cluster,
        tree: tree,
        severity: :critical,
        alert_type: :fire_detected,
        message: "КАТАСТРОФА: Термістор фіксує #{telemetry_log.temperature}°C або TinyML виявив бензопилу (Аномалія). Ризик пожежі/вирубки!"
      )
    end

    # 3. ПОСУХА (status_code == 1)
    if telemetry_log.status_code == 1
      create_and_dispatch_alert!(
        cluster: cluster,
        tree: tree,
        severity: :high,
        alert_type: :severe_drought,
        message: "ПОПЕРЕДЖЕННЯ: Дерево у стані глибокого гідрологічного стресу. Атрактор Лоренца вийшов за межі гомеостазу."
      )
    end

    # 4. ЗЕМЛЕТРУС (Сейсмічний метаматеріал)
    # Оскільки п'єзо безпосередньо будить процесор, ударна хвиля (землетрус) дасть максимальне значення акустики (255)
    if telemetry_log.acoustic >= SEISMIC_ACOUSTIC_THRESHOLD
      create_and_dispatch_alert!(
        cluster: cluster,
        tree: tree,
        severity: :critical,
        alert_type: :seismic_anomaly,
        message: "СЕЙСМІКА: Аномальний акустично-п'єзо резонанс (Рівень: #{telemetry_log.acoustic}/255). Можливий тектонічний зсув."
      )
    end

    # 5. ШКІДНИКИ (Короїд - Edge AI)
    # Якщо нейромережа не дала "Аномалію 2", але є стрес (1) і підвищений акустичний шум (хрускіт личинок)
    if telemetry_log.acoustic > PEST_ACOUSTIC_THRESHOLD && telemetry_log.acoustic < SEISMIC_ACOUSTIC_THRESHOLD && telemetry_log.status_code == 1
      create_and_dispatch_alert!(
        cluster: cluster,
        tree: tree,
        severity: :high,
        alert_type: :insect_epidemic,
        message: "БІО-ЗАГРОЗА: Периферійний ШІ зафіксував акустичну емісію, характерну для личинок короїда."
      )
    end
  end

  private_class_method def self.create_and_dispatch_alert!(cluster:, tree:, severity:, alert_type:, message:)
    # Захист від спаму: не створюємо новий алерт, якщо такий самий вже активний останні 5 хвилин
    recent_alert = EwsAlert.where(tree: tree, alert_type: alert_type)
                           .where("created_at > ?", 5.minutes.ago)
                           .exists?
    return if recent_alert

    # 1. Записуємо загрозу в базу даних
    alert = EwsAlert.create!(
      cluster: cluster,
      tree: tree,
      severity: severity,
      alert_type: alert_type,
      message: message
    )

    Rails.logger.warn "🚨 [ALERT DISPATCHER] Згенеровано тривогу: #{alert_type} для Дерева #{tree.did}"

    # 2. ЗАМКНЕНИЙ ЦИКЛ: Миттєво передаємо тривогу в Центр Прийняття Рішень
    EmergencyResponseService.call(alert)

    # 3. Сповіщення людей
    notify_stakeholders(alert)
  end

  private_class_method def self.notify_stakeholders(alert)
    AlertNotificationWorker.perform_async(alert.id)
  end
end
