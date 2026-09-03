# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Web3
  # =========================================================================
  # 🔐 KMS SIGNER (SEC.17 — Cloud KMS backend of the signer seam)
  # =========================================================================
  # Same surface as `LocalEnvSigner`; the key object is a `Web3::KmsKey`, whose
  # private half never leaves the HSM — only 32-byte digests travel. Selected by
  # `OracleSigner.for` when the role's `ORACLE_*_KMS_KEY` names a key VERSION
  # (`projects/…/cryptoKeyVersions/N`); minter and slasher only, because those
  # are the roles the keyring provisions (`terraform/kms.tf`, 06_04 §5.5 step 3).
  # Job-only by construction: the names live on the job surface, and the guard
  # refuses a plaintext twin lingering beside them (zombie after the seal).
  # =========================================================================
  class KmsSigner < KeySigner
    # @param key_version_name [String] Cloud KMS key-version resource name
    # @param transport [#public_key_pem, #asymmetric_sign] REST by default; specs inject a fake HSM
    def initialize(key_version_name, transport: KmsKey::RestTransport.new)
      super(KmsKey.new(key_version_name, transport: transport))
    end
  end
end
