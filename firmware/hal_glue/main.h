/*
 * main.h — [FW.46] CubeMX-контракт для soldier/main.c + queen/main.c
 * (owned-замінник, поки .ioc/board-freeze 👤 не народить справжній).
 *
 * Обидва main.c включають "main.h" першим — CubeMX кладе сюди HAL-парасольку,
 * пін-мапу і прототипи. Пін-мапи тут НЕМАЄ свідомо: розводка = рішення
 * board-freeze (HW), main.c користується лише generic GPIO_Pin аргументами.
 * Канон: docs/03_01 §12.4 (HAL compile-lane).
 */
#ifndef SILKEN_MAIN_H
#define SILKEN_MAIN_H

#include "stm32wlxx_hal.h"

/* Визначений у кожному main.c (CubeMX-конвенція). */
void Error_Handler(void);

#endif /* SILKEN_MAIN_H */
