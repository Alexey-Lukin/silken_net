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
