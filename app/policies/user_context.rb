# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# [SEC.25 Ф2] Пара «хто питає + в контексті ЯКОЇ організації» для Pundit.
#
# Потрібна тому, що організація запиту більше не виводиться з користувача:
# super_admin працює в контексті ОДНІЄЇ організації за раз і може її перемкнути
# (`session[:acting_org_id]`), тож `user.organization_id` перестав бути відповіддю
# на питання «чий це скоуп».
#
# 🔒 ЧОГО ЦЕЙ КЛАС СВІДОМО НЕ РОБИТЬ — і це не аскетизм, а вимір.
#
# Він НЕ підміняє користувача й НЕ делегує на нього (`delegate_missing_to`).
# Політики питають у користувача не лише організацію: `user.present?` — базовий
# RBAC-примітив усієї codex-гілки, а `return scope.none unless user` — її форма
# fail-closed. `present?`/`blank?`/`nil?` означені на `Object`, тобто вони НЕ
# «missing» і делегування їх не перехоплює НІКОЛИ: обгортка навколо `nil`-юзера
# відповідала б `present? == true` і перевертала б кожен із цих гардів на
# fail-OPEN. Дзеркально `user&.role_admin?` перестав би рятувати — обгортка не
# nil, тож `&.` пропускає виклик далі, у `nil`, і летить `NoMethodError`, який
# `rescue_from StandardError` перетворить на безликий 500.
#
# Тому контракт вужчий: контекст несе ОРГАНІЗАЦІЮ, користувач лишається собою.
# `ApplicationPolicy` розпаковує пару й тримає `user` справжнім `User` (або `nil`),
# а `organization_id` бере звідси. Побічна вигода — політика приймає і голий
# `User` (так її конструюють спеки), і контекст (так її конструює прод), тож
# наявні піни лишаються дійсними замість того, щоб мовчки почати пінити не той тип.
class UserContext
  attr_reader :user, :organization

  def initialize(user, organization)
    @user = user
    @organization = organization
  end

  def organization_id
    organization&.id
  end
end
