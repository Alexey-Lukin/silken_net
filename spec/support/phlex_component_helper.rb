# frozen_string_literal: true

# Shared helpers for Phlex component specs.
#
# Convention: every spec under spec/views/ includes this module automatically
# via the metadata hook below. This provides:
#
#   1. `render_component(**kwargs)` — universal entry point.
#      Detects whether the component under test needs a full Rails rendering
#      context (route helpers, Turbo tags, form builders) or can be rendered
#      with a bare `.call`. The decision is based on the component class
#      hierarchy — any class including Phlex::Rails helpers gets the renderer.
#
#   2. `component_class` — shorthand for `described_class`.
#
#   3. `mock_pagy(...)` — standard Pagy double used across ~20 specs.
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

  # Standard Pagy mock used by any paginated component.
  #
  # @param count [Integer] total record count
  # @param page  [Integer] current page
  # @param last  [Integer] last page number (set > 1 to make pagination render)
  def mock_pagy(count: 3, page: 1, last: 3)
    pagy = OpenStruct.new(
      count: count,
      page: page,
      last: last,
      from: 1,
      to: count,
      prev: page > 1 ? page - 1 : nil,
      next: page < last ? page + 1 : nil,
      vars: { items: 21 }
    )
    pagy.define_singleton_method(:series) do
      (1..last).to_a
    end
    pagy
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
    obj.define_singleton_method(:to_key) { [id] }
    obj.define_singleton_method(:to_param) { id.to_s }
    obj
  end

  private

  # Determines whether the component class needs a full Rails renderer.
  # True when the class (or any ancestor) includes Phlex::Rails helpers
  # that require a request context (route helpers, Turbo tags, form builders).
  def needs_renderer?(klass)
    # Components that use route helpers (_path/_url), turbo_frame_tag,
    # turbo_stream_from, form_with, button_to — all of these come from
    # Phlex::Rails::Helpers::* modules included in ApplicationComponent.
    # We detect this by checking whether the class has overridden
    # `call` to require a view context.
    #
    # Simpler heuristic: check if the source file references any route/turbo
    # helper. But that's fragile. Instead we try .call and fall back.
    #
    # The most reliable approach: components that DON'T use any of these
    # helpers can render without context. We maintain a class-level cache.
    @_renderer_cache ||= {}
    return @_renderer_cache[klass] if @_renderer_cache.key?(klass)

    source_file = Object.const_source_location(klass.name)&.first
    return @_renderer_cache[klass] = true unless source_file

    source = File.read(source_file)
    @_renderer_cache[klass] = source.match?(/\b(turbo_frame_tag|turbo_stream_from|button_to|form_with|link_to)\b|\w+_(path|url)\b/)
  end
end

RSpec.configure do |config|
  config.include PhlexComponentHelper, file_path: %r{spec/views/}
end
