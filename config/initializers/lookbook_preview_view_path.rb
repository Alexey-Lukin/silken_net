# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# 🔴 [UI.3] Каталог превʼю мусить лежати у VIEW-шляхах, а не лише в
# `lookbook.preview_paths` — це ДВА різні реєстри, і другий відповідає лише за
# ЗНАХОДЖЕННЯ класів превʼю. Тому навігація Lookbook завжди була повна, а кожен
# сценарій, що рендериться через `render_with_template`, віддавав
# `ActionView::MissingTemplate` на файл, який лежить на диску.
#
# Виміряно 2026-08-19 на живому сервері: **11 із 59** сценаріїв = HTTP 500, і серед
# них найпотрібніші — `status_badge/all_states` (єдине місце, де видно ВСІ стани
# поруч), `status_badge/transaction_states` (життєвий цикл грошової транзакції),
# уся родина `wallet_transaction_row` і обидва `photo_card`.
#
# ⚠️ Клас дефекту — «конфіг повний, шлях мертвий»: сторінка ЄСТЬ у меню, тож дірку
# бачить лише той, хто клікнув. Автотестів на Lookbook немає й бути не мусить
# (dev-only поверхня), тому носій тут — сам факт, записаний у канон `04_04 §10`.
Rails.application.config.after_initialize do
  next unless defined?(Lookbook) && Rails.env.development?

  previews = Rails.root.join("spec/components/previews").to_s
  ActionController::Base.prepend_view_path(previews) if File.directory?(previews)
end
