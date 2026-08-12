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
  # over Configuration). `Codex::Show#t(".heading")` resolves to
  # `I18n.t("codex.show.heading")`. Absolute keys (e.g. `t("flash.x")`)
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
