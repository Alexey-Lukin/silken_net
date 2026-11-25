// SPDX-License-Identifier: AGPL-3.0-or-later
/*
 * logger_journal.h — [FW.70] сторінковий журнал логера пілота П3 у внутрішній Flash.
 *
 * Навіщо власний носій: Flash-KV — ключ/значення (компакція лишає ОСТАННЄ значення
 * ключа, тож ряду вимірів без окремої схеми ключів не тримає), flash_ring — кільце
 * Королеви на SPI NOR, якого на mini немає (00_07 FW.70). Форма — присуд «П3 — склад
 * пілота» (01_03 §4 ⊕): каденс 30 хв, два виміри в одне подвійне слово, час — від
 * мітки, після скиду — маркер часу.
 *
 * Розкладка: одиниця запису — подвійне слово (dw, 8 Б). На WLE5 програмується лише
 * ціле dw, повторно — ніколи (PROGERR), стерте = 0xFF…FF. Тип стоїть у старшому
 * ніблі, тож валідний запис стертим не буває.
 *   DATA    тип 0x1: [63:60]=1 · [59:48] слот A · [47:40] темп. B · [39:24] показ B
 *                    · [23:16] темп. A · [15:0] показ A
 *   ЯКІР    тип 0x2 (відновлення) · 0x3 (заголовок сторінки — dw 0 кожної сторінки):
 *                    [63:60] тип · [59:56] прапорці (b0 — час виставлено) · [55:48] каденс, хв
 *                    · [47:32] тег: відновлення — (причина<<8) | код скиду; заголовок сторінки —
 *                      [47:40] seq · [39:32] CRC-8 решти заголовка (logj_crc8)
 *                    · [31:0] секунди: якір відновлення — читання RTC; заголовок
 *                      сторінки — сітковий час першого виміру сторінки
 * Час виміру A = секунди останнього якоря + слот × каденс; B — наступний слот. Слот
 * ЯВНИЙ: пропущене пробудження не зсуває наступних міток.
 *
 * Сентинели показу (12-біт АЦП ×16 оверсемплінгу дає ≤ 65520, тож обидва недосяжні):
 *   LOGJ_READING_NONE   0xFFFF — пристрій прокинувся, але поміряти не зміг: рядок «NA»
 *                        (00_05 §7 — відсутність малюють, нулем не підміняють);
 *   LOGJ_READING_CLOSED 0xFFFE — половина B пари, обірваної якорем чи пропуском
 *                        пробудження: слота не було, рядка в дампі немає — розрив видно
 *                        з міток часу, а «не виміряно» не стверджується про те, чого не міряли.
 * Температура — int8 у пів-градусах °C, −63.5…+63.5 (сентинел LOGJ_TEMP_NONE = INT8_MIN).
 * Перерахунок показу в мкм — справа декодера на стенді, не прошивки.
 *
 * Сітка й годинник: мітка — сітковий час, тож вона точна, лише коли пробудження
 * періодичне на ТОМУ САМОМУ годиннику (WUT з автоперезавантаженням від RTC). Якщо
 * період зʼїжджає (WUT переармовують після роботи), розходження з сіткою росте, і щойно
 * воно перевищить чверть каденсу, журнал сам пише якір (причина GAP): похибка мітки
 * лишається ≤ каденс/4, а тихого зсуву не буває. Дрейф самого LSI проти справжнього
 * часу сітка не лікує — його бачить лише референс.
 *
 * Кільце, не «стоп при заповненні»: свідок росту — весна, тож за запізнілого зчитування
 * гине найстаріше, а не найновіше. Гарантована історія — (сторінок − 1) повних сторінок,
 * бо наступна стирається перед відкриттям (LOGJ_GUARANTEED_MEAS) — і без якорів: кожен
 * якір відновлення зʼїдає dw, а обірвана пара — ще пів dw.
 *
 * Межі, названі вголос:
 *   · перша половина пари живе в RAM до наступного виміру — скид між ними губить ОДИН
 *     вимір (Flash WL не дописує половину dw). Під Standby (FW.54) SRAM гине на кожному
 *     пробудженні — тоді пара мусить жити поза SRAM (firmware #22); образ mini спить у STOP2;
 *   · зчитування бачить Flash, тож останній непарний вимір (≤ один каденс) у дамп не входить;
 *   · відмова програмування DATA → лічильник write_fail, dw пропускається (повторне
 *     програмування дало б PROGERR), пара втрачена; відмова програмування ЗАГОЛОВКА
 *     лишає сторінку закритою — сторінка без валідного якоря зробила б невидимими всі
 *     виміри на ній; відмова ЯКОРЯ відновлення — повтор на тій самій сторінці, далі
 *     сторінку закрито (слоти без записаного якоря датувались би хибно); відмова стирання
 *     — береться наступна сторінка, а стара виходить із вікна дампу, щойно після неї відкриється
 *     інша (після повернення до голови мертві сторінки серії знову у вікні — logj_open_next).
 *     Провал заголовка ставить
 *     експоненційну паузу (LOGJ_HOLD_MAX) — видно через LogJ_Holding; монтування її
 *     скидає, тож у петлі скидів кожен старт стирає ту саму наступну сторінку: історія
 *     ціла, але знос цієї сторінки росте (10 тис. циклів — ≈ 4 доби петлі на 33 с), і
 *     глю HAL проходить стенд (програмування + перечитування) до поля;
 *   · журнал закритий або в паузі → поточний вимір не тримається в RAM, а губиться;
 *   · якір BOOT заряджають на старті, а пишуть перед першим записом старту (LogJ_Arm_Boot):
 *     петлі скидів, що до запису не доходить, журнал не бачить зовсім, а петля, що доходить
 *     до виміру, пише dw на кожен старт (половина пари гине з RAM) — стільки стартів, скільки
 *     dw у кільці, затирають історію, і проти цього журнал беззбройний;
 *   · період WUT ≠ каденс більш ніж на чверть → кожне пробудження пише якір розриву й
 *     закриту половину: ≈ 4× місця, і гарантія 180 діб падає до ≈ 45 — період WUT
 *     дорівнює каденсу журналу за побудовою інтеграції;
 *   · dw, обірваний посеред програмування, може читатися на WL з ECC double error і NMI;
 *     тоді перевірене читання глю віддає його як 0 (common/flash_eccd.h):
 *     монтування його пропускає, курсор поверх нього не програмує, дамп друкує
 *     «#X,0000000000000000». Порваний dw, чий ECC вийшов узгодженим, ляже в дамп як є, а
 *     той, що читається стертим, курсор програмує поверх — CRC має лише заголовок сторінки
 *     (стелі — шапка flash_eccd.h); що NMI на кремнії відпрацьовує саме так — стенд;
 *   · обірване СТИРАННЯ найстарішої сторінки лишає її заголовок у будь-якому стані, тож
 *     монтування й дамп беруть сторінку лише з валідним CRC-8 заголовка: напівстертий заголовок,
 *     чий seq поповз, найновішою не стає — крім рідкісного збігу CRC. Будь-яку зміну 1–3 біт
 *     заголовка CRC ловить гарантовано (тест — повний перебір; CRC лінійний, тож виявлення
 *     залежить лише від візерунка зміни, а не від заголовка); довільне сміття з ніблем типу
 *     заголовка проходить ≈ 1 раз на 256 (≈ 1/340 — перебір 2·10⁶ випадкових підйомів бітів,
 *     кожен біт незалежно, нібл типу збережено; модель, не кремній). Це ціна ОДНОГО обірваного
 *     стирання: петля скидів, що щоразу обриває стирання тієї самої сторінки, тягне жереб знову
 *     на кожному старті, а сміття, що проскочило й читається найновішим, зсуває вікно дампу з
 *     усієї справжньої історії (на Flash вона лишається, доки кільце до неї не дійде).
 *     Правдоподібності seq на монтуванні немає: правило «найновіший не випереджає наступного
 *     більш ніж на n − 1» у журналі з однією справжньою сторінкою й сміттям нижче відкинуло б
 *     справжню. Заголовок, що вцілів, лишає сторінку найстарішою, і її вже частково стерте тіло
 *     ляже в дамп як є, доки наступне відкриття не зітре її знову. Ланцюг seq на монтуванні
 *     цього не заміняє: заголовок, що поповз рівно в «найновіший + 1», за самим seq не
 *     відрізнити від щойно відкритої сторінки, а мертве стирання законно рве ланцюг;
 *   · стирання, що повернуло успіх, але лишило нестертий dw (наприклад, сторінка, зношена
 *     петлею скидів), — така сама мертва сторінка, як відмова стирання: заголовок лягає лише на
 *     перевірено стерту; голову ж кільце не стирає ніколи — після n − 1 мертвих поспіль журнал
 *     вертається до неї й стає на паузу (logj_open_next);
 *   · seq — 8 біт (решта тега — CRC). Мертва сторінка, чий заголовок відстав на
 *     128 кроків seq і більше (крок — відкриття й мертві стирання перед ним; без мертвих стирань це
 *     ≈ 3.7 року на сторінці 2 КБ і каденсі 30 хв, з ними — раніше), читалась би найновішою.
 *     Мертві стирання зсувають seq не далі ніж на n − 1 від голови, тож живі seq лежать у межах
 *     2n − 1 < 128 — звідси n_pages ≤ LOGJ_PAGES_MAX;
 *   · кожен писач календаря кличе LogJ_Settle_Boot ДО запису й LogJ_Anchor(TIME_SET) після:
 *     інакше якір BOOT ляже з новим часом і старим прапорцем, а прапорець «час виставлено»
 *     не стане 1 до наступного якоря. Консоль (logger_console.h) робить обидва кроки сама,
 *     застосування маяка (Silken_Beacon_Receive) — ні: образ із радіо й журналом мусить додати;
 *   · сигнатури формату немає: регіон на першому монтуванні мусить бути стертим, інакше
 *     чужий dw із ніблем типу заголовка став би сторінкою, а з ніблем DATA — виміром у
 *     дампі. На mini це дає mass-erase першої прошивки (вихід із RDP-L1, 02_04); прошивка
 *     образу регіону не торкається — журнал переживає перепрошивку.
 *
 * One-Home: прошивка й host-тести компілюють цей самий код; залізо — лише LogJOps.
 * Канон: 00_07 FW.70 · 01_03 §4 ⊕ «П3 — склад пілота» · 03_01 §12.4.
 */
#ifndef SILKEN_LOGGER_JOURNAL_H
#define SILKEN_LOGGER_JOURNAL_H

#include <stddef.h>
#include <stdint.h>

#define LOGJ_TYPE_DATA      0x1u
#define LOGJ_TYPE_RESUME    0x2u
#define LOGJ_TYPE_PAGE      0x3u

/* Нечитабельний dw (обірваний посеред програмування, що на WL дав ECC double error і NMI)
 * перевірене читання глю віддає як 0 — common/flash_eccd.h. Тип 0 журнал не пише ніколи, тож нуль не є ні записом, ні
 * стертим. Новий тип запису — лише ненульовий. */
#define LOGJ_UNREADABLE_DW  0ull
_Static_assert(LOGJ_TYPE_DATA != 0u && LOGJ_TYPE_RESUME != 0u && LOGJ_TYPE_PAGE != 0u,
               "[FW.70] тип 0 зарезервовано за нечитабельним dw (flash_eccd.h)");

#define LOGJ_READING_NONE   0xFFFFu
#define LOGJ_READING_CLOSED 0xFFFEu
#define LOGJ_TEMP_NONE      INT8_MIN
#define LOGJ_SLOT_MAX       0x0FFFu
#define LOGJ_FLAG_TIME_VALID 0x1u

/* Заголовок сторінки: seq 8 біт + CRC-8 (поліном 0x07, init 0xFF, без рефлексії й xorout) над
 * усім dw із нулем на місці CRC, старшим бітом першим. Поліном обрано виміром: у цій розкладці
 * (CRC посеред dw) він ловить кожну зміну 1–3 біт, а частина поширених (0x1D · 0x39 · 0x4D) —
 * ні; пін — host-тест повним перебором. 8-бітний seq тримає порядок, доки живі seq лежать
 * у межах 2n − 1 < 128 — звідси стеля кількості сторінок (шапка, «Межі»). */
#define LOGJ_PAGE_CRC_POLY  0x07u
#define LOGJ_PAGE_CRC_INIT  0xFFu
#define LOGJ_PAGES_MAX      64u

#define LOGJ_REASON_BOOT     0u   /* старт прошивки (код скиду — в молодшому байті тега) */
#define LOGJ_REASON_TIME_SET 1u   /* час виставлено через UART */
#define LOGJ_REASON_GAP      2u   /* розрив без скиду: годинник назад · той самий слот ·
                                     слот > 4095 · мітка розійшлась із сіткою > каденс/4 */

/* Пауза після провалу заголовка (стирання вдалося, програмування — ні). За стійкої відмови
 * програмування (помилка глю: зсув, вирівнювання, незняті прапорці) нових даних не записати
 * однаково, а під загрозою лише історія; за короткої (просідання живлення) — усе майбутнє.
 * Тож не замок, а експоненційна пауза: наступна спроба через 1, 2, 4 … LOGJ_HOLD_MAX викликів
 * запису (≈ доба на каденсі 30 хв), і бʼє вона в ту саму стерту сторінку. Короткий збій коштує
 * кілька вимірів і минає сам; стійка відмова — одну сторінку історії і ≈ 6 стирань тієї самої
 * сторінки першої доби, далі одне на добу. Відмова стирання даних не нищить і паузи не
 * ставить — друга спроба в тому ж виклику бере наступну сторінку, — доки мертвих поспіль менше
 * за n − 1: тоді журнал вертається до голови й стає на ту саму паузу. Стирання, що вдалося, але
 * лишило сторінку нестертою, дані вже стерло; системне «нестерто» (хибне перечитування) стерло б
 * так до n − 1 сторінок за серію — кеш даних Flash HAL_FLASHEx_Erase скидає сам (FLASH_FlushCaches),
 * інші джерела — стенд. */
#define LOGJ_HOLD_MAX 48u

/* Скільки вимірів кільце тримає гарантовано (без якорів відновлення). */
#define LOGJ_GUARANTEED_MEAS(n_pages, page_dws) \
    ((uint32_t)((n_pages) - 1u) * (uint32_t)((page_dws) - 1u) * 2u)

/* Залізні примітиви. byte_off — від бази регіону журналу, кратний 8.
 * program/erase: 1 = успіх, 0 = відмова. */
typedef struct {
    uint64_t (*read_dw)(void *io, uint32_t byte_off);
    int      (*program_dw)(void *io, uint32_t byte_off, uint64_t v);
    int      (*erase_page)(void *io, uint8_t page);
} LogJOps;

typedef struct {
    const LogJOps *ops;
    void          *io;
    uint16_t       page_dws;
    uint8_t        n_pages;     /* 0 = журнал не змонтовано (хибна конфігурація) */
    uint8_t        cfg_cad;     /* каденс, який пишуть нові якорі, хв */
    uint8_t        open;        /* 1 = є відкрита сторінка */
    uint8_t        cur;         /* відкрита (або остання спробувана) сторінка */
    uint8_t        seq;         /* її seq */
    uint8_t        dead_run;    /* мертві стирання поспіль від голови: курсор і seq зсунуті на стільки ж (≤ n − 1) */
    uint16_t       widx;        /* перший вільний dw відкритої сторінки */
    uint32_t       anchor_s;    /* секунди останнього якоря */
    uint8_t        flags;       /* прапорці останнього якоря */
    uint8_t        cad;         /* каденс останнього якоря, хв — ним рахують слоти */
    uint8_t        last_valid;  /* 1 = last_g значущий */
    uint8_t        pend;        /* 1 = перша половина пари чекає в RAM */
    uint32_t       last_g;      /* сітковий час останнього зайнятого слота (разом із B і очікуваним) */
    uint32_t       pend_g;
    uint16_t       pend_reading;
    int8_t         pend_temp;
    uint32_t       write_fail;
    uint8_t        hold;        /* скільки викликів запису ще чекати до спроби відкриття */
    uint8_t        hold_len;    /* довжина наступної паузи; 0 = серії провалів немає */
    uint8_t        boot_pend;   /* 1 = якір BOOT чекає першого запису цього старту */
    uint8_t        boot_cause;  /* його код скиду (reset_cause.h) */
    uint8_t        boot_tv;     /* його прапорець «час виставлено» — як був на старті */
} LogJ;

/* ── кодування ─────────────────────────────────────────────────────── */

static inline uint8_t LogJ_Type(uint64_t dw) { return (uint8_t)(dw >> 60); }

static inline uint64_t LogJ_Pack_Data(uint16_t slot, uint16_t ra, int8_t ta, uint16_t rb, int8_t tb)
{
    return ((uint64_t)LOGJ_TYPE_DATA << 60) | ((uint64_t)(slot & LOGJ_SLOT_MAX) << 48)
         | ((uint64_t)(uint8_t)tb << 40) | ((uint64_t)rb << 24)
         | ((uint64_t)(uint8_t)ta << 16) | (uint64_t)ra;
}

static inline uint64_t LogJ_Pack_Anchor(uint8_t type, uint8_t flags, uint8_t cad_min,
                                        uint16_t tag, uint32_t secs)
{
    return ((uint64_t)(type & 0xFu) << 60) | ((uint64_t)(flags & 0xFu) << 56)
         | ((uint64_t)cad_min << 48) | ((uint64_t)tag << 32) | (uint64_t)secs;
}

/* CRC-8 заголовка сторінки над dw із нулем на місці CRC ([39:32]) — параметри й чому цей поліном
 * — біля LOGJ_PAGE_CRC_POLY. */
static inline uint8_t logj_crc8(uint64_t dw)
{
    dw &= ~(0xFFull << 32);
    uint8_t c = LOGJ_PAGE_CRC_INIT;
    for (int i = 63; i >= 0; i--) {
        uint8_t in = (uint8_t)(((dw >> i) & 1u) ^ (uint8_t)(c >> 7));
        c = (uint8_t)(c << 1);
        if (in) c ^= LOGJ_PAGE_CRC_POLY;
    }
    return c;
}

static inline uint64_t LogJ_Pack_Page(uint8_t flags, uint8_t cad_min, uint8_t seq, uint32_t secs)
{
    uint64_t dw = LogJ_Pack_Anchor(LOGJ_TYPE_PAGE, flags, cad_min, (uint16_t)((uint16_t)seq << 8), secs);
    return dw | ((uint64_t)logj_crc8(dw) << 32);
}

/* 1 = валідний заголовок сторінки: тип PAGE і CRC збігся. Інший dw із ніблем PAGE — сміття
 * (напівстерта сторінка, порваний заголовок): ні сторінкою, ні якорем він не стає. */
static inline int logj_page_ok(uint64_t dw)
{
    return LogJ_Type(dw) == LOGJ_TYPE_PAGE && (uint8_t)(dw >> 32) == logj_crc8(dw);
}

static inline uint8_t logj_page_seq(uint64_t dw) { return (uint8_t)(dw >> 40); }

/* Температура BME280 (соті °C) → пів-градуси з округленням; поза ±63.5 — стеля діапазону. */
static inline int8_t LogJ_Temp_From_Centi(int32_t centi)
{
    if (centi <= -6350) return -127;
    if (centi >= 6350)  return 127;
    int32_t h = (centi >= 0) ? (centi + 25) / 50 : -((-centi + 25) / 50);
    return (int8_t)h;
}

/* ── внутрішнє ─────────────────────────────────────────────────────── */

static inline uint64_t logj_rd(const LogJ *j, uint8_t page, uint16_t idx)
{
    return j->ops->read_dw(j->io, ((uint32_t)page * j->page_dws + idx) * 8u);
}

/* Викликач гарантує місце. Індекс рухається й на відмові: dw міг лишитись частково
 * запрограмованим, а повторне програмування на WL — PROGERR. */
static inline int logj_put(LogJ *j, uint64_t v)
{
    int ok = j->ops->program_dw(j->io, ((uint32_t)j->cur * j->page_dws + j->widx) * 8u, v);
    j->widx++;
    if (!ok) j->write_fail++;
    return ok;
}

/* 1 = кожен dw сторінки стертий. Стирання, що повернуло успіх, ще не каже, що сторінка чиста
 * (знос у петлі скидів; чи знімає повторне стирання слід обірваного — RM0461 не прочитано), —
 * заголовок лягає лише на перевірено стерту (взірець — VerifyPageFullyErased порту X-CUBE-EEPROM
 * для STM32WL). */
static inline int logj_erased(const LogJ *j, uint8_t page)
{
    for (uint16_t i = 0; i < j->page_dws; i++)
        if (logj_rd(j, page, i) != UINT64_MAX) return 0;
    return 1;
}

/* Наступна експоненційна пауза відкриття (LOGJ_HOLD_MAX): провал заголовка й «мертві всі, крім
 * голови» ділять одну серію — обидва кажуть «сторінку зараз не відкрити». */
static inline void logj_hold(LogJ *j)
{
    uint16_t len = j->hold_len ? (uint16_t)(2u * j->hold_len) : 1u;
    j->hold_len = (uint8_t)(len < LOGJ_HOLD_MAX ? len : LOGJ_HOLD_MAX);
    j->hold = j->hold_len;
}

/* Відкрити наступну сторінку кільця із заголовком-якорем на t_s. Сторінка без записаного
 * заголовка лишається закритою — дані на неї не лягають. Мертве стирання (відмова або сторінка,
 * що лишилась нестертою) зсуває курсор (далі — інша сторінка) і seq — щоб мертва сторінка зі
 * старим seq вийшла з вікна дампу. Після n − 1 мертвих поспіль наступною ціллю була б сама
 * голова — найновіша сторінка; її кільце не стирає: курсор і seq вертаються до неї, журнал
 * закритий, пауза, а після паузи спроби йдуть знову з наступної за головою (відновлене стирання
 * відкриє мертві сторінки, голова ціла; доти мертві сторінки серії знову у вікні дампу — цілі,
 * якщо стирання так і не стартувало; голова, закрита посеред сторінки — провал якоря двічі, —
 * після повернення лишається закритою до перемонтування, тож пауза стоїть при вільних dw; першу
 * паузу повернення може зʼїсти другий виклик logj_room у тому самому записі). Тож seq за серію
 * відмов не відходить від голови далі ніж на n − 1, і порядок 8-бітних seq не плутається; у порожньому журналі голови немає, і так
 * само береже сторінку n − 1. Провал заголовка не зсуває нічого: наступна спроба бʼє в ту саму
 * вже стерту сторінку, тож стійка відмова програмування коштує одну сторінку історії, а не кільце. */
static inline int logj_open_next(LogJ *j, uint32_t t_s)
{
    j->open = 0;
    if (j->dead_run >= (uint8_t)(j->n_pages - 1u)) {
        j->cur = (uint8_t)((j->cur + j->n_pages - j->dead_run) % j->n_pages);
        j->seq = (uint8_t)(j->seq - j->dead_run);
        j->dead_run = 0;
        logj_hold(j);
        return 0;
    }
    uint8_t page     = (uint8_t)((j->cur + 1u) % j->n_pages);
    uint8_t prev_cur = j->cur;
    uint8_t prev_seq = j->seq;
    j->cur = page;
    j->seq = (uint8_t)(prev_seq + 1u);
    if (!j->ops->erase_page(j->io, page) || !logj_erased(j, page)) {
        j->dead_run++;
        j->write_fail++;
        return 0;
    }
    j->widx = 0;
    if (!j->cad) j->cad = j->cfg_cad;
    if (!logj_put(j, LogJ_Pack_Page(j->flags, j->cad, j->seq, t_s))) {
        logj_hold(j);
        j->cur = prev_cur;
        j->seq = prev_seq;
        return 0;
    }
    j->open = 1;
    j->hold = 0;
    j->hold_len = 0;
    j->dead_run = 0;
    j->anchor_s = t_s;
    return 1;
}

/* Місце для одного dw. Одна мертва сторінка не губить запису (друга спроба — наступна, якщо це
 * не повернення до голови);
 * провал заголовка ставить паузу LOGJ_HOLD_MAX і другої спроби не робить. */
static inline int logj_room(LogJ *j, uint32_t header_t_s)
{
    if (j->open && j->widx < j->page_dws) return 1;
    if (j->hold) { j->hold--; return 0; }
    for (int k = 0; k < 2; k++) {
        if (logj_open_next(j, header_t_s)) return 1;
        if (j->hold) return 0;
    }
    return 0;
}

/* 1 = журнал у паузі (провал заголовка або повернення до голови): записи губляться, доки пауза
 * не мине. Інтеграція друкує це в рядку стану дампу — інакше пауза мімікрує під сіту батарею.
 * ⚠️ Консоль образу mini живе лише на старті, одразу після монтування, тож там пауза завжди 0,
 * а серія мертвих стирань до повернення паузи не ставить зовсім. */
static inline int LogJ_Holding(const LogJ *j) { return !j->open && j->hold_len != 0u; }

/* Записати пару, чия половина A стоїть на сітковому часі g_a. Повна сторінка → заголовок
 * нової стає якорем саме цього виміру (слот 0). */
static inline int logj_emit(LogJ *j, uint32_t g_a, uint16_t ra, int8_t ta, uint16_t rb, int8_t tb)
{
    if (!logj_room(j, g_a)) return 0;
    uint32_t cad_s = 60u * j->cad;
    uint16_t slot  = (uint16_t)((g_a - j->anchor_s) / cad_s);
    return logj_put(j, LogJ_Pack_Data(slot, ra, ta, rb, tb));
}

/* Записати очікувану половину пари з закритою B (слота B не існує). */
static inline int logj_flush(LogJ *j)
{
    if (!j->pend) return 1;
    j->pend = 0;
    return logj_emit(j, j->pend_g, j->pend_reading, j->pend_temp, LOGJ_READING_CLOSED, LOGJ_TEMP_NONE);
}

/* ── API ───────────────────────────────────────────────────────────── */

/* Змонтувати наявний журнал або прийняти порожній. Половину пари, що жила в RAM, не
 * відновити — вона загинула разом зі скидом.
 * Повертає 1 = знайдено відкриту сторінку · 0 = журнал порожній · −1 = хибна конфігурація
 * (тоді Anchor/Record відмовляють, ітератор порожній). */
static inline int LogJ_Mount(LogJ *j, const LogJOps *ops, void *io,
                             uint16_t page_dws, uint8_t n_pages, uint8_t cfg_cad_min)
{
    *j = (LogJ){0};
    if (!ops || page_dws < 2u || n_pages < 2u || n_pages > LOGJ_PAGES_MAX || cfg_cad_min == 0u)
        return -1;
    j->ops = ops; j->io = io; j->page_dws = page_dws; j->n_pages = n_pages;
    j->cfg_cad = cfg_cad_min;

    int found = 0;
    uint8_t best = 0;
    for (uint8_t p = 0; p < n_pages; p++) {
        uint64_t h = logj_rd(j, p, 0);
        if (!logj_page_ok(h)) continue;    /* напівстертий чи порваний заголовок — не сторінка */
        uint8_t s = logj_page_seq(h);
        if (!found || (int8_t)(uint8_t)(s - best) > 0) { best = s; j->cur = p; found = 1; }
    }
    if (!found) {                          /* порожній: перше відкриття візьме сторінку 0, seq 0 */
        j->cur = (uint8_t)(n_pages - 1u);
        j->seq = UINT8_MAX;
        return 0;
    }
    j->seq = best;
    j->open = 1;

    uint16_t last = 0;                     /* останній непорожній dw — дірка від відмови не зупиняє */
    for (uint16_t i = (uint16_t)(page_dws - 1u); i > 0; i--)
        if (logj_rd(j, j->cur, i) != UINT64_MAX) { last = i; break; }
    j->widx = (uint16_t)(last + 1u);

    for (uint16_t i = 0; i < j->widx; i++) {
        uint64_t dw = logj_rd(j, j->cur, i);
        uint8_t  t  = LogJ_Type(dw);
        if ((t == LOGJ_TYPE_PAGE && logj_page_ok(dw)) || t == LOGJ_TYPE_RESUME) {
            j->anchor_s   = (uint32_t)dw;
            j->flags      = (uint8_t)((dw >> 56) & 0xFu);
            j->cad        = (uint8_t)(dw >> 48);
            j->last_valid = 0;
        } else if (t == LOGJ_TYPE_DATA && j->cad) {
            uint32_t cad_s = 60u * j->cad;
            uint32_t g_a   = j->anchor_s + (uint32_t)((dw >> 48) & LOGJ_SLOT_MAX) * cad_s;
            j->last_g      = ((uint16_t)(dw >> 24) == LOGJ_READING_CLOSED) ? g_a : g_a + cad_s;
            j->last_valid  = 1;
        }
    }
    return 1;
}

/* Тіло якоря відновлення (без зарядженого BOOT — його бере LogJ_Anchor). */
static inline int logj_anchor(LogJ *j, uint32_t now_s, uint8_t time_valid,
                              uint8_t reason, uint8_t reset_cause)
{
    int ok = logj_flush(j);
    j->flags = time_valid ? LOGJ_FLAG_TIME_VALID : 0u;
    j->cad   = j->cfg_cad;
    uint16_t seq0 = j->seq;
    if (!logj_room(j, now_s)) return 0;
    int fresh = (j->seq != seq0);  /* заголовок щойно відкритої сторінки вже є якорем на now_s */
    uint64_t a = LogJ_Pack_Anchor(LOGJ_TYPE_RESUME, j->flags, j->cad,
                                  (uint16_t)(((uint16_t)reason << 8) | reset_cause), now_s);
    if (!logj_put(j, a)) {
        /* Слоти мусять рахуватись від якоря, який бачить декодер. Свіжа сторінка — якір уже
         * є (втрачено лише тег причини). Інакше — одна повторна спроба на тій самій сторінці,
         * без стирання; не вдалась — сторінку закрито, і наступний запис відкриє нову. */
        ok = 0;
        if (!fresh) {
            if (j->widx < j->page_dws) {
                if (!logj_put(j, a)) { j->open = 0; return 0; }
            } else if (!logj_room(j, now_s)) {
                return 0;
            }
        }
    }
    j->anchor_s   = now_s;
    j->last_valid = 0;
    return ok;
}

/* Зарядити якір BOOT на старті (після LogJ_Mount): код скиду й «час виставлено», як вони
 * є на старті. Пишеться він НЕ тут, а перед першим записом цього старту — виміром чи
 * якорем: петля скидів, що до запису не доходить, журналу не торкається. Якір на кожному
 * старті коштував би dw за скид, і петля затерла б кільце за години — а свідок росту весна. */
static inline void LogJ_Arm_Boot(LogJ *j, uint8_t reset_cause, uint8_t time_valid)
{
    if (!j->n_pages) return;
    j->boot_pend  = 1;
    j->boot_cause = reset_cause;
    j->boot_tv    = time_valid ? 1u : 0u;
}

/* Записати заряджений якір BOOT, якщо він є. Одна спроба: провал губить лише тег причини,
 * а прапорець часу старту не ляже пізніше поверх новішого якоря. Виставлення часу кличе це
 * ДО запису календаря, щоб якір ніс старий час. 1 = нічого не чекало або записано. */
static inline int LogJ_Settle_Boot(LogJ *j, uint32_t now_s)
{
    if (!j->n_pages) return 0;
    if (!j->boot_pend) return 1;
    j->boot_pend = 0;
    return logj_anchor(j, now_s, j->boot_tv, LOGJ_REASON_BOOT, j->boot_cause);
}

/* Якір відновлення: виставлення часу (reason TIME_SET), розрив (GAP) — і BOOT, хоча на
 * старті його заряджають (LogJ_Arm_Boot), а не пишуть. Заряджений BOOT лягає першим.
 * Очікувана половина пари спершу пишеться з закритою B. */
static inline int LogJ_Anchor(LogJ *j, uint32_t now_s, uint8_t time_valid,
                              uint8_t reason, uint8_t reset_cause)
{
    if (!j->n_pages) return 0;
    int ok = LogJ_Settle_Boot(j, now_s);
    return logj_anchor(j, now_s, time_valid, reason, reset_cause) & ok;
}

/* Один вимір на пробудженні. now_s — секунди RTC. reading = LOGJ_READING_NONE, коли
 * поміряти не вдалося (рядок «NA»). */
static inline int LogJ_Record(LogJ *j, uint32_t now_s, uint16_t reading, int8_t temp)
{
    if (!j->n_pages) return 0;
    int ok = 1;
    if (j->boot_pend) {
        ok = LogJ_Settle_Boot(j, now_s);
        if (!j->open) return 0;   /* відкрити не вдалось — друга спроба в тому ж виклику зʼїла б паузу */
    }
    if (!j->open || !j->cad) {
        ok &= LogJ_Anchor(j, now_s, (uint8_t)(j->flags & LOGJ_FLAG_TIME_VALID), LOGJ_REASON_GAP, 0u);
        if (!j->open) return 0;
    }

    uint32_t cad_s = 60u * j->cad;
    int gap = (now_s < j->anchor_s);
    uint32_t g = 0;
    if (!gap) {
        uint32_t d = now_s - j->anchor_s;
        uint32_t s = d / cad_s, rem = d % cad_s, err = rem;
        if (rem >= (cad_s + 1u) / 2u) { s++; err = cad_s - rem; }
        g = j->anchor_s + (s <= LOGJ_SLOT_MAX ? s : 0u) * cad_s;
        gap = (s > LOGJ_SLOT_MAX) || (err > cad_s / 4u)
           || (j->last_valid && g <= j->last_g);
    }
    if (gap) {
        ok &= LogJ_Anchor(j, now_s, (uint8_t)(j->flags & LOGJ_FLAG_TIME_VALID), LOGJ_REASON_GAP, 0u);
        if (!j->open) return 0;
        g = now_s;
    }

    if (j->pend) {
        if (g == j->pend_g + cad_s) {
            j->pend = 0;
            ok &= logj_emit(j, j->pend_g, j->pend_reading, j->pend_temp, reading, temp);
            j->last_g = g; j->last_valid = 1;
            return ok;
        }
        ok &= logj_flush(j);           /* пропущене пробудження: B не було */
    }
    j->pend = 1; j->pend_g = g; j->pend_reading = reading; j->pend_temp = temp;
    j->last_g = g; j->last_valid = 1;
    return ok;
}

/* ── зчитування: від найстарішої сторінки до найновішої, за seq ──────
 * Сторінки обходяться за віком seq відносно останнього (age n−1 … 0), не за фізичним
 * номером: сторінка, яку не вдалося стерти, несе старий seq і в дамп не йде, щойно після неї
 * відкрилась інша (після повернення до голови — йде, logj_open_next). */

#define LOGJ_REC_MEAS    1u
#define LOGJ_REC_ANCHOR  2u
#define LOGJ_REC_CORRUPT 3u

typedef struct {
    uint8_t  kind;
    uint8_t  type;        /* ANCHOR: LOGJ_TYPE_PAGE | LOGJ_TYPE_RESUME */
    uint8_t  time_valid;
    uint8_t  cad_min;     /* ANCHOR */
    uint16_t tag;         /* ANCHOR */
    uint32_t t_s;
    uint16_t reading;     /* MEAS */
    int8_t   temp;        /* MEAS */
    uint64_t raw;         /* CORRUPT */
} LogJRec;

typedef struct {
    const LogJ *j;
    uint16_t age;         /* вік наступної сторінки + 1; 0 = сторінки вичерпано */
    uint8_t  page;
    uint8_t  page_ok;
    uint16_t idx;
    uint32_t base_s;
    uint8_t  flags;
    uint8_t  cad;
    uint8_t  have_b;
    LogJRec  b;
} LogJIter;

static inline void LogJ_Iter_Begin(LogJIter *it, const LogJ *j)
{
    *it = (LogJIter){0};
    it->j = j;
    it->age = j->n_pages;
}

static inline int logj_iter_next_page(LogJIter *it)
{
    const LogJ *j = it->j;
    while (it->age > 0) {
        it->age--;
        uint8_t want = (uint8_t)(j->seq - it->age);
        for (uint8_t p = 0; p < j->n_pages; p++) {
            uint64_t h = logj_rd(j, p, 0);
            if (logj_page_ok(h) && logj_page_seq(h) == want) {
                it->page = p; it->idx = 0; it->cad = 0; it->page_ok = 1;
                return 1;
            }
        }
    }
    it->page_ok = 0;
    return 0;
}

/* 1 = запис віддано; 0 = кінець. */
static inline int LogJ_Iter_Next(LogJIter *it, LogJRec *r)
{
    const LogJ *j = it->j;
    if (it->have_b) { *r = it->b; it->have_b = 0; return 1; }
    for (;;) {
        if (!it->page_ok || it->idx >= j->page_dws) {
            if (!logj_iter_next_page(it)) return 0;
        }
        uint64_t dw = logj_rd(j, it->page, it->idx++);
        if (dw == UINT64_MAX) continue;                    /* хвіст або дірка від відмови */
        uint8_t t = LogJ_Type(dw);
        *r = (LogJRec){0};
        if ((t == LOGJ_TYPE_PAGE && logj_page_ok(dw)) || t == LOGJ_TYPE_RESUME) {
            it->base_s = (uint32_t)dw;
            it->flags  = (uint8_t)((dw >> 56) & 0xFu);
            it->cad    = (uint8_t)(dw >> 48);
            r->kind = LOGJ_REC_ANCHOR; r->type = t; r->t_s = it->base_s;
            r->time_valid = (uint8_t)(it->flags & LOGJ_FLAG_TIME_VALID);
            r->cad_min = it->cad;
            r->tag = (t == LOGJ_TYPE_PAGE) ? logj_page_seq(dw) : (uint16_t)(dw >> 32);
            return 1;
        }
        if (t == LOGJ_TYPE_DATA && it->cad) {
            uint32_t cad_s = 60u * it->cad;
            uint32_t g_a = it->base_s + (uint32_t)((dw >> 48) & LOGJ_SLOT_MAX) * cad_s;
            r->kind = LOGJ_REC_MEAS; r->t_s = g_a;
            r->time_valid = (uint8_t)(it->flags & LOGJ_FLAG_TIME_VALID);
            r->reading = (uint16_t)dw; r->temp = (int8_t)(uint8_t)(dw >> 16);
            if ((uint16_t)(dw >> 24) != LOGJ_READING_CLOSED) {
                it->b = *r;
                it->b.t_s = g_a + cad_s;
                it->b.reading = (uint16_t)(dw >> 24); it->b.temp = (int8_t)(uint8_t)(dw >> 40);
                it->have_b = 1;
            }
            return 1;
        }
        r->kind = LOGJ_REC_CORRUPT; r->raw = dw;
        return 1;
    }
}

/* ── рядок дампу (без printf: образ mini рахує байти) ─────────────── */

#define LOGJ_FORMAT_CAP 48u   /* найдовший рядок — 29 Б разом із '\n' і NUL */

static inline size_t logj_u32(char *o, uint32_t v)
{
    char tmp[10]; size_t n = 0, i = 0;
    do { tmp[n++] = (char)('0' + v % 10u); v /= 10u; } while (v);
    while (n) o[i++] = tmp[--n];
    return i;
}

/* Рядки (ASCII, закінчуються '\n'):
 *   вимір:  «<секунди>,<час виставлено 0|1>,<показ|NA>,<°C|NA>»       — напр. «1764000000,1,31207,-12.5»
 *   якір:   «#P,<seq>,<секунди>,<0|1>,<каденс хв>» · «#R,<причина>,<код скиду>,<секунди>,<0|1>,<каденс хв>»
 *   збій:   «#X,<16 hex>»
 * Повертає довжину без NUL або 0, якщо cap < LOGJ_FORMAT_CAP. */
static inline size_t LogJ_Format(char *o, size_t cap, const LogJRec *r)
{
    static const char hx[] = "0123456789abcdef";
    if (cap < LOGJ_FORMAT_CAP) return 0;
    size_t n = 0;
    if (r->kind == LOGJ_REC_MEAS) {
        n += logj_u32(o + n, r->t_s);
        o[n++] = ','; o[n++] = r->time_valid ? '1' : '0'; o[n++] = ',';
        if (r->reading == LOGJ_READING_NONE) { o[n++] = 'N'; o[n++] = 'A'; }
        else n += logj_u32(o + n, r->reading);
        o[n++] = ',';
        if (r->temp == LOGJ_TEMP_NONE) { o[n++] = 'N'; o[n++] = 'A'; }
        else {
            int32_t h = r->temp;
            if (h < 0) { o[n++] = '-'; h = -h; }
            n += logj_u32(o + n, (uint32_t)(h / 2));
            o[n++] = '.'; o[n++] = (h & 1) ? '5' : '0';
        }
    } else if (r->kind == LOGJ_REC_ANCHOR) {
        o[n++] = '#';
        if (r->type == LOGJ_TYPE_PAGE) {
            o[n++] = 'P'; o[n++] = ','; n += logj_u32(o + n, r->tag);
        } else {
            o[n++] = 'R'; o[n++] = ','; n += logj_u32(o + n, (uint32_t)(r->tag >> 8));
            o[n++] = ','; n += logj_u32(o + n, (uint32_t)(r->tag & 0xFFu));
        }
        o[n++] = ','; n += logj_u32(o + n, r->t_s);
        o[n++] = ','; o[n++] = r->time_valid ? '1' : '0';
        o[n++] = ','; n += logj_u32(o + n, r->cad_min);
    } else {
        o[n++] = '#'; o[n++] = 'X'; o[n++] = ',';
        for (int s = 60; s >= 0; s -= 4) o[n++] = hx[(r->raw >> s) & 0xFu];
    }
    o[n++] = '\n';
    o[n] = '\0';
    return n;
}

#endif /* SILKEN_LOGGER_JOURNAL_H */
