# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# Shared helpers for Phlex component specs.
#
# Convention: every spec under spec/views/ includes this module automatically
# via the metadata hook below. This provides:
#
#   1. `render_component(**kwargs)` — universal entry point.
#      Detects whether the component under test needs a full Rails rendering
#      context (route helpers, Turbo tags, form builders) or can be rendered
#      with a bare `.call`.
#      ⚠️ The decision is a TEXT match, not a class-hierarchy walk — this line
#      claimed the latter for a long time, and the difference has consequences.
#      `compute_needs_renderer` reads the file returned by
#      `Object.const_source_location(klass.name)` and matches
#      RENDERER_HELPER_REGEX against its source. Therefore:
#        · a matching token inside a COMMENT flips the decision (no AST, no
#          comment stripping);
#        · helpers INHERITED from ApplicationComponent do not count — only what
#          is written in the component's own file;
#        · editing application_component.rb cannot change any subclass's verdict.
#      Which is fine, because a false «needs renderer» is merely slower, and a
#      false «doesn't» is caught: the `.call` path rescues NoMethodError and
#      falls back to the renderer anyway (see below).
#
#   2. `component_class` — shorthand for `described_class`.
#
#   3. `mock_pagy(...)` — a REAL `Pagy::Offset` for paginated component specs
#      (the name is legacy; see the method's own comment for why it is not a double).
#
#   4. `mock_model(klass, id:, **attrs)` — builds an OpenStruct that
#      quacks like an ActiveRecord model (model_name, to_key, to_param).
#
# Usage in specs:
#
#   RSpec.describe Trees::Show do
#     let(:html) { render_component(tree: mock_tree) }
#     ...
#   end
#
module PhlexComponentHelper
  extend ActiveSupport::Concern

  # ---------------------------------------------------------------------------
  # Rendering
  # ---------------------------------------------------------------------------

  # Renders the component described by `described_class`.
  # Components that include Turbo/route/form helpers are rendered through
  # `ApplicationController.renderer` to provide a full request context.
  # Pure components are rendered via `.call` for speed.
  #
  # Falls back to the renderer when `.call` raises due to a missing
  # view context (e.g. a sub-component uses route helpers).
  def render_component(**kwargs)
    component = component_class.new(**kwargs)

    if needs_renderer?(component_class)
      ApplicationController.renderer.render(component, layout: false)
    else
      begin
        component.call
      rescue NoMethodError
        ApplicationController.renderer.render(component_class.new(**kwargs), layout: false)
      end
    end
  end

  def component_class
    described_class
  end

  # ---------------------------------------------------------------------------
  # Mock helpers
  # ---------------------------------------------------------------------------

  # Standard Pagy for any paginated component. 🔴 [TEST.12] Це вже НЕ мок —
  # повертається справжній `Pagy::Offset`; назву збережено, бо її кличуть двадцять
  # файлів. Попередній `OpenStruct` мав три вади, і третя несуча:
  #   • оголошував `vars` — методу з таким іменем на `Pagy::Offset` немає взагалі;
  #   • робив ПУБЛІЧНИМ `series`, який у гема `protected` (десята вісь — фікстура
  #     дописує API залежності повз RSpec mock-API, тож переживає бамп мовчки);
  #   • приймав `count` і `last` як НЕЗАЛЕЖНІ поля, тоді як гем виводить `last`
  #     із `count`/`limit` — тобто вміщав стан, недосяжний за побудовою (жменя
  #     записів і водночас кілька сторінок), а перший пін на «сторінка X з Y»
  #     зацементував би неможливе.
  # Тепер `limit` виводиться з бажаного `last`, тож `next`, `previous`, `from`,
  # `to` і `last` течуть з ОДНОГО джерела й суперечити одне одному не можуть.
  #
  # @param count [Integer] total record count
  # @param page  [Integer] current page
  # @param last  [Integer] desired last-page number (set > 1 to make pagination render)
  def mock_pagy(count: 3, page: 1, last: 3)
    Pagy::Offset.new(count: count, page: page, limit: [ (count.to_f / last).ceil, 1 ].max)
  end

  # Builds an OpenStruct that responds to model_name, to_key, to_param —
  # enough to satisfy route helpers and dom_id.
  #
  # @param klass [Class] AR model class (e.g. Tree, Gateway)
  # @param id    [Integer] record id
  # @param attrs [Hash] additional attributes
  def mock_model(klass, id: 1, **attrs)
    obj = OpenStruct.new(id: id, **attrs)
    model_name = ActiveModel::Name.new(klass)
    obj.define_singleton_method(:model_name) { model_name }
    obj.define_singleton_method(:to_key) { [ id ] }
    obj.define_singleton_method(:to_param) { id.to_s }
    obj
  end

  private

  # Cache must outlive a single example — every spec example is a fresh
  # instance, so an `@_renderer_cache` ivar would re-read the source file
  # on every `render_component` call. Module-level Hash + Mutex makes the
  # decision once per component class for the whole suite. Parallel
  # examples (if/when enabled) read the same memoized verdict.
  RENDERER_DECISION_CACHE = {}
  RENDERER_DECISION_MUTEX = Mutex.new
  RENDERER_HELPER_REGEX = /\b(turbo_frame_tag|turbo_stream_from|button_to|form_with|link_to)\b|\w+_(path|url)\b/

  # Determines whether the component class needs a full Rails renderer.
  # True when the source file references route helpers, Turbo tags, or
  # form builders that require a request context.
  def needs_renderer?(klass)
    return RENDERER_DECISION_CACHE[klass] if RENDERER_DECISION_CACHE.key?(klass)

    RENDERER_DECISION_MUTEX.synchronize do
      # Double-checked inside the mutex so two threads don't both read the
      # source file when entering the critical section simultaneously.
      RENDERER_DECISION_CACHE[klass] = compute_needs_renderer(klass) unless RENDERER_DECISION_CACHE.key?(klass)
      RENDERER_DECISION_CACHE[klass]
    end
  end

  def compute_needs_renderer(klass)
    source_file = Object.const_source_location(klass.name)&.first
    return true unless source_file

    File.read(source_file).match?(RENDERER_HELPER_REGEX)
  end
end

RSpec.configure do |config|
  config.include PhlexComponentHelper, file_path: %r{spec/views/}
end
