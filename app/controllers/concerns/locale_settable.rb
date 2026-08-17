# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# Concern that resolves and applies the request locale.
#
# Resolution priority (highest first):
#   1. Explicit `params[:locale]` — ⚠️ НЕ «лише `LocalesController#update`», як тут
#      стояло: концерн глобальний, тож `?locale=uk` діє на БУДЬ-ЯКОМУ екшені, і це
#      навантажений контракт (живий пін — `actuators_controller_spec`), а не
#      побічний ефект. Безпечний, бо whitelist нижче тримає, і нікуди не
#      персиститься; але писати «only» означало документувати неіснуючу межу
#   2. Persistent cookie `cookies[:locale]` (1 рік — строк ставить писач,
#      `LocalesController#update`; цей концерн cookie лише ЧИТАЄ) — «обрав У ЦЬОМУ браузері»
#   3. Persisted account preference `users.locale` — переживає зміну пристрою
#   4. HTTP `Accept-Language` header (via `Rack::Utils`, no gem needed)
#   5. Application default (`I18n.default_locale`)
#
# All resolved values are validated against `I18n.available_locales` — any
# unknown value silently falls through to the next tier so that adversarial
# `?locale=../../etc/passwd` payloads cannot escape the whitelist.
#
# 🔴 [I18N.3] Щабель 4 сім місяців був МЕРТВИЙ, і мовчки: код кликав
# `request.preferred_language`, якого не існує ні в `actionpack`, ні в `rack`
# (він приходить із гема `http_accept_language`, якого в `Gemfile` немає), а
# власний гард `return nil unless request.respond_to?(...)` ковтав це без
# винятку й без рядка в лозі. Наслідок: перший візит будь-якої людини —
# завжди `default_locale`. Лік не потребував ані гема, ані власного парсера:
# `Rack::Utils` уже вміє і q-values, і вибір найкращого збігу.
module LocaleSettable
  extend ActiveSupport::Concern

  included do
    before_action :set_locale
  end

  private

  def set_locale
    I18n.locale = resolve_locale
  end

  # 🔴 Другий прохід, і власне ім'я тут НЕСУЧЕ, а не косметика.
  #
  # `current_user` присвоюється в `authenticate_user!`, який реєструється ПІСЛЯ
  # цього концерну, тож на першому проході акаунт-щабель порожній за побудовою.
  # Природний хід «зареєструвати `before_action :set_locale` ще раз» НЕ працює:
  # Rails дедуплікує колбеки за іменем фільтра — повторна реєстрація не додає
  # другий виклик, а ПЕРЕСУВАЄ єдиний у кінець (виміряно на
  # `_process_action_callbacks`). Рання фаза просто зникла б, і сторінка логіну
  # (`render_unauthorized` кличе `I18n.t` ще всередині автентифікації) втратила
  # б мову — тобто «додати щабель» тихо відібрало б наявну поведінку.
  def set_locale_from_account
    set_locale
  end

  # ⚠️ Щаблі оцінюються ЛІНИВО, і це не мікрооптимізація. Літеральний масив
  # кандидатів обчислював би ВСІ чотири навіть тоді, коли cookie вже відповіла:
  # `locale_account` під `LocalesController` — це запит у БД (salt-звірений
  # lookup), а `header_preferred_language` парсить заголовок клієнта й на битому
  # вході пише в лог. Тобто ціна невидима саме там, де відповідь уже відома з
  # першого щабля, і зростає з кожним новим щаблем, який хтось допише нижче.
  # 🔴 [I18N.3] `account:` — ЯВНИЙ актор, і він існує рівно для межі ЗМІНИ актора.
  # На `POST /login` (`skip_before_action :authenticate_user!`) акаунт-щабель
  # порожній за побудовою, тож flash писався мовою браузера, а наступна сторінка
  # рендерилась мовою акаунта; на `DELETE /logout` те саме дзеркально. Параметр,
  # а не другий ланцюг: копія щаблів розійшлась би з цією при першій же правці
  # порядку — а порядок тут ратифікований присудом власника.
  def resolve_locale(account: locale_account)
    supported_locale(params[:locale]) ||
      supported_locale(cookies[:locale]) ||
      supported_locale(account&.locale) ||
      supported_locale(header_preferred_language) ||
      I18n.default_locale
  end

  # Whitelist — єдина точка, що перетворює НЕДОВІРЕНИЙ рядок на локаль. Саме він
  # робить `?locale=../../etc/passwd` невидимим: невідоме значення не «падає в
  # помилку», а просто провалюється на наступний щабель.
  def supported_locale(candidate)
    return nil unless candidate.is_a?(String) && candidate.present?

    symbol = candidate.to_sym
    symbol if I18n.available_locales.include?(symbol)
  end

  # Точка розширення для контролерів, що мають автентифікованого користувача.
  #
  # Дефолт `nil` — ЯВНА декларація, а не `respond_to?`-здогадка. Саме тихий
  # `respond_to?`-гард ховав мертвий щабель `Accept-Language`, тож повторювати
  # ту форму тут було б відтворенням дефекту: під `ApplicationController` живе
  # лише `LocalesController`, у якого власного `current_user` немає за
  # побудовою, і це факт про дерево, а не про рантайм.
  def locale_account
    nil
  end

  # `Accept-Language` поверх Rack — але ЛЕКСЕР звідти, а ВИБІР наш.
  #
  # 🔴 Розділення не стильове, а виміряне, і перша редакція цього методу була
  # НЕПРАВИЛЬНА саме тут. `Rack::Utils.best_q_match` виглядає як готова
  # відповідь, та має **MIME-семантику**: він зіставляє через `Rack::Mime.match?`,
  # який ділить значення по `/`. У мовному тезі слеша немає ніколи, тож матчер
  # вироджується в точну рівність, а сортування при РІВНИХ `q` бере ОСТАННІЙ
  # елемент. Виміряно на `rack 3.2.6`, каталог `[en uk lv lt]`:
  #
  #   "uk,en"        → "en"   ← інверсія: RFC 9110 §12.5.4 каже, що при рівних
  #   "uk-UA,uk,en"  → "en"     вагах ПОРЯДОК і є перевагою (це форма Chrome)
  #   "uk-UA"        → nil    ← регіон не падає на базову мову
  #   "en;q=0"       → "en"   ← `q=0` означає «неприйнятно», а не «підходить»
  #   "uk,,en"       → RAISE  ← і валідний `uk` гине разом із порожнім сегментом
  #
  # Тобто «платформа це вже вміє» було правдою лише наполовину: `q_values` —
  # коректний лексер, `best_q_match` — чужий інструмент із правдоподібним іменем.
  # Тут ми беремо перше й робимо друге самі: відкинути `q=0`, стабільно
  # відсортувати за вагою (індекс розв'язує рівність — саме цього бракувало),
  # звести регістр (BCP-47 регістро-нечутливий), а на невідомий регіональний тег
  # спробувати базову мову. `*` означає «будь-яка інша» → базова локаль.
  def header_preferred_language
    header = request.get_header("HTTP_ACCEPT_LANGUAGE")
    return nil if header.blank?

    supported = I18n.available_locales.to_h { |locale| [ locale.to_s.downcase, locale.to_s ] }

    ranked_tags(header).each do |tag|
      return supported[tag] if supported.key?(tag)

      base = tag.split("-").first
      return supported[base] if supported.key?(base)
      return I18n.default_locale.to_s if tag == "*"
    end

    nil
  rescue StandardError => e
    # Заголовок приходить від клієнта, тож битий вхід не сміє валити запит.
    # Але 🔴 мовчати тут не можна — саме мовчазний `rescue` поверх мовчазного
    # `respond_to?` робив попередню відмову невидимою на ДВОХ рівнях одразу.
    Rails.logger.warn("[I18N] Accept-Language parse failed: #{e.class}: #{e.message}")
    nil
  end

  # Теги за спаданням переваги. `sort_by` з індексом у ключі дає СТАБІЛЬНЕ
  # сортування — без нього рівні ваги розв'язуються довільно, і саме там
  # `best_q_match` віддавав останній замість першого.
  def ranked_tags(header)
    Rack::Utils.q_values(header)
               .each_with_index
               .reject { |(tag, quality), _i| tag.blank? || quality <= 0 }
               .sort_by { |(_tag, quality), index| [ -quality, index ] }
               .map { |(tag, _quality), _i| tag.downcase }
  end
end
