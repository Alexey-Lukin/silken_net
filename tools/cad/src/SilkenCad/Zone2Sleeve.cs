// SPDX-License-Identifier: AGPL-3.0-or-later
using PicoGK;
using Leap71.ShapeKernel;

namespace SilkenCad;

// Zone 2 PEEK thermal-break sleeve (Деталь 2, 01_01 §1 + §4) — серединна деталь анкера: проста
// порожниста PEEK-труба, що розриває тепловий потік між зануреним анодом (Zone 1) і капсульним
// катодом (Zone 3). Press-fit на вал Ø11 з одного кінця, приймає shank фланця з іншого; стінка
// 2 мм (CTE Lamé, §4.2) → OD Ø15 = жива рана у дереві (CODIT <25). Найпростіший генератор родини:
// труба = BasePipe (готовий hollow-tube примітив, той самий, що Zone1Anode.Envelope) → один
// voxConstruct, gotcha #9 не загрожує (це не SDF narrow-band). Барбів / DIN-471-канавок / hex тут
// немає — гладкий PEEK (барби Ti вдавлюються при 150 °C, канавки на Ti-кінцях; див. Zone2SleeveCem).
internal static class Zone2Sleeve
{
    // OD-радіус = bore/2 + стінка (Ø15 при frozen Ø11 + 2·2 мм) = радіус рани у дереві.
    public static float OuterR(Zone2SleeveCem cem) => (cem.BoreDiameterMm / 2f) + cem.WallThicknessMm;

    public static Voxels Build(Zone2SleeveCem cem)
        => new BasePipe(new LocalFrame(), cem.LengthMm, cem.BoreDiameterMm / 2f, OuterR(cem)).voxConstruct();
}
