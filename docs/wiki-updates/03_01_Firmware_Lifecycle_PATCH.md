# PATCH: 03_01_Firmware_Lifecycle_and_DMA

## Що додати (нотатка N6 — STM32CubeIDE для розробки прошивки)

### Де вставити

Знайди метадані модуля (на самому початку, після рядків "Поточний TRL", "Цільовий TRL"):

```
> **⚠️ SSOT Sync:** Цей документ синхронізовано з `firmware/soldier/main.c`...
```

Вставити **одразу після** блоку `> **⚠️ SSOT Sync:**...` і **перед** `## 🎯 Мета (Objective)`:

---

```markdown
## 🛠️ Development Toolchain (Інструменти Розробки)

> **Нотатка N6 інтегрована (Сесія 2).** Інструменти для розробки та тестування прошивки STM32WLE5JC до отримання фізичних плат.

### STM32CubeIDE

| Аспект | Деталі |
|--------|--------|
| **Призначення** | Повноцінна C/C++ IDE для STM32WLE5JC (ARM Cortex-M4 + SX1262 LoRa) |
| **Включає** | STM32CubeMX — графічний конфігуратор GPIO, тактових дерев, периферії |
| **Порт** | Налаштування GPIO pinout (PA9/PA10 UART, ADC, TIM2 DMA, RNG, CRYP) до отримання плат |
| **Clock Tree** | Конфігурація HSE/LSE для STOP2 ultra-low-power режиму (2.1 µA) |
| **HAL drivers** | Auto-генерація ініціалізаційного коду для I2C/SPI/ADC/UART/RTC/CRYP |
| **Debugger** | Інтеграція з ST-LINK-V3MINIE: breakpoints, live variable watch, SWO trace |
| **Збірка** | GCC ARM Embedded toolchain (вбудований у CubeIDE); той самий компілятор що й для host-тестів |

**Що можна зробити до отримання фізичних плат:**
1. Налаштувати повний Pinout у STM32CubeMX для обох прошивок (Soldier та Queen)
2. Сконфігурувати Clock Tree для STOP2 (MSI 100 kHz active clock, LSE 32.768 kHz для RTC)
3. Підготувати HAL-ініціалізацію для всіх периферій (ADC, TIM2 DMA, IWDG, RNG, CRYP, SUBGHZ)
4. Запустити host-based тести (make -C firmware/test) без будь-якого ARM toolchain
5. Запустити Wokwi-симуляцію для логіки сенсорів та пакетного формату

### Host-Based Tests (без CubeIDE, без плат)

```bash
# Запуск всіх 112 тестів на x86 (не потрібен ARM toolchain)
make -C firmware/test

# Тільки Soldier:
make -C firmware/test soldier

# Тільки Queen:
make -C firmware/test queen
```

Компілятор: `gcc` (системний x86). Тести покривають: CIFO, AES, Lorenz, OTA, Mesh, CRC32, DID-генерацію.

---
```
