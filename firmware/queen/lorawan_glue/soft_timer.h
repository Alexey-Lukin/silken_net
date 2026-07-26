// SPDX-License-Identifier: AGPL-3.0-or-later
#ifndef SILKEN_SOFT_TIMER_H
#define SILKEN_SOFT_TIMER_H

#include <stdint.h>

/*
 * soft_timer.h — [ARCH.34] owned м'який таймер-движок під vendored
 * LoRaMac-node (контракт Conf/timer_template.h; ST чекав UTIL_TIMER зі
 * stm32-utilities — ми НЕ тягнемо ще один submodule заради полінг-движка).
 *
 * Дизайн: інтрузивний однозв'язний список; об'єкти живуть у static-пам'яті
 * LoRaMac (жодних алокацій; TimerEvent_t для стека непрозорий — доступ
 * лише через 6 функцій контракту). Диспатч = полінг Soft_Timer_Dispatch()
 * у тугому LmHandlerProcess-циклі adapter'а — ms-порядок точності, поки
 * цикл тугий. [transitional] стеля: поза SOS-епізодом движок не тікає
 * (Queen не тримає LoRaWAN-сесій між епізодами — fresh join by design);
 * загальновузловий преемптивний таймер = бенч-ера, якщо колись знадобиться
 * Class-A downlink поза епізодом.
 *
 * Джерело часу — інжектоване: Soft_Timer_Now_Ms() дає glue (HAL_GetTick)
 * або host-тест (керований фейк) — той самий ops-патерн, що flash_kv.
 * Wrap-safe: усі порівняння на беззнаковій різниці (49.7 діб HAL_GetTick).
 */

typedef void ( *SoftTimerCb )( void *context );

typedef struct SoftTimer_s {
    struct SoftTimer_s *next;      /* інтрузивний список активних */
    SoftTimerCb         callback;
    void               *context;
    uint32_t            period_ms; /* останнє SetValue */
    uint32_t            target_ms; /* тік спрацювання (wrap-safe) */
    /* Ім'я поля = ABI: LmhpCompliance.c читає Timer.IsRunning напряму —
     * єдине місце, де стек лізе повз 6-функційний контракт. */
    uint8_t             IsRunning;
} SoftTimer_t;

/* Постачається викликачем (glue/тест), НЕ движком. */
uint32_t Soft_Timer_Now_Ms( void );

void     Soft_Timer_Init( SoftTimer_t *t, SoftTimerCb cb );
void     Soft_Timer_Set_Value( SoftTimer_t *t, uint32_t ms );
void     Soft_Timer_Start( SoftTimer_t *t );
void     Soft_Timer_Stop( SoftTimer_t *t );
uint32_t Soft_Timer_Elapsed_Since( uint32_t past_ms );

/* Кличе callback'и ВСІХ прострочених (one-shot: перед викликом таймер
 * знімається — callback може легально перезапустити себе). Повертає
 * кількість спрацювань (діагностика/тести). */
uint32_t Soft_Timer_Dispatch( void );

#endif /* SILKEN_SOFT_TIMER_H */
