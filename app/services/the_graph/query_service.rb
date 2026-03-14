# frozen_string_literal: true

module TheGraph
  class QueryService
    TIMEOUT_OPEN = 5   # seconds
    TIMEOUT_READ = 10  # seconds

    class QueryError < StandardError; end

    # Повертає загальну суму замінченого вуглецю (SCC) з The Graph subgraph.
    # Запитує останні 100 подій CarbonMinted та сумує amount.
    def fetch_total_carbon_minted
      api_url = validated_api_url

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
      data = response.parsed_body

      events = data.dig("data", "carbonMintEvents") || []
      events.sum { |e| e["amount"].to_i }
    rescue QueryError
      raise
    rescue Web3::HttpClient::RequestError => e
      raise QueryError, e.message
    rescue StandardError => e
      raise QueryError, "Збій зв'язку з The Graph: #{e.message}"
    end

    # Повертає протокольні фінанси (totalMinted, totalBurned, totalPremiums)
    # з singleton-сутності ProtocolFinancials у The Graph subgraph.
    def fetch_protocol_financials
      api_url = validated_api_url

      query = <<~GRAPHQL
        {
          protocolFinancial(id: "1") {
            totalMinted
            totalBurned
            totalPremiums
          }
        }
      GRAPHQL

      response = execute_query(api_url, query)
      data = response.parsed_body

      financials = data.dig("data", "protocolFinancial") || {}
      {
        total_minted: financials["totalMinted"].to_i,
        total_burned: financials["totalBurned"].to_i,
        total_premiums: financials["totalPremiums"].to_i
      }
    rescue QueryError
      raise
    rescue Web3::HttpClient::RequestError => e
      raise QueryError, e.message
    rescue StandardError => e
      raise QueryError, "Збій зв'язку з The Graph: #{e.message}"
    end

    private

    def validated_api_url
      url = Rails.application.credentials.the_graph_api_url
      raise QueryError, "the_graph_api_url не налаштовано в credentials" if url.blank?

      url
    end

    def execute_query(api_url, query)
      Web3::HttpClient.post(api_url,
        body: { query: query },
        open_timeout: TIMEOUT_OPEN,
        read_timeout: TIMEOUT_READ,
        service_name: "The Graph"
      )
    end
  end
end
