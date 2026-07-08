# frozen_string_literal: true

# [ARCH.66 companion — nonce-persist проти F2a double-send] Персистимо nonce broadcast'у ДО
# `transact()`, тож crash між broadcast і `update!(:sent)` не примушує resume фетчити НОВИЙ
# авто-nonce (pending-count уже врахував би завислий tx → nonce+1 = другий незалежний on-chain
# запис). Persisted nonce → resume ре-броадкастить на ТОМУ Ж слоті (same-nonce = replace/reject,
# не N+1). Nullable, без default → safe metadata-only ALTER; bigint = дзеркало block_number/gas_used.
class AddNonceToEthereumAnchors < ActiveRecord::Migration[8.1]
  def change
    add_column :ethereum_anchors, :nonce, :bigint, null: true
  end
end
