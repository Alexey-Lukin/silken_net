# frozen_string_literal: true

require "net/http"
require "json"

module TheGraph
  class QueryService
    TIMEOUT_OPEN = 5   # seconds
    TIMEOUT_READ = 10  # seconds

    class QueryError < StandardError; end

    # Повертає загальну суму замінченого вуглецю (SCC) з The Graph subgraph.
    # Запитує останні 100 подій CarbonMinted та сумує amount.
    def fetch_total_carbon_minted
      api_url = Rails.application.credentials.the_graph_api_url
      raise QueryError, "the_graph_api_url не налаштовано в credentials" if api_url.blank?

      query = <<~GRAPHQL
        {
          carbonMintEvents(first: 100, orderBy: timestamp, orderDirection: desc) {
            id
            to
            amount
            treeDid
            timestamp
          }
        }
      GRAPHQL

      response = execute_query(api_url, query)
      data = JSON.parse(response.body)

      events = data.dig("data", "carbonMintEvents") || []
      events.sum { |e| e["amount"].to_i }
    rescue QueryError
      raise
    rescue JSON::ParserError => e
      raise QueryError, "Невалідна відповідь від The Graph: #{e.message}"
    rescue StandardError => e
      raise QueryError, "Збій зв'язку з The Graph: #{e.message}"
    end

    private

    def execute_query(api_url, query)
      uri = URI.parse(api_url)

      request = Net::HTTP::Post.new(uri, {
        "Content-Type" => "application/json"
      })
      request.body = { query: query }.to_json

      response = Net::HTTP.start(
        uri.hostname, uri.port,
        use_ssl: uri.scheme == "https",
        open_timeout: TIMEOUT_OPEN,
        read_timeout: TIMEOUT_READ
      ) { |http| http.request(request) }

      unless response.is_a?(Net::HTTPSuccess)
        raise QueryError, "The Graph повернув #{response.code}: #{response.body}"
      end

      response
    end
  end
end
