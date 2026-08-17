# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# Fallback for asset-resolving helpers on DashboardLayout and AuthLayout in test.
#
# `Phlex::Rails::Layout` кличе `stylesheet_link_tag` / `javascript_importmap_tags`,
# а ті вимагають зібраних assets (Propshaft + Tailwind). Без `public/assets`
# кожна request-спека, що рендерить повний layout, падала б на
# `Propshaft::MissingAssetError` — тож фолбек лишається.
#
# 🔴 [TEST.7] Але доти це був БЕЗУМОВНИЙ stub, і саме він — а не Rails, не
# Capybara й не рендер-шлях запиту — глушив увесь наш JS у браузерних тестах:
# сторінка приїжджала без importmap, `window.Stimulus` лишався `undefined`, і
# будь-який сценарій на Stimulus/Turbo-морф/Leaflet був недоказовний В ПРИНЦИПІ.
# Діагноз три рази шукали в чужому коді (`bin/rails runner` віддавав теги
# коректно рівно тому, що НЕ вантажить `spec/support/`), і кожен раз він
# читався як інфраструктурна яма Rails.
#
# Тому глушимо ТІЛЬКИ реальну відсутність asset'а, а не виклик як такий: зібрані
# assets тепер доїжджають у браузер, а прогін без них поводиться рівно як раніше
# — жодна наявна спека не рухається. ⚠️ **«Зібрані» тут означає
# `bin/rails tailwindcss:build`, НЕ `assets:precompile`** (уточнено 2026-08-17):
# Propshaft у dev/test резолвить із load-path динамічно, а прекомпіляція
# натомість створює манифест, що перемикає його на Static і подає застарілий
# дайджест — тобто дає ТИХО хибний вимір замість гучного (`04_06 §B.1.4`).
[ DashboardLayout, AuthLayout ].each do |klass|
  next if klass.instance_variable_get(:@test_asset_patched)

  klass.prepend(Module.new do
    def stylesheet_link_tag(*args, **opts)
      super
    rescue Propshaft::MissingAssetError
      ""
    end

    def javascript_importmap_tags(*args, **opts)
      super
    rescue Propshaft::MissingAssetError
      ""
    end
  end)
  klass.instance_variable_set(:@test_asset_patched, true)
end
