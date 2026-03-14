# frozen_string_literal: true

# @label Theme Switcher
class ThemeSwitcherPreview < Lookbook::Preview
  # @label Default
  # @notes Dark/light theme toggle button with Stimulus integration.
  def default
    render Views::Shared::UI::ThemeSwitcher.new
  end
end
