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

      metadata = {
        type: "tree",
        tree_id: @tree.id,
        cluster_id: @tree.cluster_id,
        registered_at: Time.current.iso8601
      }

      body = {
        did: did_string,
        device_id: @tree.did,
        metadata: metadata
      }

      # peaq — Substrate-мережа, що використовує Ed25519 для підпису транзакцій.
      # Підписуємо DID-документ для криптографічного підтвердження автентичності.
      # Гем `eth` (secp256k1) тут не підходить — потрібен `ed25519`.
      peaq_signing_key = Rails.application.credentials.peaq_signing_key
      if peaq_signing_key.present?
        begin
          signature = Ed25519Crypto::SigningService.sign(peaq_signing_key, did_string)
          public_key = Ed25519Crypto::SigningService.public_key_from_seed(peaq_signing_key)
        rescue Ed25519Crypto::SigningService::SigningError => e
          raise RegistrationError, "Invalid peaq_signing_key in credentials: #{e.message}"
        end
        body[:proof] = {
          type: "Ed25519Signature2020",
          verification_method: "#{did_string}#key-1",
          signature: signature,
          public_key: public_key
        }
      end

      Web3::HttpClient.post("#{node_url}/did/register",
        body: body,
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
