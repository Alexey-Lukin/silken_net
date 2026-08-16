# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

class ApplicationPolicy
  # [SEC.25 Ф2] Розпаковує `UserContext` → (справжній `User`, id acting-організації).
  # Приймає й голий `User` — так політику конструюють спеки, і так вона поводилась
  # до acting-org. Для всіх, крім super_admin, обидва входи дають те саме, бо
  # acting-організація тотожна власній.
  module ContextUnpacking
    attr_reader :user, :organization_id

    def unpack_actor(actor)
      if actor.is_a?(UserContext)
        @user = actor.user
        @organization_id = actor.organization_id
      else
        @user = actor
        @organization_id = actor&.organization_id
      end
    end
  end

  include ContextUnpacking

  attr_reader :record

  def initialize(user, record)
    unpack_actor(user)
    @record = record
  end

  # [SEC.16] Deny-default. Доти читання було відкрите: `index?`/`show?` віддавали
  # голий `true`, тобто політика, яка ЗАБУЛА визначити читання, мовчки пускала
  # будь-кого до будь-якого запису — і мовчки саме тому, що дефолт виглядає як
  # «база нічого не вирішує», хоч насправді вирішувала найширше можливе.
  #
  # 🔴 Носій дефекту — САМЕ ЦЕЙ дефолт, а не політики, що його успадковують:
  # `rails g pundit:policy` генерує клас від цієї бази, тож fail-open відтворювався б
  # у кожній майбутній політиці незалежно від того, скільки старих ми приберемо.
  # Виміряний blast фліпу — ОДНА політика: єдина в репо, що не визначала власного
  # `show?`, і та не викликалась; `index?` та `Scope#resolve` були перевизначені
  # скрізь, тобто там blast нульовий. ⚠️ Перевірити це в коді більше НЕ МОЖНА:
  # наступного дня (⚖️ 2026-07-31) її знято разом із дев'ятьма іншими мертвими
  # політиками — асоціативний скоуп визнано архітектурою, а не боргом (`04_03 §3`).
  # Дефолт лишається несучим саме тому, що стереже МАЙБУТНЮ політику, а не колишні.
  #
  # ⚠️ Це робить дефолт безпечним, а НЕ політики правильними: жива-але-хибна
  # політика (предикат, що каже `true` там, де мав би звірити організацію) цим
  # фліпом не лікується — її ловлять пари `Scope`+предикат, крос-org піни й
  # adversarial-проходи.
  def index?
    false
  end

  def show?
    false
  end

  def create?
    admin_or_above?
  end

  def update?
    admin_or_above?
  end

  def destroy?
    admin_or_above?
  end

  private

  def admin_or_above?
    user.admin_or_above?
  end

  def super_admin?
    user.role_super_admin?
  end

  def forester_or_above?
    user.forest_commander?
  end

  def same_organization?(resource_org_id)
    organization_id.present? && organization_id == resource_org_id
  end

  class Scope
    include ContextUnpacking

    attr_reader :scope

    def initialize(user, scope)
      unpack_actor(user)
      @scope = scope
    end

    # [SEC.16] Deny-default і на скоупі — дзеркало предикатів вище. Голий `scope.all`
    # означав, що `Scope`, який забули визначити, віддає ВСЮ таблицю крос-тенантно.
    # Blast нульовий: власний `Scope` мають усі політики репо. Тобто рядок сторожить
    # виключно МАЙБУТНЮ політику — і саме тому його форма `none`, а не `all`:
    # забутий скоуп має віддавати порожньо, а не все.
    def resolve
      scope.none
    end

    private

    # [UI.7] `nil` тут — ВІДСУТНІСТЬ контексту, а не організація з `NULL`, і
    # розрізнити їх мусить кожен тенантний `Scope`. Rails перекладає
    # `where(organization_id: nil)` у `IS NULL`, тобто у ФІЛЬТР, що збігається з
    # org-less рядками, тоді як предикат-близнюк (`same_organization?`) на тому
    # самому вході ВІДМОВЛЯЄ. Виміряно на `users`: `Scope` віддавав двох
    # платформених super_admin'ів, а `show?` давав 403 на кожному — список, який
    # неможливо відкрити. Сусіди мовчали з ВИПАДКОВИХ причин (сирий `= NULL`
    # ніколи не істинний; `NOT NULL`-колонка не має чого віддати), тобто fail-closed
    # там був властивістю схеми, а не правила.
    def no_acting_organization?
      organization_id.blank?
    end

    def admin_or_above?
      user.admin_or_above?
    end

    def super_admin?
      user.role_super_admin?
    end
  end
end
