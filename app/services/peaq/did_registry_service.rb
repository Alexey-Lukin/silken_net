# frozen_string_literal: true

module Peaq
  class DidRegistryService
    PEAQ_DID_PREFIX = "did:peaq:"

    class RegistrationError < StandardError; end

    def initialize(tree)
      @tree = tree
    end

    # Реєструє DID дерева в мережі peaq та повертає зареєстрований DID-рядок.
    def register!
      did_string = generate_did
      register_on_peaq(did_string)
      did_string
    end

    private

    def generate_did
      # Генерація peaq DID на основі апаратного ідентифікатора дерева (STM32 UID → hex digest)
      hardware_identifier = @tree.did
      hex_hash = Digest::SHA256.hexdigest("#{hardware_identifier}:#{@tree.id}:#{@tree.created_at.to_i}")
      "#{PEAQ_DID_PREFIX}0x#{hex_hash[0, 40]}"
    end

    def register_on_peaq(did_string)
      node_url = Rails.application.credentials.peaq_node_url
      raise RegistrationError, "peaq_node_url не налаштовано в credentials" unless node_url.present?

      Web3::HttpClient.post("#{node_url}/did/register",
        body: {
          did: did_string,
          device_id: @tree.did,
          metadata: {
            type: "tree",
            tree_id: @tree.id,
            cluster_id: @tree.cluster_id,
            registered_at: Time.current.iso8601
          }
        },
        open_timeout: 10,
        read_timeout: 30,
        service_name: "peaq DID"
      )

      Rails.logger.info "🌳 [peaq DID] Зареєстровано #{did_string} для дерева #{@tree.did}"
    rescue Web3::HttpClient::RequestError => e
      raise RegistrationError, e.message
    end
  end
end
