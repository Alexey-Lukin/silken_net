# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

class AuditLogBlueprint < Blueprinter::Base
  identifier :id

  view :index do
    fields :action, :auditable_type, :auditable_id, :metadata, :created_at
    association :user, blueprint: UserBlueprint, view: :crew
  end

  view :show do
    fields :action, :auditable_type, :auditable_id, :metadata,
           :ip_address, :user_agent, :chain_hash, :ipfs_cid, :created_at
    # 🔴 [SEC.36] Актор іде `:crew`, а НЕ `:profile` — і це не звуження заради
    # звуження, а повернення `:profile` до того, чим його оголошено власним
    # коментарем: «використовується в GET /users/me». Той вигляд збудовано для
    # СЕБЕ, і два його поля це видають — `mfa_enabled` та `has_password` є
    # фактами, які людина перевіряє про ВЛАСНУ безпекову поставу (сторінка
    # `users/profile` малює саме їх, і саме свої). Через журнал вони їхали про
    # КОЛЕГУ: адміністратор, відкриваючи чужий запис, діставав у JSON стан
    # чужого другого фактора й чи взагалі має та людина пароль.
    # ⊕ Дзеркало розходилось і з власною HTML-панеллю того ж екшена
    # (`audit_logs/show` малює імʼя · пошту · роль — і нічого понад те), і з
    # сусіднім `:index`, що вже роками бере `:crew`. Тобто вигляд «про іншу
    # людину» в цьому файлі вже стояв — просто `show` його не взяв.
    # 🔒 Ціна названа: з JSON зникає й `email_address` актора, який HTML-панель
    # показує. Обміняно свідомо — `id` актора лишається в кожному вигляді
    # (`identifier`), тож адреса резолвиться окремим запитом, тоді як безпекова
    # постава колеги не мала б резолвитись НІЯК.
    association :user, blueprint: UserBlueprint, view: :crew
  end
end
