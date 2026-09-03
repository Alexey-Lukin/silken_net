# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Web3
  # =========================================================================
  # 🔎 BLOCK-EXPLORER LINKS (INF.27 — the chain axis reaches the READ path)
  # =========================================================================
  # A tx link is not decoration on this system: `Mrv::LineageReportService`
  # hands `etherscan_url` to an AUDITOR as the reference for the L1 anchor of a
  # Merkle lineage proof. A link that resolves to "transaction not found" does
  # not read as "wrong environment" — it reads as "the anchor they claim does
  # not exist", i.e. it attacks exactly the leg of the mission criterion the
  # anchor was built to serve (00_01 §1.1, «правдиво»).
  #
  # 🔴 THE TWO HOMES SAT ON OPPOSITE SIDES OF THE AXIS, which is why neither
  # looked broken from the other:
  #   · `BlockchainTransaction#explorer_url` was hardcoded to TESTNETS
  #     (`?cluster=devnet`, `/alfajores/`) — already wrong today, on mainnet;
  #   · `EthereumAnchor#etherscan_url` was hardcoded to MAINNET — correct today,
  #     wrong the moment a testnet slot exists (which is what INF.27 builds).
  # Same geometry the RPC guard already documents for hardcoded fallbacks
  # (`Web3NetworkGuard#armed_path_violations`); this is that geometry on
  # the read path instead of the write path.
  #
  # 🏠 The axis is NOT new — `WEB3_CHAIN_ENV` is read through the same One-Home
  # (`Security::Web3NetworkGuard.chain_env`) that the two migrated money sites
  # use. Nothing here declares a chain; it only renders the slot's declaration.
  #
  # ⚠️ ALFAJORES IS GONE, and that is measured, not read off a changelog:
  # `alfajores-forno.celo-testnet.org` answers **NXDOMAIN** (2026-08-30, with
  # `forno.celo.org` responding `0xa4ec` in the same run as the positive
  # control), and `explorer.celo.org/alfajores/` 301s into Blockscout. cLabs
  # deprecated Baklava + Alfajores when Holesky sunset, migrating to Celo
  # Sepolia (`0xaa044c`, live). So the Celo testnet row points at Celo Sepolia,
  # and Blockscout is kept on both sides because `explorer.celo.org` — the host
  # our shipped code already used — now redirects there itself.
  # ✅ The RPC-side twins of that dead host are GONE since 2026-08-31 — and the ⚖️ resolved
  # to REMOVAL, not a repoint: `Celo::CommunityRewardService::DEFAULT_RPC_URL` and
  # `Treasury::MonitorService`'s `fallback_rpc` were deleted, so the Celo RPC path is
  # fail-closed. ⚠️ Note the asymmetry with THIS file: an explorer URL is a READ-side link,
  # so a wrong one misleads an auditor and is worth repointing; an RPC fallback is a WRITE
  # side that moves money, and there the honest fix is to have no default at all.
  #
  # 🔒 DECLARED CEILINGS — both are about what this module CANNOT know:
  #   1. `WEB3_CHAIN_ENV` says "testnet", never WHICH testnet. The rows below
  #      bind to the ones DEPLOY-DAY Фаза 2t actually names (Amoy · Sepolia ·
  #      Devnet) plus Celo Sepolia. Target a different testnet and the links go
  #      wrong SILENTLY — there is no per-row chain id to check them against.
  #   2. The slot declaration is process-wide, while the chain of a persisted
  #      row is a per-ROW fact. Safe today only because the slots hold separate
  #      databases (POSTGRES_DATABASE); restore a production dump onto a testnet
  #      slot and every link in it flips. That is a property of the axis, not a
  #      bug to patch here — a per-row chain id would be the real fix.
  # =========================================================================
  module Explorer
    # family → tx-URL template, per declared chain family. `%s` = tx hash.
    TX_URL = {
      "mainnet" => {
        evm: "https://polygonscan.com/tx/%s",
        solana: "https://explorer.solana.com/tx/%s",
        celo: "https://celo.blockscout.com/tx/%s",
        ethereum: "https://etherscan.io/tx/%s"
      }.freeze,
      "testnet" => {
        evm: "https://amoy.polygonscan.com/tx/%s",
        solana: "https://explorer.solana.com/tx/%s?cluster=devnet",
        celo: "https://celo-sepolia.blockscout.com/tx/%s",
        ethereum: "https://sepolia.etherscan.io/tx/%s"
      }.freeze
    }.freeze

    module_function

    # @param family [Symbol] :evm (Polygon) · :solana · :celo · :ethereum (L1)
    # @param tx_hash [String, nil]
    # @return [String, nil] nil when there is no hash to point at
    def tx_url(family, tx_hash)
      return nil if tx_hash.blank?

      format(template_for(family), tx_hash)
    end

    # An unrecognised declaration lands on `mainnet` — the SAME fail-closed
    # default the guard itself uses. It cannot normally get here (the guard
    # refuses to boot on a value outside mainnet/testnet), but a rescue boot
    # (`SILKENNET_SKIP_WEB3_NETWORK_GUARD=1`) can, and a KeyError rendering a
    # dashboard row would be a worse failure than a wrong link.
    def template_for(family)
      TX_URL.fetch(Security::Web3NetworkGuard.chain_env(ENV), TX_URL.fetch("mainnet"))
            .fetch(family.to_sym)
    end
  end
end
