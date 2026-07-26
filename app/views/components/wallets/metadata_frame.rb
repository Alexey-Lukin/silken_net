# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Wallets
  class MetadataFrame < ApplicationComponent
    def initialize(wallet:)
      @wallet = wallet
    end

    def view_template
      turbo_frame_tag "wallet_metadata_frame_#{@wallet.id}" do
        render_wallet_metadata
      end
    end

    private

    def render_wallet_metadata
      div(class: "p-6 border border-emerald-900 bg-black shadow-xl") do
        h3(class: "text-tiny uppercase tracking-widest text-emerald-700 mb-6") { t(".title") }
        div(class: "space-y-4 font-mono text-tiny") do
          div do
            p(class: "text-gray-600 mb-1 uppercase") { t(".polygon_address") }
            if @wallet.crypto_public_address.present?
              render Views::Shared::Web3::Address.new(address: @wallet.crypto_public_address)
            else
              p(class: "text-gaia-text-muted italic") { t(".not_provisioned") }
            end
          end
          div do
            p(class: "text-gray-600 mb-1 uppercase") { t(".network") }
            p(class: "text-white") { t(".polygon_mainnet") }
          end
          div(class: "pt-3 border-t border-emerald-900/30") do
            p(class: "text-gaia-text-muted mb-1 uppercase") { t(".locked_balance") }
            p(class: "text-status-warning-text") { "#{@wallet.locked_balance.to_f.round(4)} SCC" }
          end
          div do
            p(class: "text-gaia-text-muted mb-1 uppercase") { t(".available_balance") }
            p(class: "text-gaia-primary") { "#{@wallet.available_balance.to_f.round(4)} SCC" }
          end
          div do
            p(class: "text-gaia-text-muted mb-1 uppercase") { t(".esg_retired") }
            p(class: "text-gaia-text-muted") { "#{@wallet.esg_retired_balance.to_f.round(4)} SCC" }
          end
        end
      end
    end
  end
end
