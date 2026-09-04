# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

class PeaqRegistrationWorker
  include ApplicationWeb3Worker
  sidekiq_options queue: "web3", retry: 5

  def perform(tree_id)
    # [ARCH.119] Другий гейт тієї самої ноги, і він не дубль: enqueue-гард стереже
    # МАЙБУТНІ джоби, а цей дренажить ті, що вже лежать у Redis (retry-set/queue) з
    # доби до гейта. Форма — `Iotex::VerificationWorker`: WARN і вихід, ніколи raise.
    unless Peaq::DidRegistryService.configured?
      return Rails.logger.warn "⏸️ [peaq DID] Нога не сконфігурована (PEAQ_NODE_URL/PEAQ_SIGNING_KEY) — " \
                               "Tree ##{tree_id} лишається без DID до активації; ре-арм — PeaqBackfillWorker (06_08 §2.2)."
    end

    tree = Tree.find_by(id: tree_id)
    return Rails.logger.error "🛑 [peaq DID] Дерево ##{tree_id} не знайдено." unless tree
    return Rails.logger.info "✅ [peaq DID] Дерево #{tree.did} вже має peaq DID: #{tree.peaq_did}" if tree.peaq_did.present?

    peaq_did = with_web3_error_handling("peaq", "Tree ##{tree_id}") do
      service = Peaq::DidRegistryService.new(tree)
      service.register!
    end

    tree.with_lock do
      return Rails.logger.info "✅ [peaq DID] Дерево #{tree.did} вже має peaq DID: #{tree.peaq_did}" if tree.peaq_did.present?

      tree.update!(peaq_did: peaq_did)
    end

    Rails.logger.info "🌿 [peaq DID] Дерево #{tree.did} отримало DID: #{peaq_did}"
  rescue Peaq::DidRegistryService::RegistrationError => e
    Rails.logger.error "🚨 [peaq DID] Реєстрація для дерева ##{tree_id} зазнала невдачі: #{e.message}"
    raise
  end
end
