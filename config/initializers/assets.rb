# SPDX-License-Identifier: AGPL-3.0-or-later
# Be sure to restart your server when you modify this file.

# Version of your assets, change this if you want to expire all your assets.
Rails.application.config.assets.version = "1.0"

# Add additional assets to the asset load path.
#
# [TEST.7] Vendored сторонні стилі. `vendor/javascript` Propshaft бачить сам
# (його додає importmap-rails), а `vendor/assets/stylesheets` — ні, тож шлях
# треба заявити явно; інакше `asset_path("leaflet/leaflet.css")` не резолвиться.
# Тут лежить локальна копія Leaflet CSS разом із його `images/`: CSS шле
# ВІДНОСНІ `url(images/*.png)`, і Propshaft переписує їх на дайджест-шляхи лише
# тоді, коли картинки лежать поруч із самим CSS.
Rails.application.config.assets.paths << Rails.root.join("vendor/assets/stylesheets")

# [UI.3] Вендоровані бінарники шрифтів. Тут лежать ЛИШЕ файли (третя сторона,
# SIL OFL 1.1 — текст ліцензії поруч); самі `@font-face` — НАШІ й живуть у
# `app/assets/stylesheets/application.css`, бо це наше оголошення, не чуже.
# Propshaft резолвить `url("jetbrains-mono/…woff2")` із того CSS по ВСІХ
# load-path'ах (`Propshaft::Compiler::CssAssetUrls#resolve_path` — перевірено
# в джерелі), тож перетинати каталоги через `../` не потрібно.
Rails.application.config.assets.paths << Rails.root.join("vendor/assets/fonts")
