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
      div(class: "p-6 border border-gaia-border bg-gaia-surface shadow-xl") do
        h3(class: "text-tiny uppercase tracking-widest text-gaia-text-muted mb-6") { t(".title") }
        div(class: "space-y-4 font-mono text-tiny") do
          div do
            p(class: "text-gaia-text-muted mb-1 uppercase") { t(".polygon_address") }
            if @wallet.crypto_public_address.present?
              render Views::Shared::Web3::Address.new(address: @wallet.crypto_public_address)
            else
              p(class: "text-gaia-text-muted italic") { t(".not_provisioned") }
            end
          end
          div do
            p(class: "text-gaia-text-muted mb-1 uppercase") { t(".network") }
            p(class: "text-gaia-text-strong") { t(".polygon_mainnet") }
          end
          # [ARCH.88] Дві величини нижче — БАЛИ росту (locked/available живуть у тій
          # самій колонковій родині, що й `balance`), тож тікер монети там знято.
          # 🔴 [ARCH.95] `esg_retired` із цієї трійки ВИБУВ: він рахує погашені МОНЕТИ,
          # і саме тому несе власний тікер. Доти цей коментар стверджував «усі три»,
          # а суфікс друкував `GP` над величиною, яку `00_04` двічі називає SCC —
          # тобто екран сперечався з юр-домом, що росте в MSA/SLA.
          div(class: "pt-3 border-t border-gaia-border") do
            p(class: "text-gaia-text-muted mb-1 uppercase") { t(".locked_balance") }
            p(class: "text-status-warning-text") { "#{formatted_points(@wallet.locked_balance)} #{t('.unit')}" }
          end
          div do
            p(class: "text-gaia-text-muted mb-1 uppercase") { t(".available_balance") }
            p(class: "text-gaia-primary-strong") { "#{formatted_points(@wallet.available_balance)} #{t('.unit')}" }
          end
          div do
            p(class: "text-gaia-text-muted mb-1 uppercase") { t(".esg_retired") }
            p(class: "text-gaia-text-muted") { "#{formatted_amount(@wallet.esg_retired_balance)} #{t('.coin_unit')}" }
          end
        end
      end
    end
  end
end
