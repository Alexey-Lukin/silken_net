# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# Хелпери для request-специв на `IdempotentRequest`-контур (`actuators#execute`,
# `maintenance_records#create`). Три речі, які інакше розповзаються літералом по
# двох файлах і розходяться з реалізацією поодинці.
module IdempotencyHelper
  # Заголовки з ключем. Явний `key:` — коли приклад доводить ПОВТОР (той самий
  # ключ двічі); за замовчуванням кожен виклик дає новий, тобто «різні запити».
  def idempotent(headers, key: SecureRandom.uuid)
    headers.merge("Idempotency-Key" => key)
  end

  # 🔴 У тест-середовищі `rack.response_finished` лише НАКОПИЧУЄТЬСЯ — Rails його
  # не викликає. Смикаємо руками з РЕАЛЬНОЮ Rack-арністю `(env, status, headers,
  # error)`, тобто рівно так, як це робить Puma після флашу: вужчий виклик кинув
  # би `ArgumentError`, і приклад «довів» би запис у кеш, якого не сталося.
  #
  # Повертає сам масив колбеків — щоб приклад, який пінить НАЯВНІСТЬ механізму,
  # міг стверджувати про нього тим самим викликом, яким його й запускає
  # (інакше ліхтар і дія розʼїжджаються на два рядки й перший тихо зникає).
  def flush_response_finished!
    callbacks = Array(request.env["rack.response_finished"])
    callbacks.each { |cb| cb.call(request.env, response.status, response.headers, nil) }
    callbacks
  end

  # Дзеркало `IdempotentRequest#idempotency_cache_key`. Тримається окремо
  # НАВМИСНО: якщо схема ключа зміниться, приклад мусить почервоніти, а не
  # мовчки піти за реалізацією.
  def idempotency_cache_key_for(scope, key)
    "idempotency:#{scope}:#{Digest::SHA256.hexdigest(key)}"
  end
end

RSpec.configure do |config|
  config.include IdempotencyHelper, type: :request
end
