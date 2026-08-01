# SPDX-License-Identifier: AGPL-3.0-or-later
class ApplicationController < ActionController::Base
  include LocaleSettable

  # [SEC.25 Ф3] Дзеркало реєстрації з `Api::V1::BaseController` — той успадковує
  # `ActionController::Base` напряму, тож спільного предка в них немає і список
  # мусить стояти в обох. Сьогодні під цим коренем живе лише `LocalesController`,
  # який ставить flash формою `flash[:x] =` (вона приймає будь-який ключ і без
  # реєстрації) — рядок тут коштує нуль і гасить клас: перша ж kwarg-форма,
  # написана під цим коренем, інакше зникла б мовчки.
  add_flash_types :success, :error, :pending, :security

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes
end
