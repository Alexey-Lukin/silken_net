# frozen_string_literal: true

class PeaqRegistrationWorker
  include Sidekiq::Job
  sidekiq_options queue: "web3", retry: 5

  def perform(tree_id)
    tree = Tree.find_by(id: tree_id)
    return Rails.logger.error "🛑 [peaq DID] Дерево ##{tree_id} не знайдено." unless tree
    return Rails.logger.info "✅ [peaq DID] Дерево #{tree.did} вже має peaq DID: #{tree.peaq_did}" if tree.peaq_did.present?

    service = Peaq::DidRegistryService.new(tree)
    peaq_did = service.register!

    tree.with_lock do
      return Rails.logger.info "✅ [peaq DID] Дерево #{tree.did} вже має peaq DID: #{tree.peaq_did}" if tree.peaq_did.present?

      tree.update!(peaq_did: peaq_did)
    end

    Rails.logger.info "🌿 [peaq DID] Дерево #{tree.did} отримало DID: #{peaq_did}"
  rescue Peaq::DidRegistryService::RegistrationError => e
    Rails.logger.error "🚨 [peaq DID] Реєстрація для дерева ##{tree_id} зазнала невдачі: #{e.message}"
    raise e
  end
end
