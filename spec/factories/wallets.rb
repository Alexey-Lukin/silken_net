# frozen_string_literal: true

FactoryBot.define do
  factory :wallet do
    tree
    organization { tree&.cluster&.organization }
    balance { 5000.0 }
    hadron_kyc_status { "approved" }
    sequence(:crypto_public_address) { |n| "0x#{'a' * 4}#{'%036x' % n}" }

    # [ARCH.56] Tree.after_create вже створює свій wallet (build_default_wallet),
    # а wallets.tree_id тепер unique — реюзаємо авто-створений замість дубля;
    # фабричні атрибути лягають поверх звичайними сеттерами.
    initialize_with { tree&.wallet || Wallet.new(tree: tree) }
  end
end
