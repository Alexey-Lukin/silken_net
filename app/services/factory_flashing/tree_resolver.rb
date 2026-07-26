# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# [FW.54/SEC.3] UID → DID → Tree: one-pass прив'язка кремнію до identity.
#
# Вхід — 24-hex кремнієвий UID (три %08X-слова, порядок регістрів);
# `SilkenNet::DidDerivation.wire_did_from_uid_hex` дає канонічний
# `trees.did`. Чотири долі:
#   • дерева нема → create! — потрібні cluster_id + tree_family_id
#     (family = NOT NULL у БД; без cluster `OtaHmacKeyService.fetch_for`
#     впаде на K_ota). Координати лишаються польовому register-ритуалу.
#   • є, паспорт порожній → bind: legacy-дерево всиновлює свій чип.
#   • є, паспорт == uid → re-flash того самого чипа (ідемпотентний no-op).
#   • є, паспорт інший → CollisionError: birthday-колізія 32-біт DID або
#     чужа плата на джизі — юніт у quarantine (03_01 §7), жодних записів.
#
# Peaq-реєстрація тут СВІДОМО не enqueue'иться [transitional]: фабричний
# хост offline-friendly (web3-черг нема); peaq — за польовим
# `ProvisioningController#register`.
module FactoryFlashing
  class TreeResolver
    class CollisionError < StandardError; end
    class MissingAttributesError < StandardError; end

    def self.resolve!(uid_hex:, cluster_id: nil, tree_family_id: nil)
      uid = uid_hex.to_s.strip.upcase
      did = SilkenNet::DidDerivation.wire_did_from_uid_hex(uid)
      tree = Tree.find_by(did: did)

      if tree.nil?
        if cluster_id.blank? || tree_family_id.blank?
          raise MissingAttributesError,
                "Tree #{did} не існує — для створення потрібні CLUSTER_ID і TREE_FAMILY_ID " \
                "(tree_family = NOT NULL; без cluster не деривується K_ota, FW.23)"
        end
        return Tree.create!(did: did, silicon_uid_hex: uid,
                            cluster_id: cluster_id, tree_family_id: tree_family_id)
      end

      case tree.silicon_uid_hex
      when nil then tree.update!(silicon_uid_hex: uid)
      when uid then nil
      else
        raise CollisionError,
              "DID #{did}: у БД чип #{tree.silicon_uid_hex}, на джизі #{uid} — " \
              "birthday-колізія DID або чужа плата; юніт у quarantine (03_01 §7)"
      end
      tree
    end
  end
end
