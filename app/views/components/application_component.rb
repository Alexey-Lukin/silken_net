# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

class ApplicationComponent < Phlex::HTML
  include Phlex::Rails::Helpers::Routes
  include Phlex::Rails::Helpers::TurboStreamFrom
  include Phlex::Rails::Helpers::TurboFrameTag
  include Phlex::Rails::Helpers::FormWith
  include Phlex::Rails::Helpers::ButtonTo
  include Phlex::Rails::Helpers::AssetPath
  include Phlex::Rails::Helpers::FormAuthenticityToken
  # Adds `t(".key")` with class-name-based autoscope (Rails Convention
  # over Configuration). `Wallets::Show#t(".heading")` resolves to
  # `I18n.t("wallets.show.heading")`. Absolute keys (e.g. `t("flash.x")`)
  # still work as a fallback for cross-cutting messages.
  #
  # We override the Phlex::Rails helper because it requires a Rails view
  # context (`helpers.translate`), which is `nil` in component specs that
  # render via `Component.new(...).call` and in Turbo Stream broadcasts
  # (where Phlex is invoked outside a controller). Falling back to `I18n.t`
  # for absolute keys (`"foo.bar"`) keeps both call sites working.
  include Phlex::Rails::Helpers::Translate

  def t(key, **options)
    if key.to_s.start_with?(".")
      # `self.class.ancestors` always contains a named class (at minimum
      # Object/BasicObject), so this fallback chain can never yield nil —
      # no `&.`/`|| ""` needed after it (verified empirically; dead-branch
      # cleanup per 04_06 §B.4).
      klass_name = self.class.name || self.class.ancestors.lazy.filter_map(&:name).first
      scope = klass_name.underscore.gsub("/", ".")
      I18n.t("#{scope}#{key}", **options)
    else
      I18n.t(key, **options)
    end
  end
  alias_method :translate, :t
  include Phlex::SVG::StandardElements
  include ActionView::RecordIdentifier

  # Pure formatting helpers that work without a view context.
  # Delegated directly so components render correctly in Turbo broadcasts
  # (where no Rails view context is available).
  delegate :time_ago_in_words, :number_to_human_size, to: :"ActionController::Base.helpers"

  # Custom font-size tokens defined in app/assets/tailwind/application.css @theme.
  # Registered here so TailwindMerge treats them as font-size (not text-color).
  CUSTOM_TEXT_SCALE = %w[micro mini tiny compact display-sm display-md display-lg].freeze

  # [UI.3] `id` поля, деривований з його `name` за Rails-конвенцією
  # (`organization[name]` → `organization_name`, `current_password` → `current_password`).
  #
  # 🔴 **Навіщо дім, а не рядок на місці:** мітка, не звʼязана з полем, — це WCAG 1.3.1
  # (скрінрідер поля просто НЕ НАЗИВАЄ), і воно сильніше за 3.3.1, заради якого писався
  # цей пункт. Там, де форма йде через `form_with |f|`, звʼязок дає сам білдер — і в
  # ТОМУ випадку цей хелпер не потрібен (див. `TreeFamilies::Form` як еталон). Він
  # існує для форм, де поля не є атрибутами моделі: контролер читає `params[:current_password]`
  # плоско, тож білдера в блоці немає, а `id` треба вигадати обабіч — і саме «обабіч»
  # є режимом відмови, бо дві рукописні копії розходяться мовчки.
  def field_id_for(name) = name.to_s.gsub(/\]\[|\[|\]/, "_").chomp("_")

  # [UI.3] Per-field індикація ПОМИЛКИ — ОДИН дім на застосунок.
  #
  # 🔴 Що це лікує: `ErrorSummary` показує СПИСОК причин згори, тож людина зі
  # скрінрідером чує їх усі, а дійшовши до конкретного поля не дізнається, що
  # невалідне саме воно (WCAG 3.3.1 просить звʼязати причину з ПОЛЕМ, а не лише
  # показати її). Доти `aria-invalid` мав **нуль** входжень у всьому `app/`.
  #
  # ⚠️ Пастка, через яку це виглядало зробленим: Rails-івський
  # `ActionView::Base.field_error_proc` активний і справді огортає невалідне поле
  # в `.field_with_errors` — але той клас ніде не стилізований (нуль згадок у
  # `application.css`), тобто механізм працює й не дає ані візуального, ані ARIA
  # сигналу. Перевизначати його ми свідомо НЕ стали: proc дістає готовий HTML
  # РЯДКОМ, тож додати в тег атрибут можна лише регексом по розмітці — це другий
  # рендерер поза Phlex, якого ніхто не звіряє.
  #
  # 🔴 `aria-describedby`, а не `aria-errormessage`, попри те, що остання назва
  # точніша: `aria-errormessage` озвучується лише в парі з `aria-invalid="true"`
  # і має нерівну підтримку в AT, тоді як `describedby` працює скрізь і вже
  # вживається в цьому дереві для підказок (`notifications/settings`). Форма,
  # у якої поле нестиме І hint, І помилку, мусить злити обидва id в один атрибут —
  # сьогодні такої немає (hint живе лише у формах без моделі).
  #
  # `id` не деривуємо самі: `form.field_id(attr, :error)` — нативна Rails-конвенція
  # (8.1), тобто той самий бік, що генерує `id` поля, генерує й адресу помилки,
  # і розійтись вручну вони не можуть.
  def field_error_messages(form, attribute)
    return [] if form.object.blank?

    form.object.errors[attribute]
  end

  # Атрибути для САМОГО контрола. Порожній хеш, коли поле валідне — `aria-invalid`
  # на справному полі є твердженням не менш гучним, ніж на зламаному.
  def field_error_attrs(form, attribute)
    return {} if field_error_messages(form, attribute).empty?

    { aria: { invalid: "true", describedby: form.field_id(attribute, :error) } }
  end

  # Вузол, на який вказує `aria-describedby`. Тон — `status-danger-accent`, бо це
  # сигнал БЕЗ власного фону: парний `-text` призначений стояти на `bg-status-danger`,
  # і винести його на поверхню форми означало б ужити токен поза роллю — рівно та
  # підміна, що вже коштувала невидимих гліфів (`04_04 §3.2`). Виміряно на
  # `bg-gaia-surface`: **4.83:1** світла · 5.12:1 темна, при порозі 4.5 для `text-mini`.
  def render_field_error(form, attribute)
    messages = field_error_messages(form, attribute)
    return if messages.empty?

    p(id: form.field_id(attribute, :error), class: "text-mini text-status-danger-accent") do
      messages.to_sentence
    end
  end

  def tokens(*args, **conditions)
    result = args.compact.join(" ")
    conditional = conditions.filter_map { |cls, flag| cls.to_s if flag }.join(" ")
    combined = [ result, conditional ].reject(&:empty?).join(" ")
    self.class.merger.merge(combined)
  end

  def self.merger
    @merger ||= TailwindMerge::Merger.new(config: {
      theme: { "text" => CUSTOM_TEXT_SCALE }
    })
  end

  # [ARCH.88] One-Home ТОЧНОСТІ балових величин (`balance` · `locked_balance` ·
  # `available_balance` · `esg_retired_balance`). Доти ті самі поля того самого
  # гаманця друкувались `.round(6)` · `.round(4)` · `.round(2)` у трьох різних
  # компонентах — тобто застосунок відповідав на одне питання трьома числами.
  #
  # Чому саме 2, і це НЕ смак: крок джерела. `TreeFamily#weighted_growth_points`
  # округлює нарахування до 2 знаків (`(raw × coefficient).round(2)`), а решта
  # рухів балансу — цілі (мінт блокує `tokens × threshold`). Отже кожна балова
  # величина кратна 0.01 ЗА ПОБУДОВОЮ, і 6 знаків схеми `numeric(24,6)` — запас
  # сховища, а не наявна інформація. Друкувати їх означало б показувати нулі як
  # точність.
  #
  # ⚠️ Наслідок, який тут несучий: гард виду `if value > 0` більше не розходиться
  # з тим, що надрукується. Доти `Wallets::Index` рахував `> 0`, а друкував
  # `.round(2)` — тож доведено ненульова величина могла вийти як «0.0» (клас
  # «механізм ⟷ його пускач»). При кроці 0.01 ненульове ніколи не округлиться в нуль.
  #
  # ⛔ JSON НЕ округлюємо: `WalletBlueprint` віддає сиру `numeric(24,6)` навмисно —
  # API-споживач рахує сам, і зрізати за нього значить вирішити за чужий калькулятор.
  POINTS_PRECISION = 2

  def formatted_points(value)
    value.to_f.round(POINTS_PRECISION)
  end

  # [ARCH.84] Дім ПОЯВИ стану «не виміряно» — один на всі поверхні, що показують
  # величину 0..1 у відсотках. `nil` тут не «нуль» і не «порожньо»: це окремий стан
  # поряд із будь-яким виміряним числом, включно з тими самими 0% і 100%.
  #
  # 🔴 Чому СЛОВО, а не звичне для дерева тире: тире означає «значення немає» взагалі,
  # а тут твердження вужче — «вимірювання не відбулося», і воно мусить бути відрізнимим
  # від «виміряли, вийшло погано». Прецедент форми — `ARCH.81`, де стан теж дістав
  # ІМʼЯ (`not_configured`), а не символ, саме щоб не злитись із сусіднім `unreachable`.
  # ⚠️ Побічно це й робить фолбек самодискримінованим: відсоток ніколи не рендериться
  # словом, тож пін на цей текст не може випадково пройти через виміряне значення
  # (на відміну від піна на клас — `status-neutral` несе ще пʼять живих станів).
  def measured_percent(value, precision: 0)
    return t("ui.measurement.not_measured") if value.nil?

    pct = (value * 100).round(precision)
    "#{precision.zero? ? pct.to_i : pct}%"
  end

  # [ARCH.84] Третій член тієї ж родини — значення З ОДИНИЦЕЮ. `measured_percent`
  # покриває шкалу 0..1, а сенсорні величини мають власну одиницю й нікуди не
  # нормуються, тож інтерполяція `"#{value || 0} mV"` була єдиною наявною формою —
  # і саме вона друкує ВИМІРЯНИЙ НУЛЬ там, де виміру не було. ⚠️ Одиниця — окремий
  # аргумент, а не частина значення: підпис і число мають рендеритись одним вузлом
  # лише тут, тоді як пін на них має право цілитись у кожне окремо (`04_06 §B.2`).
  # `space:` — типографіка, не логіка: «3800 mV» пишеться з пробілом, «58.1%» без
  # (SI ставить пробіл перед одиницею, але не перед знаком відсотка).
  def measured_value(value, unit, space: true)
    return t("ui.measurement.not_measured") if value.nil?

    "#{value}#{' ' if space}#{unit}"
  end

  # [ARCH.84] Пара до `measured_percent` для АГРЕГАТІВ: середнє по виміряній підмножині
  # правдиве про неї й німе про решту, тож поруч мусить їхати підстава — скільки з
  # чого виміряно. Повне покриття підпису НЕ отримує (нема чого дисконтувати), тож
  # рядок зʼявляється рівно тоді, коли він щось означає.
  def measurement_coverage(measured, total)
    return nil if measured.nil? || total.nil? || total.zero?
    return nil if measured == total

    t("ui.measurement.coverage", measured: measured, total: total)
  end

  # Phlex формалізує в текст ЛИШЕ `Float` та `Integer`; на будь-що інше його
  # `format_object` віддає `nil`, і тоді в буфер не йде НІЧОГО — вузол виходить
  # порожнім без жодної помилки (`04_04 §2`). Виміряно рендером: BigDecimal ·
  # Rational · Date · Time · true/false · Array · Hash → «».
  #
  # `Numeric` — не політика, а рід, який Phlex просто не перелічив: `decimal`
  # приходить BigDecimal'ом, і арифметика з ним заражає в ОДИН бік
  # (Float + BigDecimal = BigDecimal), тож канал зараження не має статичної
  # форми й жодним сканом коду не ловиться.
  private def format_object(object)
    case object
    # `to_s("F")` явно, а не голий `to_s`: десятковий вигляд BigDecimal у Rails дає
    # патч `ActiveSupport::BigDecimalWithDefaultFormat`, і без нього той самий виклик
    # повертає НАУКОВУ нотацію (`0.123…e14`). Спиратись тут на чужий патч мовчки —
    # означає мати формат, який зникне від зміни в сусідньому гемі.
    when BigDecimal then object.to_s("F")
    when Numeric then object.to_s
    # 🔴 Колекція тут — НЕ значення, а штатний залишок ітерації: `div { rows.each … }`
    # повертає саму колекцію, і коли вона порожня, буфер не зрушив, тож Phlex питає
    # про неї саме тут. Виміряно: без цієї гілки гучними стають 105 законних прикладів.
    when Enumerable then nil
    else super || unrenderable!(object)
    end
  end

  # Решту типів свідомо не друкуємо: дата/час без `l()` втрачає локаль, а булеве
  # значення не є текстом інтерфейсу. Але МОВЧАЗНА втрата не має власного
  # симптому — порожній вузол виглядає як «даних немає», — тому поза продом вона
  # гучна. У проді лишається тиша: падати через формат гірше, ніж недодрукувати.
  private def unrenderable!(object)
    return nil unless Rails.env.local?

    raise Phlex::ArgumentError, <<~MSG.squish
      Phlex не вміє надрукувати #{object.class} — вузол вийде ПОРОЖНІМ, мовчки.
      Дай явну форму: дата/час → `l(value, format: :short)` або `.to_fs(:short)`;
      булеве → тернарник із текстом; колекція → зведи в рядок. (`04_04 §2`)
    MSG
  end
end
