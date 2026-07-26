# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Web3
  # [ARCH.50] Pure EVM receipt tri-state classifier — One-Home, shared by
  # `MintingRollbackService` (Polygon/Celo rollback reconcile) and
  # `CeloConfirmationWorker` (Celo reward reconcile).
  #
  # The eth gem (0.5.x) returns the full JSON-RPC envelope:
  #   `{ "id" => ..., "jsonrpc" => "2.0", "result" => { "status" => "0x1", ... } }`.
  # A nil / empty `result` means the tx is still in the mempool (→ :pending).
  # Accepts both the wrapped envelope and a flat `{ "status" => ... }` (legacy fixtures).
  module EvmReceiptClassifier
    module_function

    def classify(envelope)
      return :pending if envelope.nil? || envelope == {}

      receipt = envelope.is_a?(Hash) && envelope.key?("result") ? envelope["result"] : envelope
      return :pending if receipt.nil? || receipt == {}

      status = receipt["status"]
      if status == "0x1" || status == 1 || status == "0x01"
        :confirmed
      elsif status.nil?
        :pending
      else
        :reverted
      end
    end
  end
end
