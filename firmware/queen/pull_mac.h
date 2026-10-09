// SPDX-License-Identifier: AGPL-3.0-or-later
/*
 * pull_mac.h — [SEC.38] MAC над Queen-pull запитом (`poll/<uid>` і `ota/<uid>`).
 *
 * Навіщо: Rails шукає шлюз за uid з Uri-Path і доти вірив query будь-якого
 * відправника — підроблений `fw=` закривав OTA-кампанію шлюзу, що її не отримав,
 * а сам poll рухав стан наказів. Конверт ВІДПОВІДІ під KEYC цього не лікував:
 * він ховає, що каже Rails, а не доводить, хто питає. ⚖️ founder 2026-09-27.
 *
 * Форма (дзеркало — Rails `Downlink::PullMac`, спільний golden-вектор —
 * firmware/test/test_pull_mac.c ⟷ spec/services/downlink/pull_mac_spec.rb):
 *   K_mac     = HMAC-SHA256(KEYC, "silken-poll-mac-v1")  — підключ, щоб AES-256
 *               KEYC і HMAC не ділили один ключ;
 *   canonical = "silken-pull-v1" "\n" route "\n" uid "\n" mid(десятково)
 *               ("\n" q)*  — q = Uri-Query опції в порядку надсилання, БЕЗ m=;
 *   запит несе  "m=" + перші 16 байт HMAC-SHA256(K_mac, canonical) у hex.
 *
 * ⚠️ KEYC у RAM — це `uint32_t[8]`, завантажений із Flash словами, які
 * CommandBuilder пише `-w32 0x00112233` для байтів 00 11 22 33 (FW.30-
 * конвенція). HAL CRYP споживає слова ЧИСЛОМ, тож AES працює, але байтовий
 * вигляд памʼяті на LE Cortex-M4 переставляє байти кожного слова — HMAC над
 * ним на кремнії не зійшовся б із Rails. Тому ключ перетворюється тут, в одному
 * місці: Pull_Mac_Keyc_Bytes = big-endian байти кожного слова.
 *
 * Стеля, названа свідомо: свіжості MAC не дає — перехоплений справжній запит
 * можна повторити (MID після ребуту Королеви починається знову, з FW.60 — з HRNG). Повтор нічого не
 * підробляє (fw= і cmd= — справжні), лише перевидає голову черги; час Королева
 * отримує саме з poll-відповіді, тож штамп часу в MAC дав би дедлок першого poll'а.
 */
#ifndef SILKEN_PULL_MAC_H
#define SILKEN_PULL_MAC_H

#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "../common/silken_sha256.h"

#define PULL_MAC_LABEL      "silken-poll-mac-v1"
#define PULL_MAC_VERSION    "silken-pull-v1"
#define PULL_MAC_HEX_LEN    32u
#define PULL_MAC_QUERY_LEN  (2u + PULL_MAC_HEX_LEN) /* "m=" + hex, без NUL */
#define PULL_MAC_KEY_WORDS  8u

static inline void Pull_Mac_Keyc_Bytes(const uint32_t words[PULL_MAC_KEY_WORDS],
                                       uint8_t out[4u * PULL_MAC_KEY_WORDS])
{
    for (uint32_t i = 0; i < PULL_MAC_KEY_WORDS; i++) {
        out[4u * i + 0u] = (uint8_t)(words[i] >> 24);
        out[4u * i + 1u] = (uint8_t)(words[i] >> 16);
        out[4u * i + 2u] = (uint8_t)(words[i] >> 8);
        out[4u * i + 3u] = (uint8_t)(words[i]);
    }
}

/* 1 — у `out` лежить "m=<32 hex>" + NUL; 0 — канонічний рядок не вліз
 * (запит тоді не йде зовсім: без MAC Rails однаково відповів би 4.01). */
static inline int Pull_Mac_Query(const uint32_t keyc_words[PULL_MAC_KEY_WORDS],
                                 const char *route, const char *uid, uint16_t mid,
                                 const char *q1, const char *q2,
                                 char out[PULL_MAC_QUERY_LEN + 1u])
{
    uint8_t keyc[4u * PULL_MAC_KEY_WORDS];
    uint8_t k_mac[SILKEN_SHA256_DIGEST_LEN];
    uint8_t digest[SILKEN_SHA256_DIGEST_LEN];
    char canon[192];

    Pull_Mac_Keyc_Bytes(keyc_words, keyc);
    Silken_Hmac_Sha256(keyc, sizeof keyc, (const uint8_t *)PULL_MAC_LABEL,
                       sizeof(PULL_MAC_LABEL) - 1u, k_mac);

    int n = snprintf(canon, sizeof canon, "%s\n%s\n%s\n%u",
                     PULL_MAC_VERSION, route, uid, (unsigned)mid);
    if (n < 0 || (size_t)n >= sizeof canon) return 0;
    const char *qs[2] = { q1, q2 };
    for (int i = 0; i < 2; i++) {
        if (!qs[i]) continue;
        int m = snprintf(canon + n, sizeof canon - (size_t)n, "\n%s", qs[i]);
        if (m < 0 || (size_t)(n + m) >= sizeof canon) return 0;
        n += m;
    }

    Silken_Hmac_Sha256(k_mac, sizeof k_mac, (const uint8_t *)canon, (size_t)n, digest);
    static const char hex[] = "0123456789abcdef";
    out[0] = 'm';
    out[1] = '=';
    for (uint32_t i = 0; i < PULL_MAC_HEX_LEN / 2u; i++) {
        out[2u + 2u * i] = hex[digest[i] >> 4];
        out[3u + 2u * i] = hex[digest[i] & 0x0Fu];
    }
    out[PULL_MAC_QUERY_LEN] = '\0';
    return 1;
}

/*
 * [FW.60 ⚖️ делеговано 2026-10-09] MAC над poll-ВІДПОВІДДЮ — дзеркало Rails
 * `Downlink::PullMac.reply_tag`, golden-вектор спільний (test_pull_mac.c ⟷ pull_mac_spec.rb).
 * Конверт [IV:16][AES-256-CBC KEYC] ховав, ЩО каже Rails, але не доводив, що казав Rails:
 * зміна IV переписує перший блок відкритого тексту (час і OTA-hint), а стару відповідь
 * можна повторити. Тег — 16 Б хвостом після конверта:
 *   K_rmac = HMAC-SHA256(KEYC, "silken-reply-mac-v1");
 *   tag    = перші 16 Б HMAC-SHA256(K_rmac, "silken-reply-v1" "\n" m_hex "\n" ‖ конверт),
 *   m_hex  = 32 hex тегу ЦЬОГО запиту — відповідь чинна лише для свого запиту.
 * Королева звіряє тег ДО розшифрування (encrypt-then-MAC). Свіжість між ребутами дає
 * випадковий початковий MID (queen/main.c): без нього запит після ребуту повторювався б
 * побайтово, а з ним — і чинний тег старої відповіді.
 */
#define PULL_MAC_REPLY_LABEL    "silken-reply-mac-v1"
#define PULL_MAC_REPLY_VERSION  "silken-reply-v1"
#define PULL_MAC_REPLY_TAG_LEN  16u

static inline void Pull_Mac_Reply_Tag(const uint32_t keyc_words[PULL_MAC_KEY_WORDS],
                                      const char m_hex[PULL_MAC_HEX_LEN],
                                      const uint8_t *envelope, uint16_t env_len,
                                      uint8_t out[PULL_MAC_REPLY_TAG_LEN])
{
    uint8_t keyc[4u * PULL_MAC_KEY_WORDS];
    uint8_t k_rmac[SILKEN_SHA256_DIGEST_LEN];
    uint8_t digest[SILKEN_SHA256_DIGEST_LEN];
    uint8_t prefix[sizeof(PULL_MAC_REPLY_VERSION) + PULL_MAC_HEX_LEN + 1u]; /* ver \n hex \n */
    size_t n = sizeof(PULL_MAC_REPLY_VERSION) - 1u;

    Pull_Mac_Keyc_Bytes(keyc_words, keyc);
    Silken_Hmac_Sha256(keyc, sizeof keyc, (const uint8_t *)PULL_MAC_REPLY_LABEL,
                       sizeof(PULL_MAC_REPLY_LABEL) - 1u, k_rmac);
    memcpy(prefix, PULL_MAC_REPLY_VERSION, n);
    prefix[n++] = '\n';
    memcpy(prefix + n, m_hex, PULL_MAC_HEX_LEN);
    n += PULL_MAC_HEX_LEN;
    prefix[n++] = '\n';
    Silken_Hmac_Sha256_Concat(k_rmac, sizeof k_rmac, prefix, n, envelope, env_len, digest);
    memcpy(out, digest, PULL_MAC_REPLY_TAG_LEN);
}

/* 1 — хвіст payload'а несе чинний тег для запиту з `qm` ("m=<hex>"), і *len зменшено
 * до самого конверта; 0 — тегу немає чи він чужий (підробка, повтор, збій): відповідь
 * не читається зовсім, як транспортний збій. Порівняння — без раннього виходу. */
static inline int Pull_Mac_Reply_Verify(const uint32_t keyc_words[PULL_MAC_KEY_WORDS],
                                        const char qm[PULL_MAC_QUERY_LEN + 1u],
                                        const uint8_t *payload, uint16_t *len)
{
    if (payload == NULL || len == NULL || *len < PULL_MAC_REPLY_TAG_LEN) return 0;
    const uint16_t env_len = (uint16_t)(*len - PULL_MAC_REPLY_TAG_LEN);
    uint8_t want[PULL_MAC_REPLY_TAG_LEN];
    uint8_t diff = 0;
    Pull_Mac_Reply_Tag(keyc_words, qm + 2u, payload, env_len, want);
    for (uint32_t i = 0; i < PULL_MAC_REPLY_TAG_LEN; i++) diff |= (uint8_t)(want[i] ^ payload[env_len + i]);
    if (diff != 0u) return 0;
    *len = env_len;
    return 1;
}

#endif /* SILKEN_PULL_MAC_H */
