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
      klass_name = self.class.name || self.class.ancestors.lazy.filter_map(&:name).first
      scope = klass_name&.underscore&.gsub("/", ".") || ""
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
end
