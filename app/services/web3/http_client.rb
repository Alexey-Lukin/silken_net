# frozen_string_literal: true

require "net/http"
require "json"

module Web3
  # = ===================================================================
  # 🌐 HTTP CLIENT (Shared HTTP Utility for External API Services)
  # = ===================================================================
  # Централізована утиліта для всіх HTTP-запитів до зовнішніх API:
  # IPFS/Filecoin, IoTeX W3bstream, Streamr, Polygon Hadron, The Graph,
  # peaq DID, Solana JSON RPC.
  #
  # Забезпечує:
  # - Уніфіковані таймаути з конфігурацією per-service
  # - Автоматичне SSL для HTTPS
  # - Стандартну обробку помилок (таймаути, HTTP-коди, JSON-парсинг)
  # - Єдиний формат логування помилок
  #
  # Використання:
  #   response = Web3::HttpClient.post(url,
  #     body: payload,
  #     headers: { "Authorization" => "Bearer #{api_key}" },
  #     open_timeout: 10,
  #     read_timeout: 30,
  #     service_name: "Filecoin"
  #   )
  #   data = response.parsed_body # parsed JSON
  module HttpClient
    DEFAULT_OPEN_TIMEOUT = 10
    DEFAULT_READ_TIMEOUT = 30

    class RequestError < StandardError; end

    class << self
      # Виконує HTTP POST запит з JSON body.
      #
      # @param url [String] повний URL endpoint
      # @param body [Hash] тіло запиту (буде серіалізовано у JSON)
      # @param headers [Hash] додаткові HTTP заголовки
      # @param open_timeout [Integer] таймаут на з'єднання (секунди)
      # @param read_timeout [Integer] таймаут на відповідь (секунди)
      # @param service_name [String] ім'я сервісу для логування помилок
      # @return [Response] обгортка з body та parsed_body
      def post(url, body:, headers: {}, open_timeout: DEFAULT_OPEN_TIMEOUT, read_timeout: DEFAULT_READ_TIMEOUT, service_name: "HTTP")
        uri = URI.parse(url)

        request = Net::HTTP::Post.new(uri)
        request["Content-Type"] = "application/json"
        headers.each { |k, v| request[k] = v }
        request.body = JSON.generate(body)

        execute(uri, request, open_timeout:, read_timeout:, service_name:)
      end

      # Виконує HTTP GET запит.
      #
      # @param url [String] повний URL endpoint
      # @param headers [Hash] додаткові HTTP заголовки
      # @param open_timeout [Integer] таймаут на з'єднання (секунди)
      # @param read_timeout [Integer] таймаут на відповідь (секунди)
      # @param service_name [String] ім'я сервісу для логування помилок
      # @return [Response] обгортка з body та parsed_body
      def get(url, headers: {}, open_timeout: DEFAULT_OPEN_TIMEOUT, read_timeout: DEFAULT_READ_TIMEOUT, service_name: "HTTP")
        uri = URI.parse(url)

        request = Net::HTTP::Get.new(uri)
        headers.each { |k, v| request[k] = v }

        execute(uri, request, open_timeout:, read_timeout:, service_name:)
      end

      private

      def execute(uri, request, open_timeout:, read_timeout:, service_name:)
        response = Net::HTTP.start(
          uri.hostname, uri.port,
          use_ssl: uri.scheme == "https",
          open_timeout: open_timeout,
          read_timeout: read_timeout
        ) { |http| http.request(request) }

        unless response.is_a?(Net::HTTPSuccess)
          raise RequestError, "#{service_name} API returned #{response.code}: #{response.body}"
        end

        Response.new(response.body)
      rescue Net::OpenTimeout, Net::ReadTimeout => e
        Rails.logger.error "🛑 [#{service_name}] Timeout: #{e.message}"
        raise RequestError, "#{service_name} Timeout: #{e.message}"
      rescue RequestError
        raise
      rescue StandardError => e
        raise RequestError, "#{service_name} connection error: #{e.message}"
      end
    end

    # Lightweight wrapper for HTTP response with lazy JSON parsing
    class Response
      attr_reader :body

      def initialize(body)
        @body = body
      end

      def parsed_body
        @parsed_body ||= JSON.parse(@body)
      rescue JSON::ParserError => e
        raise RequestError, "Invalid JSON response: #{e.message}"
      end
    end
  end
end
