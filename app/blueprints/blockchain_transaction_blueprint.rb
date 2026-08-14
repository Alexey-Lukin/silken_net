# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

class BlockchainTransactionBlueprint < Blueprinter::Base
  identifier :id

  # 🔴 [ARCH.98] Провенанс резолвиться ДВОМА координатами, тож обидві мусять бути й
  # тут: cluster-sourced рухи (Celo-винагорода, слеш останнього дерева) живуть без
  # гаманця, і `tree_did` для них `null` ЗА ПОБУДОВОЮ. `tree_did` свідомо НЕ
  # перейменовано — це чинний контракт дроту, а не опис поля.
  # ⚠️ Пара тримається разом із HTML-коміркою «Джерело» саме тому, що один екшен
  # обслуговує обидва формати: добудова лише одного боку і є клас [ARCH.90].
  # 🔴 [ARCH.101] НАПРЯМОК мусить бути в контракті явно, і це не оздоба, а
  # повнота: `amount` валідовано `greater_than: 0`, тож slash-інтент їде
  # ДОДАТНИМ і знак напрямку не видає. Без цього поля машинний споживач —
  # інтегратор, аудитор, реєстр — не може відрізнити спалення від емісії на
  # поверхні, чиє призначення саме аудит.
  #
  # Дім деривації ОДИН — `#burn?` над `BURN_SOURCEABLE_TYPE`, той самий
  # дискримінатор, яким `net_minted_supply` розводить обидва боки в SQL
  # ([`04_01 §6`](../../docs/04_01_Data_Models_and_Entities.md)). Віддаємо
  # предикат, а не сирий `sourceable_type`: тип є деталлю реалізації, а
  # «спалення це чи ні» — питанням контракту.
  view :index do
    fields :amount, :token_type, :status, :tx_hash, :to_address, :created_at
    field(:explorer_url) { |tx| tx.explorer_url }
    field(:tree_did) { |tx| tx.wallet&.tree&.did }
    field(:cluster_name) { |tx| tx.cluster&.name }
    field(:burn) { |tx| tx.burn? }
  end

  view :show do
    fields :amount, :token_type, :status, :tx_hash, :to_address, :locked_points,
           :notes, :error_message, :created_at, :updated_at,
           :gas_price, :gas_used, :cumulative_gas_cost,
           :block_number, :nonce, :sent_at, :confirmed_at
    field(:explorer_url) { |tx| tx.explorer_url }
    field(:cluster_name) { |tx| tx.cluster&.name }
    field(:burn) { |tx| tx.burn? }
    association :wallet, blueprint: WalletBlueprint, view: :with_tree
  end
end
