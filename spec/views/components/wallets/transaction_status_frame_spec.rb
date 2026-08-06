# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# 🔴 Ця спека — ЄДИНИЙ автоматичний доказ інваріанта `04_04 §8.1а` для леджера
# гаманця, і це не риторика: `broadcast_payload_invariance_spec` рахує `t()` лише
# у ВЛАСНОМУ джерелі broadcast-компонента й свідомо не ходить у дочірні (стеля
# названа в його шапці). `Wallets::TransactionRow` має нуль `t()` і мав би їх нуль
# навіть із дротованим бейджем усередині — тобто порушення лишилось би ТИХИМ.
# Тому доказ довелось СТВОРИТИ, а не успадкувати від гейта.
RSpec.describe Wallets::TransactionStatusFrame do
  def tx(status: "confirmed", id: 42)
    record = BlockchainTransaction.new(status: status, token_type: "carbon_coin", amount: "1")
    record.id = id
    record
  end

  describe "the page/response side (no src)" do
    let(:html) { render_component(tx: tx) }

    it "wraps the shared badge in a frame that carries no src" do
      expect(html).to include(%(id="tx_status_frame_42"))
      expect(html).to include(Views::Shared::UI::StatusBadge.new(status: "confirmed").call)
      expect(html).not_to include("src=")
    end

    # ⚠️ Не «щоб не було нескінченного циклу»: Turbo розпізнає фрейм, чий `src`
    # вказує на себе, кидає `references itself` у консоль і лишає фрейм ПОРОЖНІМ.
    # Тобто ціна помилки — назавжди порожня комірка й тиха помилка, а не шторм
    # запитів; помилка тихіша, ніж здається, і тому небезпечніша.
    it "keeps the frame id apart from the badge id inside it" do
      expect(described_class.dom_id(42)).to eq("tx_status_frame_42")
      expect(html.scan(%(id="tx_status_frame_42")).size).to eq(1)
    end

    it "translates the badge — this side runs in the viewer's request" do
      uk = I18n.with_locale(:uk) { render_component(tx: tx) }

      expect(uk).not_to eq(render_component(tx: tx))
    end
  end

  describe Wallets::TransactionStatusFrameStub do
    subject(:stub_html) { described_class.new(tx_id: 42, src: "/wallets/1/transactions/42/status").call }

    it "renders an eager frame with the SAME id and a src" do
      expect(stub_html).to include(%(id="tx_status_frame_42"))
      expect(stub_html).to include(%(src="/wallets/1/transactions/42/status"))
      expect(stub_html).to include(%(loading="eager"))
    end

    # Це і є весь сенс класу 2: payload той самий у будь-якій локалі, тож ціна
    # live-оновлення росте з ГЛЯДАЧАМИ, ніколи з каталогом мов (`04_04 §8.1а`).
    # ⚠️ Приклад несучий саме тому, що сусід (фрейм) навмисно РІЗНИЙ у різних
    # локалях — без цієї пари не видно, що границя проходить рівно тут.
    it "renders byte-identically in every configured locale" do
      renders = I18n.available_locales.map do |locale|
        I18n.with_locale(locale) { described_class.new(tx_id: 42, src: "/x").call }
      end

      expect(renders.uniq.size).to eq(1)
    end

    # Плейсхолдер мусить ТРИМАТИ МІСЦЕ бейджа: порожній фрейм смикає висоту рядка
    # на кожне оновлення статусу. Готовий `Views::Shared::UI::Skeleton` тут не
    # годиться — він локалізований (`t(".loading")`), тобто повернув би в payload
    # рівно те, що клас 2 звідти прибирає.
    it "holds the badge's space without carrying a single word" do
      expect(stub_html).to include("animate-pulse")
      expect(stub_html).to match(/\bw-\d+\b/)
      expect(stub_html).to match(/\bh-\d+\b/)
      expect(stub_html).not_to match(/>[^<>]*\p{L}[^<>]*</)
    end
  end
end
