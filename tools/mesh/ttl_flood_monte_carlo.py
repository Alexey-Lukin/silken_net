#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""
ARCH.74 — Monte Carlo TTL-flood: P_delivery(q, TTL) для майбутнього mesh-relay (post-TRL 6).

🔴 **Чесний framing (несучий, не оздоба):** це НЕ виправдання поточних wire-констант
`PANIC_TTL=5`/`DEFAULT_TTL=3` у `firmware/soldier/main.c` — вони живуть у STAR-топології
(CCM-ера, `03_01 §1.9.1`: Сценарій Б mesh-relay гейтований `#if !FW2_CCM_ENABLED`, тож на
живому wire TTL-байт по суті не маршрутизує). Ця робота — **ARCH.43-readiness**: math-фундамент
для mesh, який повертається лише з wire-rev3-класом (post-TRL 6). Percolation-ТЕОРІЯ (q_c/Markov)
лишається Open Research (`06_08`) — тут лише Monte Carlo, не аналітична теорія.

**Модель:**
- Топологія: RGG (random geometric graph, disk-модель радіо-звʼязку) + ER (Erdős–Rényi, той самий
  середній degree) — пара, бо ER ізолює ефект raw-звʼязності від просторової локальності: якщо
  TTL-поріг тримається на ОБОХ, він не є артефактом RGG-геометрії.
- N_TOTAL = 100: 1 Королева (фіксована в центрі кластера, always-on — `03_01 §1.9`
  «Королева… ніколи не спить», тож у пул відмов НЕ входить) + 99 Солдатів (uniform-random
  у AREA_SIDE_M²).
- COMM_RADIUS_M = 150 м — нижня межа радіо-радіуса з `03_01 §1.9` («Будь-який Солдат у радіусі
  150–200 м») та `§1.9.1` («≤3 хопи ≈ 450–600 м ефективного радіусу» ⇒ per-hop ≈150–200 м).
- q ∈ {0.20, 0.25, 0.30} — частка ОДНОЧАСНИХ відмов Солдатів (specified in ARCH.74). Фізичний
  референс тієї самої осі — HW.44 (зимовий boot↔brownout цикл на низькому EBFC-харвесті): відмова
  тут МОДЕЛЬ вузла, що замовк (не EBFC-достатньо, не «циклить» POR), не тип відмови.
- TTL ∈ 1..7, ціль P_delivery ≥ 0.99.
- 10⁴ реалізацій НА ТОПОЛОГІЮ: кожна реалізація = один випадковий граф (позиції + edges) + для
  КОЖНОГО q незалежний випадковий набір відмов на ТОМУ Ж графі (common random numbers — парне
  порівняння q при фіксованій геометрії) + одна BFS від Королеви → відстані до ВСІХ виживших вузлів
  одразу → для кожного TTL: частка виживших Солдатів у межах TTL хопів. Це саме той сенс «10⁴
  реалізацій», у якому специфікація ARCH.74 його вжила — не 10⁴ на кожну (q,TTL)-пару окремо.

**Ідеалізації, названі вголос (платформа ≠ ідеал специфікації, CLAUDE.md §4):**
- Disk-модель радіозвʼязку (edge ⟺ dist ≤ COMM_RADIUS_M) — ІЗОТРОПНА, без крон-затінення,
  рельєфу, багатопроменевості. Реальний ліс дає нерівномірний, вужчий і асиметричний radio-graph.
  Результати тут — **оптимістична верхня межа**, не польова валідація (та сама вісь, що
  «in-silico ≠ TRL 4», застосована до симуляції мешу).
- Позиції Солдатів рандомізуються НАНОВО щореалізацію (ансамбль «типових» розкладок кластера,
  не одне зафіксоване польове дерево) — це навмисний вибір для ДИЗАЙН-стадії питання (немає ще
  жодного реального кластера, `00_01 §4`: System TRL=3, нуль вузлів у лісі), а не приховане
  припущення про мобільність дерев.
- Відмова вузла = вузол ПОВНІСТЮ вилучено з графа (не ретранслює, не породжує) — модель
  «мовчазного» Солдата (EBFC-underpower / brownout-цикл), не часткової деградації радіо.
"""
from __future__ import annotations

import json
import time
from pathlib import Path

import networkx as nx
import numpy as np

REPO_ROOT = Path(__file__).resolve().parents[2]
OUT_DIR = Path(__file__).resolve().parent / "cache"
OUT_DIR.mkdir(parents=True, exist_ok=True)

# ── Model parameters (canon-cited above) ──
N_SOLDIERS = 99
N_TOTAL = N_SOLDIERS + 1          # + Королева
QUEEN_ID = 0
AREA_SIDE_M = 1000.0              # 1 km² кластер (масштаб-порядок з 00_01 §4 Phase 2: "тисячі дерев" / "10+ кластерів")
COMM_RADIUS_M = 150.0             # per-hop LoRa-радіус — нижня межа з 03_01 §1.9/§1.9.1
Q_VALUES = (0.20, 0.25, 0.30)     # ARCH.74: одночасні відмови Солдатів
TTL_VALUES = tuple(range(1, 8))   # ARCH.74: TTL 1..7
N_REALIZATIONS = 10_000           # ARCH.74: 10⁴ реалізацій
P_DELIVERY_TARGET = 0.99          # ARCH.74: ціль
SEED = 20260909                   # reproducible (дата виконання)

AVG_DEGREE_RGG = N_TOTAL * np.pi * COMM_RADIUS_M**2 / AREA_SIDE_M**2  # disk-continuum estimate
ER_EDGE_PROB = AVG_DEGREE_RGG / (N_TOTAL - 1)                          # matched avg degree


def banner(msg: str) -> None:
    print(f"\n[{time.strftime('%H:%M:%S')}] {msg}", flush=True)


def rgg_realization(rng: np.random.Generator) -> tuple[nx.Graph, int]:
    """Один RGG-розклад: Королева фіксована в центрі, 99 Солдатів — uniform random."""
    pos = {QUEEN_ID: (AREA_SIDE_M / 2, AREA_SIDE_M / 2)}
    for i in range(1, N_TOTAL):
        pos[i] = (rng.uniform(0, AREA_SIDE_M), rng.uniform(0, AREA_SIDE_M))
    g = nx.random_geometric_graph(N_TOTAL, COMM_RADIUS_M, pos=pos)
    return g, QUEEN_ID


def er_realization(rng: np.random.Generator) -> tuple[nx.Graph, int]:
    """Null-model: той самий N і середній degree, БЕЗ просторової локальності."""
    g = nx.gnp_random_graph(N_TOTAL, ER_EDGE_PROB, seed=int(rng.integers(0, 2**31 - 1)))
    return g, QUEEN_ID


def simulate(topology: str, rng: np.random.Generator) -> dict[tuple[float, int], np.ndarray]:
    """N_REALIZATIONS реалізацій; на кожній — 3 незалежні q-відмови (common random numbers на
    графі), одна BFS на відмову → per-TTL частка виживших Солдатів у межах TTL хопів."""
    gen = rgg_realization if topology == "rgg" else er_realization
    per_q_ttl: dict[tuple[float, int], list[float]] = {(q, ttl): [] for q in Q_VALUES for ttl in TTL_VALUES}

    for _ in range(N_REALIZATIONS):
        g, queen = gen(rng)
        soldier_pool = [n for n in g.nodes if n != queen]

        for q in Q_VALUES:
            n_fail = round(q * len(soldier_pool))
            failed = set(rng.choice(soldier_pool, size=n_fail, replace=False)) if n_fail else set()
            survivors = g.copy()
            survivors.remove_nodes_from(failed)

            n_surv_soldiers = survivors.number_of_nodes() - 1  # мінус Королева
            dist = nx.single_source_shortest_path_length(survivors, queen) if n_surv_soldiers > 0 else {}

            for ttl in TTL_VALUES:
                if n_surv_soldiers <= 0:
                    per_q_ttl[(q, ttl)].append(0.0)
                    continue
                reached = sum(1 for n, d in dist.items() if n != queen and d <= ttl)
                per_q_ttl[(q, ttl)].append(reached / n_surv_soldiers)

    return {k: np.array(v) for k, v in per_q_ttl.items()}


def summarize(results: dict[tuple[float, int], np.ndarray]) -> dict:
    out = {}
    for (q, ttl), arr in results.items():
        out[f"q={q}_ttl={ttl}"] = {
            "q": q, "ttl": ttl,
            "mean": round(float(arr.mean()), 5),
            "ci90_lo": round(float(np.percentile(arr, 5)), 5),
            "ci90_hi": round(float(np.percentile(arr, 95)), 5),
        }
    return out


def threshold_table(results: dict[tuple[float, int], np.ndarray]) -> dict[float, int | None]:
    """Найменший TTL, де mean P_delivery ≥ P_DELIVERY_TARGET, для кожного q. None = не досягнуто в 1..7."""
    thresholds: dict[float, int | None] = {}
    for q in Q_VALUES:
        thresholds[q] = None
        for ttl in TTL_VALUES:
            if results[(q, ttl)].mean() >= P_DELIVERY_TARGET:
                thresholds[q] = ttl
                break
    return thresholds


def print_table(topology_label: str, results: dict[tuple[float, int], np.ndarray]) -> None:
    banner(f"{topology_label} — P_delivery(q, TTL), mean [90% CI]")
    header = "  TTL | " + " | ".join(f"q={q:.2f}" for q in Q_VALUES)
    print(header)
    print("  " + "-" * (len(header) - 2))
    for ttl in TTL_VALUES:
        row = f"  {ttl:>3d} | "
        cells = []
        for q in Q_VALUES:
            arr = results[(q, ttl)]
            cells.append(f"{arr.mean():.3f} [{np.percentile(arr, 5):.3f},{np.percentile(arr, 95):.3f}]")
        print(row + " | ".join(cells))


def main() -> int:
    banner(f"ARCH.74 — Monte Carlo TTL-flood (N={N_TOTAL}, area={AREA_SIDE_M:.0f}m², "
           f"r={COMM_RADIUS_M:.0f}m, avg_degree≈{AVG_DEGREE_RGG:.2f}, realizations={N_REALIZATIONS})")
    print(f"  ER matched edge-prob p={ER_EDGE_PROB:.4f} (same avg degree as RGG, no spatial locality)")

    rng_rgg = np.random.default_rng(SEED)
    rng_er = np.random.default_rng(SEED + 1)

    banner("Running RGG campaign…")
    rgg_results = simulate("rgg", rng_rgg)
    banner("Running ER campaign…")
    er_results = simulate("er", rng_er)

    print_table("RGG (spatial, disk-model radio)", rgg_results)
    print_table("ER (null model, same avg degree)", er_results)

    rgg_thresh = threshold_table(rgg_results)
    er_thresh = threshold_table(er_results)

    banner(f"TTL-поріг для P_delivery ≥ {P_DELIVERY_TARGET:.2f} (None = не досягнуто в межах TTL≤7)")
    for q in Q_VALUES:
        print(f"  q={q:.2f}   RGG: TTL={rgg_thresh[q]}   ER: TTL={er_thresh[q]}")

    banner("Verdict")
    print("  🔴 ЦЕ НЕ виправдання живих wire-констант PANIC_TTL=5/DEFAULT_TTL=3 — той шлях зараз")
    print("  star-only (CCM-ера, 03_01 §1.9.1). Ці числа — ARCH.43-readiness math-фундамент для")
    print("  mesh, який повертається post-TRL 6 разом із wire-rev3.")
    both_reach_7 = all(rgg_thresh[q] is not None and er_thresh[q] is not None for q in Q_VALUES)
    if both_reach_7:
        worst_ttl = max(max(rgg_thresh[q], er_thresh[q]) for q in Q_VALUES)
        print(f"  На ОБОХ топологіях (RGG і ER) TTL≥{worst_ttl} досягає P_delivery≥{P_DELIVERY_TARGET:.2f}")
        print(f"  для всього діапазону q∈{Q_VALUES} — поріг НЕ артефакт геометрії.")
    else:
        print("  ⚠️ Принаймні одна (q, топологія) пара НЕ досягає цілі в межах TTL≤7 — чесний")
        print("  негативний результат: одноодержувацький (single-sink) mesh на цій щільності/радіусі")
        print("  структурно не тягне 99%-доставку при заданих відмовах без ретрансляції через кількох Queen")
        print("  (fractal L2 / ARCH.10 Q2Q, 00_07) або без ширшого радіуса/щільнішої сітки.")

    out = {
        "params": {
            "n_total": N_TOTAL, "n_soldiers": N_SOLDIERS, "area_side_m": AREA_SIDE_M,
            "comm_radius_m": COMM_RADIUS_M, "avg_degree_rgg": round(float(AVG_DEGREE_RGG), 3),
            "er_edge_prob": round(float(ER_EDGE_PROB), 5), "q_values": list(Q_VALUES),
            "ttl_values": list(TTL_VALUES), "n_realizations": N_REALIZATIONS,
            "p_delivery_target": P_DELIVERY_TARGET, "seed": SEED,
        },
        "framing": ("NOT a justification of live PANIC_TTL=5/DEFAULT_TTL=3 (star-only under CCM, "
                    "03_01 §1.9.1) — ARCH.43-readiness math for a future mesh (post-TRL 6, wire-rev3)."),
        "rgg": summarize(rgg_results),
        "er": summarize(er_results),
        "ttl_threshold_p99": {"rgg": {str(q): rgg_thresh[q] for q in Q_VALUES},
                               "er": {str(q): er_thresh[q] for q in Q_VALUES}},
    }
    json_path = OUT_DIR / "ttl_flood_monte_carlo.json"
    json_path.write_text(json.dumps(out, indent=2))
    banner(f"✅ Saved {json_path.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
