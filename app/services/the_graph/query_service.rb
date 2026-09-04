# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module TheGraph
  class QueryService
    TIMEOUT_OPEN = 5   # seconds
    TIMEOUT_READ = 10  # seconds

    class QueryError < StandardError; end

    # [ARCH.119] ОДИН дім питання «чи нога жива» — ENV-first із credentials-фолбеком (SEC.22).
    #
    # ⚠️ Тут гейт купує НЕ те, що в сусідів по класу, і плутати ці дві вигоди шкідливо.
    # Ретрай-драбини на цьому шляху немає взагалі (синхронний read-only виклик усередині
    # `rescue`), тож слотів Sidekiq він не рятує. Купує він ДВІ інші речі, обидві виміряні:
    #
    #   1. РОЗРІЗНЮВАНІСТЬ. Без гейта «ключ не заведено» і «The Graph лежить» дають той
    #      самий деградований екран, а на дашборді — ще й той самий беззвучний `rescue`.
    #      Жодна змінна The Graph не стоїть на жодній деплой-поверхні, тож сьогодні це
    #      НЕ гіпотетичний стан, а єдиний наявний.
    #   2. ПРИГЛУШЕННЯ. `Rails.cache.fetch` не пише НІЧОГО, коли блок кинув, — виміряно:
    #      `exist?` після raise = false. Тобто несконфігурована нога рейзить на КОЖЕН
    #      запит, а не «раз на 5 хв», як читається з наявності TTL. Гейт, що повертає
    #      значення замість винятку, кешується (виміряно: блок біжить раз на TTL) і
    #      повертає деградації ту саму 5-хвилинну стелю, яку має успіх.
    #
    # ⛔ Outbox/ре-арм сюди НЕ копіювати (⊥ peaq/Filecoin): read-only шлях відновлювати
    # нема чого — наступний cache-miss спитає заново.
    def self.api_url
      ENV["THE_GRAPH_API_URL"].presence || Rails.application.credentials.the_graph_api_url
    end

    def self.configured?
      api_url.present?
    end

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

    # Повертає протокольні фінанси (totalMinted, totalBurned) з singleton-сутності
    # ProtocolFinancials у The Graph subgraph. Премії тут НЕ запитуються — вони
    # off-chain USDC-факт (NaasContract), джерело правди — БД (див. 05_03 / reports_controller).
    def fetch_protocol_financials
      api_url = validated_api_url

      query = <<~GRAPHQL
        {
          protocolFinancial(id: "1") {
            totalMinted
            totalBurned
          }
        }
      GRAPHQL

      response = execute_query(api_url, query)
      data = response.parsed_body

      financials = data.dig("data", "protocolFinancial") || {}
      {
        total_minted: financials["totalMinted"].to_i,
        total_burned: financials["totalBurned"].to_i
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
      url = self.class.api_url
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
