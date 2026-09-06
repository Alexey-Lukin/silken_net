# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# = ===================================================================
# 💰 treasury:balances — операторський ЗОНД oracle-гаманців
# = ===================================================================
#
# 🔴 [DEPLOY-1] ЧОМУ ЦЕЙ ФАЙЛ ІСНУЄ. Нога вимагала розрізнити ДВА вироки —
# `НЕ ПРОВІЖИНЕНО` (баланс рівно 0, з адреси не пішло жодної транзакції) ⊥
# `НИЖЧИЙ ЗА МІНІМУМ` (витрачено більше, ніж поповнено), — бо вони посилають
# оператора в протилежні боки: перший у кран, другий шукати витік. А ПРИЛАДУ,
# здатного це виміряти, у репо не було ЖОДНОГО: ні rake, ні скрипта, ні бінаря.
# Єдиний, хто читав баланси, — `TreasuryMonitorWorker` усередині Sidekiq, без
# операторського входу. Тобто рішення просили, а міряти було нічим.
#
# ⛔ **ЦЕ НЕ ОБГОРТКА НАД `Treasury::MonitorService.call`, І ЦЕ НЕСУЧЕ.** Той
# сервіс не є зондом: у тому ж проході він пише Prometheus-ґейджі, рахує
# money-path і payout-флоат, детектує mint-аномалію, **СТВОРЮЄ `EwsAlert`** і
# **ЗАКРИВАЄ** одужалі. Операторський «подивитись баланс» не сміє мутувати те,
# про що звітує (скіл `web3-pipeline` гоча 1a) — інакше сам акт діагностики
# міняє стан, який діагностують.
#
# ЩО ЦЕ РОБИТЬ: читає адресу через seam `Web3::OracleSigner.address_for` (для
# KMS-ролі — з ПУБЛІЧНОГО ключа HSM, тож зонд не стає останнім читачем
# приватного), а тоді `eth_getBalance` + `eth_getTransactionCount`. Нічого не пише.
#
# ⚠️ Мережу задає СЕРЕДОВИЩЕ, не прапорець: ті самі імена ENV на обох слотах, а
# canopy підмінює їх на testnet у `.kamal/secrets.canopy`. Тож на canopy запускати
# в job-контейнері (там і живуть три підписантські ключі):
#   kamal app exec -d canopy -r job "bin/rails treasury:balances"
#
# ⚠️ Дормантні (activation-gated) ролі пропускаються ГУЧНО — рядком, а не тишею:
# «нема ключа» і «є ключ, нема монет» є різними станами, і зонд, що зливає їх у
# порожній вивід, відповідав би на обидва одним мовчанням.
namespace :treasury do
  desc "READ-ONLY: баланс + nonce кожного oracle-підписанта з розрізненням НЕ ПРОВІЖИНЕНО ⊥ НИЖЧИЙ ЗА МІНІМУМ"
  task balances: :environment do
    slot = SilkenNet::DeploymentSlot.current
    puts "💰 Oracle wallets · slot=#{slot} · chain_env=#{ENV.fetch('WEB3_CHAIN_ENV', 'mainnet')}"
    puts "=" * 78

    Treasury::MonitorService::WALLETS.each do |key, wallet|
      # ⚠️ Реєстр НЕ однорідний: Solana стоїть поза seam'ом `OracleSigner` (адреса —
      # ПУБЛІЧНИЙ ключ із `env_public_key`, підпис — `SOLANA_WALLET_KEYPAIR`), тож
      # `role` там `nil`, а `resolvable?(nil)` чесно кидає. Зонд свідомо лишається
      # EVM-ним і каже це ВГОЛОС замість тихого пропуску: nonce у Solana немає
      # взагалі, тобто дискримінатор «не провіжинено ⊥ вичерпано» тут інший, і
      # вдавати, що ми його дали, було б гірше за відмову.
      if wallet[:role].nil?
        puts format("%-18s ⏭  ПОЗА ЗОНДОМ — не-EVM підписант (%s, адреса з %s); nonce-дискримінатора немає",
                    key, wallet[:network], wallet[:env_public_key])
        next
      end

      unless Web3::OracleSigner.resolvable?(wallet[:role])
        puts format("%-18s ⚪ ДОРМАНТНИЙ — бекенда підпису не заведено (role=%s)", key, wallet[:role])
        next
      end

      # 🔴 ТРЕТІЙ стан ключа, знайдений першим же прогоном зонда: ПРИСУТНІЙ, АЛЕ
      # НЕПРИДАТНИЙ. `resolvable?` відповідає на «чи заведено бекенд підпису», тобто
      # судить НАЯВНІСТЬ, і плейсхолдер у `.env` проходить його зеленим — а деривація
      # адреси падає `Secp256k1::Error`. Без цього гарду один зіпсований підписант
      # обривав увесь прохід, тобто зонд мовчав саме про ті дві ноги, заради яких його
      # писали. ⛔ Не «лагодити» це звуженням `resolvable?`: там інше питання.
      begin
        address = Web3::OracleSigner.address_for(wallet[:role])
      rescue StandardError => e
        puts format("%-18s ⛔ КЛЮЧ Є, АЛЕ НЕПРИДАТНИЙ — %s: %s (role=%s)", key, e.class, e.message, wallet[:role])
        next
      end

      if address.nil?
        puts format("%-18s ⛔ адреса не деривується (role=%s)", key, wallet[:role])
        next
      end

      min_native = (SystemParameter.current(wallet[:param_key], default: wallet[:min_balance]) ||
                    wallet[:min_balance]).to_f
      min_raw = (BigDecimal(min_native.to_s) * (10**wallet[:decimals])).to_i

      begin
        client  = Web3::RpcConnectionPool.client_for(wallet[:env_rpc_key])
        balance = client.get_balance(address)
        nonce   = client.get_nonce(address)
      rescue StandardError => e
        # ⛔ «Не прочитано» — ТРЕТІЙ стан, і зливати його з нулем заборонено: саме
        # так нуль-як-збій-приладу читався б як нуль-як-факт про світ.
        puts format("%-18s ❓ НЕ ПРОЧИТАНО — %s: %s (%s)", key, e.class, e.message, wallet[:env_rpc_key])
        next
      end

      human = balance.to_f / (10**wallet[:decimals])
      verdict =
        if balance.zero?
          nonce.to_i.zero? ? "⛔ НЕ ПРОВІЖИНЕНО (nonce=0 — з адреси не йшло НІЧОГО; у кран, не шукати витік)"
                           : "🔴 ВИЧЕРПАНО ДО НУЛЯ (nonce>0 — транзакції були)"
        elsif balance < min_raw
          "🟡 НИЖЧИЙ ЗА МІНІМУМ — витрачено більше, ніж поповнено"
        else
          "✅ OK"
        end

      puts format("%-18s %s", key, address)
      puts format("%-18s %.6f %s (поріг %.6f · ratio %.2f · nonce %d)",
                  "", human, wallet[:currency], min_native,
                  min_raw.positive? ? balance.to_f / min_raw : 0.0, nonce.to_i)
      puts format("%-18s %s", "", verdict)
      puts
    end
  end
end
