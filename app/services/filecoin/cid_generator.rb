# frozen_string_literal: true

module Filecoin
  # =========================================================================
  # 🔗 FILECOIN CID GENERATOR (Детермінований Відбиток Вічної Пам'яті)
  # =========================================================================
  # Обчислює канонічний, самоперевірний CIDv1 (Content Identifier) для
  # довільного payload — БЕЗ звернення до IPFS-шлюзу. Той самий вміст завжди
  # дає той самий CID, тож архів неможливо ex-post підмінити непомітно:
  # верифікатор перераховує CID локально й порівнює з тим, що пінилося.
  #
  # Формат (multiformats CIDv1, leaf-рівень E.60 — `05_02 §E.60`):
  #   multibase('b') + version(0x01) + codec(raw 0x55) + multihash(sha2-256)
  #   multihash = 0x12 (sha2-256) ‖ 0x20 (32 байти) ‖ SHA256(bytes)
  # Результат — рядок з префіксом «bafkrei…» (raw + sha2-256), сумісний з
  # `ipfs add --raw-leaves --cid-version 1`.
  # =========================================================================
  module CidGenerator
    module_function

    CIDV1_VERSION = 0x01            # CID version 1
    RAW_CODEC     = 0x55            # multicodec «raw» (вміст — сирі байти)
    SHA2_256_CODE = 0x12            # multihash function code: sha2-256
    SHA2_256_LEN  = 0x20            # digest length: 32 байти
    MULTIBASE_B32 = "b"            # multibase prefix: base32 (RFC 4648 lower, no-pad)
    BASE32_ALPHABET = "abcdefghijklmnopqrstuvwxyz234567"

    # Детермінований CIDv1 для рядка (сирі байти) або Hash/Array (канонічний JSON).
    def cidv1(payload)
      bytes     = payload.is_a?(String) ? payload : canonical_json(payload)
      digest    = Digest::SHA256.digest(bytes)
      multihash = [ SHA2_256_CODE, SHA2_256_LEN ].pack("C2") + digest
      cid_bytes = [ CIDV1_VERSION, RAW_CODEC ].pack("C2") + multihash
      MULTIBASE_B32 + base32_encode(cid_bytes)
    end

    # Канонічна JSON-серіалізація: рекурсивно відсортовані ключі + компактно —
    # щоб логічно однаковий вміст завжди давав байтово однаковий CID.
    def canonical_json(obj)
      JSON.generate(deep_sort(obj))
    end

    def deep_sort(obj)
      case obj
      when Hash
        obj.keys.sort_by(&:to_s).each_with_object({}) { |k, acc| acc[k] = deep_sort(obj[k]) }
      when Array
        obj.map { |e| deep_sort(e) }
      else
        obj
      end
    end

    # RFC 4648 base32, нижній регістр, без padding (multibase 'b').
    def base32_encode(bytes)
      bits = bytes.unpack1("B*")
      bits += "0" * ((5 - (bits.length % 5)) % 5)
      bits.chars.each_slice(5).map { |group| BASE32_ALPHABET[group.join.to_i(2)] }.join
    end
  end
end
