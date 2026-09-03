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
  # Два бекенди, розвилка живе ТУТ і ніде більше (`06_04 §5.5`):
  #   `KmsSigner`      — коли `ORACLE_<ROLE>_KMS_KEY` ролі називає key-version у
  #                      Cloud KMS (minter/slasher — ролі, що їх провіжить keyring);
  #   `LocalEnvSigner` — інакше: `Eth::Key` із plaintext deploy-ENV (поточна поведінка).
  # KMS-імена читаються `ENV[]`, а не `ENV.fetch`, СВІДОМО: відсутнє імʼя = «цю роль
  # підписує ENV-ключ», не збій; тож fail-loud цієї змінної забезпечує не KeyError, а
  # `Security::Web3NetworkGuard` (формат key-version + «сирий ключ поруч = зомбі»), і
  # саме через членство в guard-set вона класифікована для `web3_env_loudness_spec`.
  #
  # ⛔ КОЖНЕ ім'я ENV-ключа написане ЛІТЕРАЛОМ у `case` (`ENV.fetch` з рядком-константою),
  # по одному на роль — і це НЕ стиль. `spec/deploy/env_fetch_declaration_spec.rb`
  # сканує `app/**` статично саме за цією текстовою формою й рахує SET-DIFF проти
  # `config/deploy.yml` / Kamal-ланцюга. Табличний lookup
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
    # Roles with an HSM key in the keyring (`terraform/kms.tf`): the KMS axis exists for
    # these two only; the aux/anchor roles stay ENV-keyed by construction.
    KMS_KEY_ENVS = { minter: "ORACLE_MINTER_KMS_KEY", slasher: "ORACLE_SLASHER_KMS_KEY" }.freeze

    class << self
      # @param role [Symbol] one of :minter, :slasher, :celo, :puro, :klima, :etherisc, :anchor
      # @return [Web3::KeySigner] `KmsSigner` when the role is sealed, else `LocalEnvSigner`
      # @raise [KeyError] коли ENV-ключ ролі відсутній на цій поверхні (fail-loud, INF.12)
      # @raise [ArgumentError] на невідому роль
      def for(role)
        kms = kms_key_name(role)
        return KmsSigner.new(kms) if kms

        LocalEnvSigner.new(env_private_key(role))
      end

      # The read-only consumer's form (`Treasury::MonitorService`): `nil` when a role has
      # NEITHER backend — there «not activated» is a state, not a failure — else the address
      # the money path would sign from (an HSM role answers from its PUBLIC key, so the
      # balance sweep never becomes the last plaintext reader).
      # @return [Eth::Address, nil]
      def address_for(role)
        resolvable?(role) ? self.for(role).address : nil
      end

      # @return [Boolean] does SOME backend hold a key for the role on this surface?
      def resolvable?(role)
        kms_key_name(role).present? || env_private_key(role).present?
      rescue KeyError
        false
      end

      private

        def kms_key_name(role)
          var = KMS_KEY_ENVS[role]
          var && ENV[var].presence
        end

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
