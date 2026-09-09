// SPDX-License-Identifier: AGPL-3.0-or-later
/*
 * ota_sha_guard.h — [FW.52] Персистований SHA-256 останньої прийнятої OTA
 *                   для cross-check на Magic Re-Request (§5.1.3).
 *
 * Навіщо: `pending_ota_bytecode` живе лише в RAM Королеви. Після повного
 * reflex-shot циклу (`ota_is_active` 1→0) буфер логічно "видихнув", але
 * БАЙТИ лишаються на місці, аж доки наступний CoAP OTA-push не почне їх
 * перезаписувати посеред нового `Handle_CoAP_Command`-збирання (03_02 §5).
 * Пізній Magic Re-Request (`OTA_REQ_MARKER`, 03_02 §5.1.3) до FW.52 не мав
 * способу відрізнити "буфер той самий, що я чекав" від "буфер уже
 * наполовину чужий" — і canon сам це називав дослівно: "після
 * ota_is_active=0 буфер pending_ota_bytecode може бути перезаписаний
 * наступним CoAP-push'ем, тоді re-request не обслуговується" (03_02 §5.1.3,
 * 00_07 FW.52). Це не гіпотетична діра: served-навмання чанк із чужої
 * прошивки Солдат прийме як СВОЮ (LoRa-шар CRC32-перевіряє повний зібраний
 * потік, не окремий чанк проти еталону).
 *
 * Дизайн — [magic:4][sha256:32] = 36 байт = 5 doublewords, той самий
 * "тіло-перше-магія-остання" (power-cut-safe) порядок, що й
 * `common/flash_ota.c` (Flash_Write_Contract). Свідомо СИБЛІНГ, не той
 * самий виклик: там — змінний розмір, сторінка 126 (Soldier mruby-контракт,
 * інший чіп/інша семантика магії "RITE"); тут — фіксовані 36 байт, Queen'ина
 * власна вільна сторінка 125. ⚠️ Номер СПІВПАДАЄ з Soldier-івською сторінкою
 * 125 (FLASH_OTA_KEY_ADDR/FLASH_BCAST_KEY_ADDR, 03_01 §2.3) — інший фізичний
 * чіп, інший адресний простір, справжньої колізії нема, але читай «сторінка
 * 125» завжди з іменем чіпа поруч. Карта Королеви живе ЛИШЕ в коментарі
 * main.c біля queen_kv (окремого канон-дому Queen-flash-map ще нема): 122-123
 * Helium-KV [ARCH34_HELIUM_ENABLED, gated] · 124 ключі KEYB/KEYC/EDSK · 127
 * UID; 125-126 нічим не заявлені до цього файлу. Мерджити
 * в один виклик означало б додати page-параметр `Flash_Write_Contract` і
 * чіпати її 10 наявних host-тестових call-site'ів (test_flash_ota.c) заради
 * нуль-зміни поведінки Soldier-шляху — не варте.
 *
 * On-boot mount НЕ потрібен (на відміну від flash_kv.h journal-стору):
 * запис один, фіксованого розміру, переписується ЦІЛКОМ раз на OTA-цикл
 * (дні-тижні, FW.52 ADR) — рівно той самий usage-шейп, що вже має
 * flash_ota.c для Soldier'а. Erase/rewrite-раз-на-цикл не тисне wear-бюджет
 * (~10k циклів/сторінку, 03_01 §2.3).
 *
 * One-Home: firmware і host-тести компілюють цей самий код; залізні
 * примітиви — той самий FlashKvOps seam, що й flash_kv.h/flash_ota.h (host
 * = RAM+fault-injection мок у test_ota_sha_guard.c, MCU = HAL_FLASH у
 * queen/main.c). Канон: 03_02 §5.1.3 + 00_07 FW.52.
 */
#ifndef SILKEN_QUEEN_OTA_SHA_GUARD_H
#define SILKEN_QUEEN_OTA_SHA_GUARD_H

#include <stdint.h>
#include <string.h>
#include "../common/flash_kv.h"     /* FlashKvOps — read_dw/program_dw/erase_page */
#include "../common/silken_sha256.h"

/* Queen Flash, сторінка 125 (0x0803E800) — вільна (див. блок-коментар
 * вище). Абсолютна, як і решта однослотових Queen-констант (FLASH_KEY_ADDR,
 * QUEEN_UID_FLASH_ADDR) — HAL-глю у main.c мапить її на реальну адресу. */
#define QUEEN_OTA_SHA_PAGE        125u
#define QUEEN_OTA_SHA_MAGIC       0x514F5348u /* "QOSH" сентинел — не RITE/EDSK/KEYL/KEYC */
#define QUEEN_OTA_SHA_RECORD_SIZE 36u         /* magic:4 + sha256:32 */
#define QUEEN_OTA_SHA_RECORD_DWS  5u          /* ceil(36/8) */

/* Персистує SHA-256(bytecode[0..size)) на Queen Flash, magic-last
 * power-cut-safe: тіло (dw1..dw4) — ПЕРШИМ, magic-dw (dw0) — ОСТАННІМ.
 * Перерваний посеред запис лишає dw0 стертим (0xFF…) → Verify нижче бачить
 * невалідну магію → трактує як "нічого не персистовано", безпечний
 * фолбек (ніколи не хибне "збіглося"). 1 = успіх, 0 = відмова HAL/входу. */
static inline int Ota_Sha_Persist(const FlashKvOps *ops, void *io,
                                   const uint8_t *bytecode, uint16_t size)
{
    uint8_t  record[QUEEN_OTA_SHA_RECORD_SIZE];
    uint32_t magic = QUEEN_OTA_SHA_MAGIC;

    if (!ops || !ops->erase_page || !ops->program_dw || !bytecode || size == 0u) return 0;

    memcpy(record, &magic, 4u);
    Silken_Sha256(bytecode, size, record + 4u);

    if (!ops->erase_page(io, QUEEN_OTA_SHA_PAGE)) return 0;

    for (uint16_t i = 1u; i < QUEEN_OTA_SHA_RECORD_DWS; i++) {
        uint64_t dw  = 0xFFFFFFFFFFFFFFFFull;   /* нероздані хвостові байти = 0xFF */
        uint32_t off = (uint32_t)i * 8u;
        uint16_t rem = (uint16_t)(QUEEN_OTA_SHA_RECORD_SIZE - off);
        if (rem > 8u) rem = 8u;
        memcpy(&dw, record + off, rem);
        if (!ops->program_dw(io, off, dw)) return 0;
    }

    uint64_t dw0;
    memcpy(&dw0, record, 8u);
    return ops->program_dw(io, 0u, dw0);  /* magic — LAST (power-cut safety) */
}

/* Звіряє SHA-256(candidate[0..candidate_size)) проти персистованого запису.
 * 1 = збіглося — буфер безпечно обслуговувати з поточного вмісту РІВНО
 * такого, як його персистили при прийомі. 0 = магія невалідна (нічого не
 * персистовано / erase без наступного program) АБО хеш розійшовся (буфер
 * уже частково/повністю чужий — новий CoAP-push пише зверху) — обидва
 * випадки трактуються ОДНАКОВО: fail-closed, не обслуговувати. */
static inline int Ota_Sha_Verify(const FlashKvOps *ops, void *io,
                                  const uint8_t *candidate, uint16_t candidate_size)
{
    uint8_t  stored[QUEEN_OTA_SHA_RECORD_SIZE];
    uint8_t  fresh[SILKEN_SHA256_DIGEST_LEN];
    uint32_t magic;

    if (!ops || !ops->read_dw || !candidate || candidate_size == 0u) return 0;

    for (uint16_t i = 0u; i < QUEEN_OTA_SHA_RECORD_DWS; i++) {
        uint64_t dw  = ops->read_dw(io, (uint32_t)i * 8u);
        uint16_t off = i * 8u;
        uint16_t rem = (uint16_t)(QUEEN_OTA_SHA_RECORD_SIZE - off);
        if (rem > 8u) rem = 8u;
        memcpy(stored + off, &dw, rem);
    }

    memcpy(&magic, stored, 4u);
    if (magic != QUEEN_OTA_SHA_MAGIC) return 0;   /* нічого валідного не персистовано */

    Silken_Sha256(candidate, candidate_size, fresh);
    return memcmp(stored + 4u, fresh, SILKEN_SHA256_DIGEST_LEN) == 0;
}

#endif /* SILKEN_QUEEN_OTA_SHA_GUARD_H */
