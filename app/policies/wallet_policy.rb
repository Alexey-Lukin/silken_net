# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

class WalletPolicy < ApplicationPolicy
  def index?
    true
  end

  # [SEC.25 Ф2] Роль тут більше не дає доступу — лише організація, в контексті якої
  # виконується запит. Раніше рядок вів `super_admin? ||`, тобто платформена роль
  # відмикала скарбницю БУДЬ-ЯКОЇ організації; тепер super_admin бачить рівно ту, в
  # яку перемкнувся, і по тому самому правилу, що всі.
  #
  # 🔴 Знімати цю гілку МОЖНА ЛИШЕ ПАРОЮ зі `Scope` — вони одна конструкція. Звузити
  # сам `Scope` й лишити її тут = `wallets#index` віддає лише свою організацію, а
  # `GET /wallets/:id` і далі будь-чию, бо контролер вантажить запис голим
  # `Wallet.find(params[:id])` (три екшени: show/balance/metadata). Це фікс, що
  # відвантажується з ілюзією ізоляції — рівно та форма, від якої цей файл уже
  # лікували в SEC.16, тільки роллю вище.
  def show?
    same_organization?(record.organization_id) ||
      same_organization?(record.tree&.cluster&.organization_id)
  end

  def balance?
    show?
  end

  def metadata?
    show?
  end

  # [I18N.2] Комірка статусу транзакції — той самий обʼєкт і те саме право, що
  # сторінка гаманця. Окремого правила для транзакції СВІДОМО немає: воно було б
  # другим означенням тенантності поруч із `show?`, а ці двоє вже мають прецедент
  # розходження (`BlockchainTransactionsController#find_transaction` скоупить лише
  # через `wallet → tree → cluster`, тоді як `show?` приймає ще й пряме
  # `wallet.organization_id`).
  def transaction_status?
    show?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      scope.where(organization_id: organization_id)
    end
  end
end
