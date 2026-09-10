// SPDX-License-Identifier: AGPL-3.0-or-later
/*
 * cmd_token.h — [FW.60/FW.63] Локатор idempotency-токена в CMD-конверті Королеви.
 *
 * Wire (03_02 §6, 03_05 §CMD):  CMD:<ACTION>:<DURATION>:<ACTUATOR_ID>:<TOKEN>
 * Токен — ОСТАННЄ поле, і саме воно (а) хешується для Cmd_Dedup_Check і
 * (б) луною повертається Rails у `?cmd=` наступного poll'а, де
 * `observe_delivered_command!` шукає його `find_by(idempotency_token:)`.
 *
 * Чому ключ на ОСТАННІЙ двокрапці, а не «після 3-ї від +4»: лічильник
 * роздільників правдивий лише доки ACTION не несе двокрапки. Форма
 * `ACTION:value` (колишній ALLOWED_PAYLOAD_FORMAT, сіди `OPEN:60`) зсувала
 * вікно на поле ACTUATOR_ID — дедуп лишався self-consistent (той самий зсув на
 * кожному повторі), а echo ніколи не збігався з idempotency_token: команда
 * виконана, Rails по TTL пише `failed`. Rails тепер забороняє двокрапку в
 * ACTION (`ActuatorCommand::ALLOWED_PAYLOAD_FORMAT`); цей заголовок — друга
 * лінія: UUID двокрапок не має за побудовою, тож останній роздільник завжди
 * відділяє токен, хоч би що стояло в ACTION.
 *
 * Pure header (без HAL): host-тести `firmware/test/test_queen_logic.c` ганяють
 * саме цей код, не дзеркало.
 */
#ifndef QUEEN_CMD_TOKEN_H
#define QUEEN_CMD_TOKEN_H

#include <stdint.h>
#include <stddef.h>

#ifndef UUID_STR_LEN
#define UUID_STR_LEN 36   /* 8-4-4-4-12 з дефісами — та сама replacement-list, що в main.c */
#endif

/* Роздільників після "CMD:" щонайменше три: ACTION:DURATION:ACTUATOR_ID:TOKEN. */
#define CMD_TOKEN_MIN_COLONS 3u

/*
 * inner     — дешифрований CMD-рядок від байта 'C' (вже перевірено "CMD:").
 * inner_len — aligned-довжина буфера; CBC zero-pad ставить NUL раніше за неї.
 * Повертає вказівник на перший байт токена або NULL: менш ніж три роздільники
 * після "CMD:", порожній токен, або роздільник упирається в межу буфера.
 * Ніколи не читає поза [inner, inner + inner_len).
 */
static inline const char* Cmd_Locate_Token(const char* inner, uint16_t inner_len)
{
    if (inner == NULL || inner_len <= 4u) return NULL;

    const char* last = NULL;
    uint16_t colons = 0;
    for (uint16_t i = 4u; i < inner_len && inner[i] != '\0'; i++) {
        if (inner[i] == ':') {
            colons++;
            last = inner + i + 1;
        }
    }
    if (colons < CMD_TOKEN_MIN_COLONS || last == NULL) return NULL;
    if (last >= inner + inner_len || *last == '\0') return NULL;   /* порожній токен */
    return last;
}

/*
 * Довжина токена: до NUL, до UUID_STR_LEN або до кінця буфера (`remaining` =
 * inner + inner_len − p) — що настане першим. Та сама межа, що в djb2_hash над
 * токеном, тож хеш дедупу на канонічному конверті байт-у-байт той, що й доти.
 */
static inline uint8_t Cmd_Token_Len(const char* p, uint16_t remaining)
{
    uint16_t cap = remaining < UUID_STR_LEN ? remaining : (uint16_t)UUID_STR_LEN;
    uint8_t n = 0;
    while (n < cap && p[n] != '\0') n++;
    return n;
}

/* Копія токена в out (ємність UUID_STR_LEN + 1), завжди NUL-термінована. */
static inline void Cmd_Copy_Token(char out[UUID_STR_LEN + 1], const char* p, uint8_t len)
{
    uint8_t i = 0;
    while (i < len && i < UUID_STR_LEN) { out[i] = p[i]; i++; }
    out[i] = '\0';
}

#endif /* QUEEN_CMD_TOKEN_H */
