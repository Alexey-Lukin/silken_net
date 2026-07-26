// SPDX-License-Identifier: AGPL-3.0-or-later
/*
 * soft_timer.c — [ARCH.34] тіло м'якого таймер-движка (дизайн у .h).
 * Спільний стан між TU LoRaMac (створюють таймери) і adapter'ом
 * (диспатчить) — тому .c, не header-only.
 */
#include "soft_timer.h"
#include <stddef.h>

static SoftTimer_t *g_active_head = NULL;

/* 1 = t уже в списку активних. */
static int in_active_list( const SoftTimer_t *t )
{
    const SoftTimer_t *it;
    for ( it = g_active_head; it != NULL; it = it->next ) {
        if ( it == t ) return 1;
    }
    return 0;
}

static void unlink_timer( SoftTimer_t *t )
{
    SoftTimer_t **pp = &g_active_head;
    while ( *pp != NULL ) {
        if ( *pp == t ) {
            *pp = t->next;
            t->next = NULL;
            return;
        }
        pp = &( *pp )->next;
    }
}

void Soft_Timer_Init( SoftTimer_t *t, SoftTimerCb cb )
{
    /* Ре-Init того самого об'єкта (LoRaMac робить це при переініціалізації
     * MAC) не сміє лишити хвіст у списку. */
    if ( in_active_list( t ) ) unlink_timer( t );
    t->next      = NULL;
    t->callback  = cb;
    t->context   = NULL;
    t->period_ms = 0u;
    t->target_ms = 0u;
    t->IsRunning   = 0u;
}

void Soft_Timer_Set_Value( SoftTimer_t *t, uint32_t ms )
{
    /* Контракт UTIL_TIMER_SetPeriod: значення міняється на зупиненому —
     * якщо біжить, перезарядиться новим періодом з наступного Start.
     * 0 мс легальний (спрацює на найближчому диспатчі). */
    t->period_ms = ms;
}

void Soft_Timer_Start( SoftTimer_t *t )
{
    if ( t->callback == NULL ) return; /* неініціалізований — глухий */
    t->target_ms = Soft_Timer_Now_Ms( ) + t->period_ms;
    t->IsRunning   = 1u;
    if ( !in_active_list( t ) ) {
        t->next       = g_active_head;
        g_active_head = t;
    }
}

void Soft_Timer_Stop( SoftTimer_t *t )
{
    t->IsRunning = 0u;
    unlink_timer( t );
}

uint32_t Soft_Timer_Elapsed_Since( uint32_t past_ms )
{
    return (uint32_t)( Soft_Timer_Now_Ms( ) - past_ms ); /* wrap-safe */
}

/* Стеля спрацювань за ОДИН Dispatch: period-0 self-restart інакше крутив
 * би цикл вічно повз deadline (0 >= 0 істинне і зі свіжим now) — polling-
 * цикл викликача повторить Dispatch, прогрес системи не губиться. */
#define SOFT_TIMER_DISPATCH_CAP 32u

uint32_t Soft_Timer_Dispatch( void )
{
    uint32_t fired = 0u;
    uint32_t now   = Soft_Timer_Now_Ms( );
    SoftTimer_t *t = g_active_head;

    while ( t != NULL && fired < SOFT_TIMER_DISPATCH_CAP ) {
        /* next знімаємо ДО callback'а: він може Stop/Start себе чи сусіда. */
        SoftTimer_t *next = t->next;
        if ( t->IsRunning && (int32_t)( now - t->target_ms ) >= 0 ) {
            /* one-shot: спершу зняти, потім кликати — callback має право
             * перезапустити таймер, і це не сміє загубитись. */
            Soft_Timer_Stop( t );
            if ( t->callback != NULL ) t->callback( t->context );
            fired++;
            /* Список міг перешитись callback'ом — рестарт з голови.
             * [transitional] O(n²)-рестарт: n ≈ десяток MAC-таймерів, стеля
             * свідома. `now` РЕ-СЕМПЛИМО: період-0 + self-restart проти
             * застиглого `now` крутився б вічно повз deadline (code-review). */
            now = Soft_Timer_Now_Ms( );
            t   = g_active_head;
            continue;
        }
        t = next;
    }
    return fired;
}
