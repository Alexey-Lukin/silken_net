# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module SilkenNet
  # [UI.1] Єдиний Ruby-дім бренд-значень для поверхонь, куди CSS-токен не
  # дотягується ЗА ПОБУДОВОЮ: Prawn-PDF (звіти) і PWA-manifest. Розмітка й JS
  # сюди НЕ ходять — вони читають той самий факт рідним каналом (`@theme`
  # у `application.css`; JS — `getComputedStyle` на `--gaia-primary`).
  #
  # Дзеркальність із `@theme` не конвенція, а ГЕЙТ: `spec/lib/silken_net/
  # brand_spec.rb` парсить обидві шафи CSS і червоніє, щойно значення
  # розійдуться. Міняючи палітру — міняй обидва доми одним комітом.
  module Brand
    # --gaia-primary: бренд-емералд, byte-однаковий в обох темах.
    PRIMARY_HEX = "#10b981"
    # Prawn приймає hex БЕЗ ґратки.
    PRIMARY_PRAWN = PRIMARY_HEX.delete("#").freeze
    # --gaia-surface-base ТЕМНОЇ шафи: сплеш-фон PWA до першого рендера.
    SURFACE_BASE_DARK_HEX = "#050607"
  end
end
