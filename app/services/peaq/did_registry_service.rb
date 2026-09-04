# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Peaq
  class DidRegistryService
    PEAQ_DID_PREFIX = "did:peaq:"

    class RegistrationError < StandardError; end

    # [ARCH.119] ОДИН дім питання «чи нога жива» — ENV-first із credentials-фолбеком
    # (SEC.22). Обидва значення обовʼязкові: node_url без ключа однаково рейзить нижче.
    #
    # ⛔ Fail-closed raise у `register_on_peaq` НЕ є гардом для несконфігурованої ноги —
    # він є retry-драбиною: джоба не може ані виконатись, ані здатись, тож кожне
    # провіжнене дерево купує 6 гарантовано провальних виконань у черзі `web3`.
    # Гард мусить стояти на ENQUEUE, а не на виклику (прецеденти — `Filecoin::ArchiveService`,
    # `Iotex::W3bstreamVerificationService`). Sentry тиші не порушить: `RegistrationError`
    # стоїть в `excluded_exceptions`, тобто ціна — слоти Sidekiq і Redis-команди.
    #
    # 🔑 Пропуск нічого НЕ губить, і це ДИЗАЙН, а не щастя: `generate_did` детермінований
    # від (`tree.did`, `tree.id`, `tree.created_at`), тож ре-арм через місяці дає ТОЙ САМИЙ
    # DID. Маркером служить сама доменна колонка `trees.peaq_did IS NULL` — форма IoTeX,
    # окремої outbox-колонки не потрібно.
    #
    # ⚠️ Оголошена стеля ре-арму: вікна НЕМАЄ свідомо. DID є постійною ідентичністю, а не
    # предметом ретеншену (⊥ `IotexBackfillWorker::LOOKBACK_WINDOW`), тож дерево без DID
    # лишається кандидатом скільки б не минуло; стелю проходу тримає `BATCH_LIMIT`.
    def self.node_url
      ENV["PEAQ_NODE_URL"].presence || Rails.application.credentials.peaq_node_url
    end

    def self.signing_key
      ENV["PEAQ_SIGNING_KEY"].presence || Rails.application.credentials.peaq_signing_key
    end

    def self.configured?
      node_url.present? && signing_key.present?
    end

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
      node_url = self.class.node_url
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

      # [BLOCKER-08 FIX]: peaq_signing_key обов'язковий для W3C DID Core compliance.
      # Без Ed25519-підпису DID-документ не має криптографічного доказу автентичності.
      peaq_signing_key = self.class.signing_key
      raise RegistrationError, "peaq_signing_key обов'язковий у credentials для реєстрації DID (W3C DID Core spec)" if peaq_signing_key.blank?

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
