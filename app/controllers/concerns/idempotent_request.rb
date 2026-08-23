# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# Один дім протоколу `Idempotency-Key` для запитів, повтор яких коштує грошей або
# доказу. Механізм ідентичний на всіх майданчиках, різняться лише ТРИ параметри —
# скоуп ключа, текст відмови й статус повтору, — тож вони й лишаються на місці
# виклику, а сам протокол не має другої копії, здатної тихо розійтись.
#
# 🔴 Чому запис у кеш іде ПІСЛЯ віддачі відповіді (`rack.response_finished`,
# Puma 7+): це знімає 1-2 мс із критичного шляху, але головне — колбек
# спрацьовує й тоді, коли клієнт відповіді не отримав. А саме цей сценарій
# протокол і стереже: сервер запит виконав, відповідь загубилась у дорозі,
# клієнт повторює.
#
# ⛔ Лямбда мусить приймати РІВНО чотири аргументи Rack SPEC — `(env, status,
# headers, error)`. Вужча кидає `ArgumentError`, який Puma ковтає в debug-лог:
# запис у кеш тихо не відбувається, і повтор створює дубль. Саме тому вона
# написана тут один раз, а не копіюється по контролерах.
module IdempotentRequest
  extend ActiveSupport::Concern

  # Доба — стільки живе вікно повтору offline-черги; довше не потрібно, бо
  # флаш прив'язаний до відновлення зв'язку, а не до календаря.
  IDEMPOTENCY_TTL = 24.hours

  private

  # Віддає `true`, якщо відповідь УЖЕ віддано (400 без ключа або повтор із кешу) —
  # викликач мусить одразу вийти. Скоуп задає ВИКЛИКАЧ і робить це свідомо: там,
  # де об'єкт існує до запиту, ключується він; там, де об'єкт лише створюється,
  # єдина стабільна координата — автор.
  def handle_idempotency!(scope:, error:, replay_status:)
    @idempotency_key = request.headers["Idempotency-Key"]
    @idempotency_scope = scope

    if request.format.json? && @idempotency_key.blank?
      render json: { error: error }, status: :bad_request
      return true
    end

    return false if @idempotency_key.blank?

    cached = Rails.cache.read(idempotency_cache_key)
    return false if cached.nil?

    render json: cached, status: replay_status
    true
  end

  # Кешуємо ЛИШЕ успіх: невдала валідація мусить лишатись повторюваною, інакше
  # ключ заморозив би відмову на добу.
  def remember_idempotent_response!(body)
    return if @idempotency_key.blank?

    key = idempotency_cache_key
    request.env["rack.response_finished"] ||= []
    request.env["rack.response_finished"] << lambda { |_env, _status, _headers, _error|
      Rails.cache.write(key, body, expires_in: IDEMPOTENCY_TTL)
    }
  end

  def idempotency_cache_key
    "idempotency:#{@idempotency_scope}:#{Digest::SHA256.hexdigest(@idempotency_key)}"
  end
end
