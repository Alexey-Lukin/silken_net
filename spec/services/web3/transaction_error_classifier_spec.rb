# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# [SEC.18 / DPIA M6] Інваріант, заради якого класифікатор існує: НАЗОВНІ не
# виходить жодного байта вхідного тексту. Тому головний приклад тут — не
# «чи правильний код», а «чи не витік підрядок» (`returns_no_input_fragment`).
RSpec.describe Web3::TransactionErrorClassifier do
  describe ".classify" do
    it "повертає :none на порожньому вході (nil / \"\" / пробіли)" do
      expect(described_class.classify(nil)).to eq(:none)
      expect(described_class.classify("")).to eq(:none)
      expect(described_class.classify("   ")).to eq(:none)
    end

    it "класифікує double-spend-лімбо як :broadcast_ambiguous — ПЕРЕД evm_revert" do
      # Реальні рядки з money-path (blockchain_minting_service / burning_service).
      expect(described_class.classify("Ambiguous mint broadcast — звір Polygonscan")).to eq(:broadcast_ambiguous)
      expect(described_class.classify("Крах після broadcast — звір Polygonscan ПЕРЕД re-mint")).to eq(:broadcast_ambiguous)
      expect(described_class.classify("Slash міг піти в мемпул до збою")).to eq(:broadcast_ambiguous)
    end

    it "пріоритет несучий: рядок, що містить ОБИДВА маркери, лишається ambiguous" do
      # Інакше найдорожчий стан money-path (кошти заблоковані, ланцюг невідомий)
      # занижувався б до звичайного реверту.
      expect(described_class.classify("ambiguous broadcast after execution reverted")).to eq(:broadcast_ambiguous)
    end

    it "розрізняє решту відомих родів відмови" do
      expect(described_class.classify("insufficient funds for gas")).to eq(:insufficient_funds)
      expect(described_class.classify("EVM Revert: Транзакція відхилена мережею")).to eq(:evm_revert)
      expect(described_class.classify("Slash lock-timeout: Kredis::LockTimeout")).to eq(:lock_timeout)
      expect(described_class.classify("Celo rejected: nonce too low")).to eq(:rpc_rejected)
      expect(described_class.classify("INS.2 reserve-gate hold (aggregate_cap)")).to eq(:reserve_hold)
      expect(described_class.classify("stuck in :sent past 6 hours")).to eq(:stuck_timeout)
      expect(described_class.classify("stale unconfirmed reward")).to eq(:stale_unconfirmed)
    end

    it "невідоме падає в :unknown — fail-CLOSED, а не «пропустити як є»" do
      expect(described_class.classify("Ковбаса з несподіваним текстом чужого сервісу")).to eq(:unknown)
      expect(described_class.classify("<html><body>502 Bad Gateway</body></html>")).to eq(:unknown)
    end

    # 🔴 Головний пін класу. Мутація, що ламає САМЕ його: повернути з `classify`
    # будь-який фрагмент входу (напр. `text[0, 40]`) замість символу.
    it "НІКОЛИ не повертає фрагмент входу — навіть для впізнаного роду" do
      pii = "user bogdan.melnyk@example.com at https://user:s3cret@rpc.example/eth reverted"

      code = described_class.classify(pii)

      expect(code).to be_a(Symbol)
      expect(described_class::RULES.map(&:first) + %i[none unknown]).to include(code)
      # Позитивний контроль недостатній — пінимо ВІДСУТНІСТЬ кожного носія PII.
      expect(code.to_s).not_to include("@")
      expect(code.to_s).not_to include("bogdan")
      expect(code.to_s).not_to include("s3cret")
      expect(code.to_s).not_to include("example.com")
    end

    it "коди — замкнена множина, тож нова гілка не може розширити її мовчки" do
      # Пін на РОЗМІР множини: додавання правила без оновлення цього числа
      # червонить — саме тому, що кожен новий код виходить у незворотний пін.
      expect(described_class::RULES.size).to eq(8)
      expect(described_class::RULES.map(&:first).uniq.size).to eq(8)
    end
  end
end
