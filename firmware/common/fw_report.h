// SPDX-License-Identifier: AGPL-3.0-or-later
/*
 * fw_report.h — [SEC.20] wire-звіт contract-стану: що РЕАЛЬНО біжить у вузлі.
 *
 * Навіщо: вузол після auto-fallback (3 bytecode-збої → erase contract → boot
 * embedded baseline) знову ЗДОРОВИЙ — vm_error зник, телеметрія чиста. Без
 * явного звіту backend ніколи не дізнається, що OTA-версія відкотилась:
 * байти 12..13 legacy-кадру возили compile-константу C-прошивки, яку
 * bytecode-OTA фізично не міняє (два різні version-простори). Звіт робить
 * відкат видимим з КОЖНОГО кадру — стан, не подія: LoRa губить кадри, але
 * наступний кадр знову несе істину (ідемпотентність замість retry-ACK).
 *
 * Семантика 16 біт (байти 12..13 legacy-wire, BE):
 *   [15] semantic  — 1 = цей звіт; 0 = legacy C-image константа (стара
 *                    прошивка / KV недоступний) — Rails розрізняє автоматично
 *   [14] reverted  — 1 = біжить baseline ПРИ спаленому припливі (hiwater>0 ∧
 *                    contract-magic відсутній): сигнатура auto-fallback,
 *                    самодостатня на девайсі (не залежить від пам'яті Rails)
 *   [13:0] id14    — hiwater (ключ 0x15) & 0x3FFF: біжуча версія, або спалена
 *                    при reverted (Rails одразу знає, від чого bump'ати).
 *                    Стеля 16383 = BioContractFirmware.id modulo; переповнення
 *                    віддасть ширше поле wire-rev3
 *
 * CCM-ера: той самий звіт стискається у vpd_index-байт (до BME280/HW.32):
 *   [7] reverted | [6:0] id7. Несучий біт — reverted; echo 7 біт = best-effort
 *   (колізія modulo НІКОЛИ не маскує відкат). Фліп-день перепрошиває всі
 *   вузли → неоднозначність legacy-CCM (0x00 = factory АБО стара прошивка)
 *   вимирає разом зі старою прошивкою.
 *
 * Дзеркало Ruby: TelemetryLog::FW_REPORT_* + TelemetryUnpackerService.
 * Канон: 03_01 §1.6 (байти 12..13) + 03_06 §4 (bump-інваріант) + 00_07 SEC.20.
 */
#ifndef SILKEN_FW_REPORT_H
#define SILKEN_FW_REPORT_H

#include <stdint.h>

#define FW_REPORT_SEMANTIC_BIT  0x8000u
#define FW_REPORT_REVERTED_BIT  0x4000u
#define FW_REPORT_ID_MASK       0x3FFFu

/* Зібрати звіт з фактів boot'а. !kv_mounted → legacy_id як є (semantic=0):
 * без припливу звіт був би вигадкою — чесна деградація до старої семантики. */
static inline uint16_t Fw_Report_Compose(int kv_mounted, uint32_t hiwater,
                                         int contract_live, uint16_t legacy_id)
{
    if (!kv_mounted) return legacy_id;
    uint16_t id14 = (uint16_t)(hiwater & FW_REPORT_ID_MASK);
    if (contract_live) return (uint16_t)(FW_REPORT_SEMANTIC_BIT | id14);
    if (hiwater > 0u)
        return (uint16_t)(FW_REPORT_SEMANTIC_BIT | FW_REPORT_REVERTED_BIT | id14);
    return FW_REPORT_SEMANTIC_BIT; /* factory baseline — OTA ще не жив тут */
}

/* CCM vpd_index-байт: [reverted:1 | id7]. Legacy-семантика (semantic=0) →
 * 0x00, як байт слався до цього патча. */
static inline uint8_t Fw_Report_To_Vpd(uint16_t report)
{
    if (!(report & FW_REPORT_SEMANTIC_BIT)) return 0x00u;
    return (uint8_t)(((report & FW_REPORT_REVERTED_BIT) ? 0x80u : 0x00u) |
                     (report & 0x7Fu));
}

#endif /* SILKEN_FW_REPORT_H */
