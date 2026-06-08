/*
 * flash_ota.h — [FW.52-г] OTA contract blob writer for STM32WLE5JC.
 *
 * Навіщо: Soldier збирає OTA mruby-байткод у `ota_buffer`, звіряє CRC32 +
 * HMAC, тоді мусить ЗАПИСАТИ його у contract-сторінку Flash, щоб boot
 * magic-check (RITE @ MRUBY_CONTRACT_FLASH_ADDR) завантажив його наступним
 * reset'ом. Без цього запису OTA нефункціональний end-to-end — зібраний
 * байткод ніколи не доходить до Flash (раніше `Write_OTA_Contract_To_Flash`
 * був порожнім hal_mock-стабом).
 *
 * Power-cut safety: magic-doubleword (несе "RITE" у `data[0..3]`) програмиться
 * ОСТАННІМ. Перерваний запис → dw[0] лишається стертим (0xFF…) → boot не бачить
 * RITE → fallback на embedded `lorenz_bytecode` (безпечно). Запис, що дійшов до
 * magic → повний (безпечно). Як у flash_kv: dw-програмування атомарне щодо ECC,
 * тож «порваного» dw не існує — або записаний, або стертий 0xFF.
 *
 * One-Home: firmware і host-тести компілюють цей самий код; залізні примітиви
 * ізольовано у `FlashKvOps` (host = RAM + fault-injection, MCU = HAL_FLASH при
 * HAL-фазі). Канон: 03_02 §5 (OTA) + 03_01 §2.3 + 00_07 FW.52.
 */
#ifndef SILKEN_FLASH_OTA_H
#define SILKEN_FLASH_OTA_H

#include <stdint.h>
#include "flash_kv.h"  /* FlashKvOps (read_dw / program_dw / erase_page) */

/* Contract-сторінка: 0x0803F000 на STM32WLE5JC (256 КБ Flash, 2 КБ сторінки
 * → сторінка 126). Значення = дзеркало MRUBY_CONTRACT_FLASH_ADDR у main.c. */
#define OTA_CONTRACT_PAGE  126u
#define OTA_CONTRACT_MAGIC 0x45544952u  /* "RITE" little-endian */

/* Пише data[0..size] у contract-сторінку (попередньо стерши її), power-cut-safe
 * (magic-dw останнім). `ops`/`io` — як у flash_kv (`byte_off` від бази сторінки).
 * 1 = успіх; 0 = відмова erase/program АБО size < 4 (немає місця під magic). */
int Flash_Write_Contract(const FlashKvOps *ops, void *io, const uint8_t *data, uint16_t size);

#endif /* SILKEN_FLASH_OTA_H */
