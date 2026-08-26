# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Web3
  # =========================================================================
  # 🔑 ORACLE SIGNER (SEC.17 seam — role → signer)
  # =========================================================================
  # Один дім деривації підписанта для ВСІХ EVM-money-шляхів. Доти
  # `Eth::Key.new(priv: ENV.fetch(...))` жив інлайном у 7 сервісах (12
  # `sender_key`-call-sites) — нуль спільного власника, тож підміна бекенду
  # підпису вимагала б 7 правок у money-path.
  #
  # `LocalEnvSigner` = поточна ENV-поведінка, behavior-preserving за побудовою.
  # Наступний крок (pre-mainnet, `06_04 §5.5`) — `Web3::KmsSigner`: ключ не
  # покидає HSM, backend шле лише digest. Тоді розвилка бекенду живе ТУТ, а не
  # в кожному сервісі.
  #
  # ⛔ КОЖНЕ ім'я ENV написане ЛІТЕРАЛОМ у `case` (`ENV.fetch` з рядком-константою),
  # по одному на роль — і це НЕ стиль. `spec/deploy/env_fetch_declaration_spec.rb`
  # сканує `app/**` статично саме за цією текстовою формою й рахує SET-DIFF проти
  # `config/deploy.yml` / Akash SDL / Kamal-ланцюга. Табличний lookup
  # (`ENV.fetch(ROLE_ENVS[role])`) вивів би змінну зі сканованої множини, і
  # гейт став би зеленим ВТРАТИВШИ ЗМІННУ — тобто відсутній на деплой-поверхні
  # money-ключ проходив би мовчки аж до KeyError у мить першого мінта.
  # Дзеркально: додаєш роль — додаєш літерал, інакше ключ не гейтований.
  # ⚠️ Той скан читає й КОМЕНТАРІ — приклад-заглушка з великих літер у лапках тут
  # сам став би «змінною», якої нема на жодній поверхні (виміряно 2026-08-26).
  #
  # ⚠️ `class << self` (а не `module_function`): `for` — ключове слово Ruby, і
  # копія без явного отримувача розпарсилась би як `for`-цикл.
  # =========================================================================
  module OracleSigner
    class << self
      # @param role [Symbol] one of :minter, :slasher, :celo, :puro, :klima, :etherisc, :anchor
      # @return [Web3::LocalEnvSigner]
      # @raise [KeyError] коли ENV-ключ ролі відсутній на цій поверхні (fail-loud, INF.12)
      # @raise [ArgumentError] на невідому роль
      def for(role)
        LocalEnvSigner.new(env_private_key(role))
      end

      private

      def env_private_key(role)
        case role
        when :minter   then ENV.fetch("ORACLE_MINTER_PRIVATE_KEY")
        when :slasher  then ENV.fetch("ORACLE_SLASHER_PRIVATE_KEY")
        when :celo     then ENV.fetch("ORACLE_CELO_PRIVATE_KEY")
        when :puro     then ENV.fetch("ORACLE_PURO_PRIVATE_KEY")
        when :klima    then ENV.fetch("ORACLE_KLIMA_PRIVATE_KEY")
        when :etherisc then ENV.fetch("ORACLE_ETHERISC_PRIVATE_KEY")
        when :anchor   then ENV.fetch("ETHEREUM_ANCHOR_PRIVATE_KEY")
        else raise ArgumentError, "Невідома signer-роль: #{role.inspect}"
        end
      end
    end
  end
end
