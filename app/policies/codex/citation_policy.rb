# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# Codex::CitationPolicy — full RBAC for the citations surface (create/destroy via
# API; reads happen inline in target view components, no dedicated read endpoint).
# `update?` has no live caller yet — no admin edit route exists for citations.
#
# Read: any authenticated user.
# Create: forester+ (operational citation = treats lore as production data).
# Update / destroy: own ≤ 24h, or admin+.
module Codex
  class CitationPolicy < ApplicationPolicy
    def index?
      user.present?
    end

    def show?
      user.present?
    end

    def create?
      forester_or_above?
    end

    def update?
      owner_within_grace? || admin_within_same_organization?
    end

    def destroy?
      owner_within_grace? || admin_within_same_organization?
    end

    private

    def owner_within_grace?
      record.created_by_user_id == user.id && record.created_at >= 24.hours.ago
    end

    # [SEC.26] Голий `admin_or_above?` тут означав, що admin БУДЬ-ЯКОЇ організації
    # зносить будь-яку цитату на платформі. Вісь звуження — організація АВТОРА, а не
    # цитованої цілі: ціль може бути вже знищена, і скоуп по ній лишив би осиротілу
    # цитату невидалимою (дзеркало `verify_citation_within_organization!` у
    # контролері — там же й повний розбір вибору осі).
    #
    # Це НЕ забирає в адмінів модерацію lore: сусідній `Codex::CommentPolicy` уже
    # зафіксував, що глобальне втручання в чужий лор — це `hide?`, ніколи `destroy`.
    # У цитат прихованого стану немає, тож глобального дієслова тут просто нема чого
    # успадковувати.
    #
    # ⚠️ Чесна межа: на шляху `destroy` цей предикат ВТОРИННИЙ — гард контролера
    # відсікає чужу цитату раніше (і 404-ом, а не 403). Він лишається тут, бо тримає
    # `update?`, у якого гарду нема, і бо політика мусить бути правдивою сама по собі:
    # доти її власна спека стверджувала «permits admin on a foreign citation».
    def admin_within_same_organization?
      admin_or_above? && same_organization?(record.created_by_user&.organization_id)
    end
  end
end
