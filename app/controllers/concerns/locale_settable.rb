# frozen_string_literal: true

# Concern that resolves and applies the request locale.
#
# Resolution priority (highest first):
#   1. Explicit `params[:locale]` (used by LocalesController#update only)
#   2. Persistent cookie `cookies[:locale]` (1-year expiry)
#   3. HTTP `Accept-Language` header (Rails request.preferred_language API)
#   4. Application default (`I18n.default_locale`)
#
# All resolved values are validated against `I18n.available_locales` — any
# unknown value silently falls through to the next tier so that adversarial
# `?locale=../../etc/passwd` payloads cannot escape the whitelist.
module LocaleSettable
  extend ActiveSupport::Concern

  included do
    before_action :set_locale
  end

  private

  def set_locale
    I18n.locale = resolve_locale
  end

  def resolve_locale
    candidates = [
      params[:locale],
      cookies[:locale],
      request_preferred_language
    ]

    candidates.each do |candidate|
      symbol = candidate&.to_sym
      return symbol if symbol && I18n.available_locales.include?(symbol)
    end

    I18n.default_locale
  end

  def request_preferred_language
    return nil unless request.respond_to?(:preferred_language)

    request.preferred_language(I18n.available_locales)
  rescue StandardError
    # `Accept-Language` header may be malformed; do not let it crash the request.
    nil
  end
end
