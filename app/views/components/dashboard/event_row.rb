# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Dashboard
  class EventRow < ApplicationComponent
    def initialize(event:)
      @event = event
    end

    def view_template
      div(class: "flex items-start gap-4 border-l border-gaia-border pl-4 py-1") do
        div(class: "flex flex-col flex-1 font-mono text-tiny") do
          span(class: "text-gaia-text-subtle text-micro mb-1") { time_ago_text }
          span(class: tokens("leading-relaxed", event_color)) { event_summary }
        end
      end
    end

    private

    def event_summary
      case @event
      # Сире значення enum'а, інтерпольоване в ПЕРЕКЛАДЕНЕ речення, — гірший
      # різновид промаху: фраза виглядає локалізованою, а всередині англійський
      # токен. Мітку бере той самий TextFormatter, що й `Alerts::Row`.
      when EwsAlert then t(".threat", type: TreeChronicle::TextFormatter.alert_title(@event), cluster: @event.cluster&.name || t(".unknown_cluster"))
      when BlockchainTransaction then blockchain_transaction_summary
      when MaintenanceRecord then t(".maintenance", action: @event.action_type_label, user: @event.user&.first_name || t(".system_user"))
      else t(".system_pulse")
      end
    end

    def event_color
      case @event
      when EwsAlert then "text-status-danger-accent"
      # [ARCH.101 ⚖️ 08-20] Спалення гучне й КОЛЬОРОМ: дієслово «Burned» уже чесне,
      # але колір читається раніше за текст, і нейтральний тон ховав найгучнішу
      # грошову подію серед буденних. `-accent` міряний для текст-ролі на
      # gaia-поверхнях обох тем.
      when BlockchainTransaction then @event.burn? ? "text-status-danger-accent" : "text-gaia-text"
      when MaintenanceRecord then "text-status-warning-text"
      else "text-gaia-text-subtle"
      end
    end

    def time_ago_text
      render Views::Shared::UI::RelativeTime.new(datetime: @event.created_at)
    end

    # Один грошовий рядок несе ТРИ властивості, і жодна не видна з імені колонки:
    # ТІКЕР (`token_type` має три значення — дім `#ticker`), НАПРЯМОК (деривація з
    # `sourceable_type`, дім `#burn?` — знак `amount` його НЕ видає, slash-інтент
    # пишеться додатним) і ДЖЕРЕЛО (гаманцеве дерево АБО кластер). Доти всі три
    # були зашиті в одне речення, тож спалення друкувалось емісією, cUSD-винагорода
    # — «SCC», а кластерне джерело — «System».
    def blockchain_transaction_summary
      sourceable = @event.sourceable
      if sourceable.is_a?(ParametricInsurance) && sourceable.uses_etherisc?
        t(".etherisc_claim", amount: @event.amount, address: short_address(@event.to_address))
      elsif @event.burn?
        t(".burned", amount: @event.amount, ticker: @event.ticker, target: event_target)
      else
        t(".minted", amount: @event.amount, ticker: @event.ticker, target: event_target)
      end
    end

    # Провенанс резолвиться ТІЄЮ САМОЮ парою, що й приналежність організації
    # (`BlockchainTransaction.for_organization`, [ARCH.98]): гаманець → дерево,
    # інакше кластер. Прецедент форми — `Alerts::Row`, де кластер і DID стоять в
    # одній комірці. Третя гілка лишається fail-open: рядок без обох координат
    # `for_organization` не бачить, тож на цьому екрані вона недосяжна.
    def event_target
      @event.wallet&.tree&.did || @event.cluster&.name || t(".system_user")
    end

    def short_address(address)
      return t(".pool") unless address.present? && address.length > 10

      "#{address[0..5]}…#{address[-4..]}"
    end
  end
end
