#ifndef DID_DERIVE_H
#define DID_DERIVE_H

#include <stdint.h>

// = =========================================================================
// 🌳 Did_Derive — детерміноване ім'я дерева з кремнієвого паспорта
// = =========================================================================
//
// [FW.54 Вісь 2] DID = f(96-біт UID), без random. Ім'я дерева тепер
// відтворюване з самого кристала: повний розряд EDLC (зимовий голод HW.14)
// більше не сиротить identity/гаманець, а фабрика (SEC.3) деривує той самий
// DID з UID по SWD ще ДО прошивки — однопрохідний провіженінг, K_seed
// запікається одразу. DR7 звільнено: зберігати нічого, recompute на boot.
//
// Мікс — murmur3-фінalizer ланцюгом по трьох словах UID: повний avalanche
// (один біт UID перемішує весь DID), чиста цілочисельна арифметика,
// біт-у-біт відтворювана хостом (SilkenNet::DidDerivation — Ruby-дзеркало;
// golden-вектори заморожені обабіч: test_soldier_logic.c (golden g1-g4) ↔
// spec/services/silken_net/did_derivation_spec.rb).
//
// DID == 0 зарезервовано ефіром під Королеву-Сентінель (03_02 §7) — нуль
// детерміновано відображається у "SNET"-константу. Колізії 32-біт ловить
// фабрика DB-unique-перевіркою до поля (birthday-математика однакова з
// старою random-схемою, але детермінізм робить її видимою заздалегідь).
//
// Канон: 03_01 §2 (DR-map, DR7) + §2.3.2 Вісь 2. Трекер: 00_07 FW.54.

#define DID_DERIVE_SEED 0x534E4554u /* "SNET" */

// murmur3 fmix32: лавина у 32 бітах.
static inline uint32_t Did_Mix32(uint32_t h)
{
    h ^= h >> 16;
    h *= 0x85EBCA6Bu;
    h ^= h >> 13;
    h *= 0xC2B2AE35u;
    h ^= h >> 16;
    return h;
}

// 96-біт UID (три слова з 0x1FFF7590) → 32-біт DID. Ніколи не повертає 0.
static inline uint32_t Did_Derive_From_Uid(uint32_t w0, uint32_t w1, uint32_t w2)
{
    uint32_t h = DID_DERIVE_SEED;
    h = Did_Mix32(h ^ w0);
    h = Did_Mix32(h ^ w1);
    h = Did_Mix32(h ^ w2);
    return (h != 0u) ? h : DID_DERIVE_SEED;
}

#endif // DID_DERIVE_H
