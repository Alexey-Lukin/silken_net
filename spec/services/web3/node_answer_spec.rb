# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# 🗣️ [ARCH.62, 2026-09-23] Один дім питання «вузол відповів про НАШ запит ⊥ провайдер
# зламався». Межа між двома множинами — безпека: REJECTED → безпечний `fail!`/re-send,
# ALREADY_SUBMITTED → ambiguous (tx могла полетіти), ніколи сліпий re-send.
RSpec.describe Web3::NodeAnswer do
  def rpc(message) = Eth::Client::RpcError.new(message, nil, -32_000)

  describe ".rejected?" do
    [
      "execution reverted: SafeERC20: transfer failed",
      "insufficient funds for gas * price + value",
      "Transaction gas limit is too low, try 74494!", # Amoy дослівно, 2026-09-05
      "exceeds block gas limit",
      "intrinsic gas too low",
      "gas required exceeds allowance (30000000)",
      "invalid sender",
      "out of gas"
    ].each do |message|
      it "reads «#{message}» as a pre-broadcast rejection" do
        expect(described_class.rejected?(rpc(message))).to be true
      end
    end

    # Наш власний гард мусить читатись як вирок ноди — інакше він сам виробляє лімб.
    it "judges the TEXT, not the class — our own insufficient-funds guard counts" do
      expect(described_class.rejected?(Web3::KeySigner::InsufficientGasReserve.new("insufficient funds для ЦІЄЇ транзакції"))).to be true
    end

    # Межа double-spend тримається РІШЕННЯМ, а не даними: будь-який текст множини
    # ALREADY_SUBMITTED — і той, що збігся б з ОБОМА, — ніколи не «безпечний fail».
    [
      "nonce too low",
      "already known",
      "replacement transaction underpriced",
      "already imported",
      "replacement transaction underpriced: insufficient funds for gas * price + value"
    ].each do |message|
      it "does NOT read «#{message}» as a rejection (double-spend boundary)" do
        expect(described_class.rejected?(rpc(message))).to be false
      end
    end

    # Вузли пишуть по-різному: регістр і голе «revert» (без «execution») — теж відмови.
    it "matches case-insensitively and the bare «revert» form" do
      expect(described_class.rejected?(rpc("Execution Reverted"))).to be true
      expect(described_class.rejected?(rpc("VM Exception while processing transaction: revert"))).to be true
    end
  end

  describe ".already_submitted?" do
    %w[nonce\ too\ low already\ known replacement\ transaction\ underpriced already\ imported].each do |message|
      it "reads «#{message}» as ambiguous" do
        expect(described_class.already_submitted?(rpc(message))).to be true
      end
    end
  end

  describe ".answered?" do
    it "is true for a node's JSON-RPC answer about our request" do
      expect(described_class.answered?(rpc("execution reverted"))).to be true
      expect(described_class.answered?(rpc("nonce too low"))).to be true
    end

    it "finds the node answer through a wrapping error's cause chain" do
      wrapped = begin
        begin
          raise rpc("insufficient funds for gas * price + value")
        rescue Eth::Client::RpcError
          raise StandardError, "DispatchError"
        end
      rescue StandardError => e
        e
      end

      expect(described_class.answered?(wrapped)).to be true
    end

    # Allowlist: невідома JSON-RPC-помилка лишається провайдерською — шлюз, що вже переслав
    # tx, теж відповідає JSON-RPC-помилкою (гоча `web3-pipeline` #40).
    it "is false for a JSON-RPC error that is not about our request" do
      expect(described_class.answered?(rpc("upstream request timeout"))).to be false
      expect(described_class.answered?(rpc("header not found"))).to be false
    end

    # Відповідь є лише тоді, коли вузол її ДАВ: той самий текст без JSON-RPC-обʼєкта —
    # не свідчення про здоровʼя провайдера.
    # Транспортний збій, піднятий усередині rescue відповіді, лишається ЗБОЄМ: найближча
    # мережева причина — транспорт, а не відповідь.
    it "is false for a transport error whose cause is a node answer" do
      timeout = begin
        begin
          raise rpc("execution reverted")
        rescue Eth::Client::RpcError
          raise Net::ReadTimeout
        end
      rescue Net::ReadTimeout => e
        e
      end

      expect(described_class.answered?(timeout)).to be false
    end

    it "is false for a transport error even when its text looks like an answer" do
      expect(described_class.answered?(IOError.new("insufficient funds"))).to be false
      expect(described_class.answered?(nil)).to be false
    end
  end
end
