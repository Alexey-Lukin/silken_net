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

      uri = URI.parse("#{node_url}/did/register")
      request = Net::HTTP::Post.new(uri, "Content-Type" => "application/json")
      request.body = {
        did: did_string,
        device_id: @tree.did,
        metadata: {
          type: "tree",
          tree_id: @tree.id,
          cluster_id: @tree.cluster_id,
          registered_at: Time.current.iso8601
        }
      }.to_json

      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https", open_timeout: 10, read_timeout: 30) do |http|
        http.request(request)
      end

      unless response.is_a?(Net::HTTPSuccess)
        raise RegistrationError, "peaq node повернув #{response.code}: #{response.body}"
      end

      Rails.logger.info "🌳 [peaq DID] Зареєстровано #{did_string} для дерева #{@tree.did}"
    rescue RegistrationError
      raise
    rescue StandardError => e
      raise RegistrationError, "Збій зв'язку з peaq node: #{e.message}"
    end
  end
end
