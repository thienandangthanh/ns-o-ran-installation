# M9 disk projection, P8′ exit (2026-10-28 14:09 KST)

Formula (P0 K2, A1 floor): projection = host free now − expected further dev growth − M9 need − (25 + h) GB. Overlays already on disk are inside "host free now". P10 reverts to `fresh-install`; libvirt keeps every existing overlay, so the M9 overlay grows on top of today's usage.

## Image chain (measured, `chain-sizes.txt`, allocated bytes)

| File | Holds | GB |
|---|---|---|
| `ubuntu24.04` | base (`fresh-install` backing) | 3.5 |
| `ubuntu24.1792618143` | fresh-install → f7-rerun-green (M0–M7) | 39.7 |
| `ubuntu24.1792653312` | f7-rerun-green → r0-green (s0, s1, q8, r0 dev, ns-3 rebuilds) | 14.2 |
| `ubuntu24.04-r0-green.qcow2` | r0-green → r2-green (i0, r1, i2 ×9, r2 ×4, QP/stub images) | 9.6 |
| `ubuntu24.04-r2-green.qcow2` | r2-green → now (15 gate runs: r0 ×4, r1 ×2, r2 ×3, r3p ×6) | 8.3 |

Measured per-gate-run growth after the installs: 8.3 GB / 15 runs ≈ 0.55 GB.

## Projection

| Term | GB | Basis |
|---|---|---|
| Host `/home` free now | 61 | measured, `df.txt` |
| Expected further dev growth (P9 insurance r0/r1 singles; reference made host-side) | 2 | 0.55 GB per run, rounded up |
| M9 need: M0–M7 | 42 | measured host-free drop 78 → 36 G in `p8-attempt2-run-to-m7.log` (≥ the 39.7 GB overlay) |
| M9 need: i0 r0 r1 i2 r2 r3p | 12 | the r0-green → r2-green overlay 9.6 GB (installs plus 6 runs, an upper bound for i0 + i2) plus 4 gate runs × 0.55 GB, rounded up |
| Floor 25 + h | 29 | h = 4 GB from the draft `m9-budget.py` run (fastest measured growth × stop path); finalized in P9 |
| **Projection** | **61 − 2 − 54 − 29 = −24** | negative |

Status: negative. Not a pause (P0 K2, user ruling 2026-10-23 01:30 KST): the user frees the measured shortfall, about 24 GB, at Stop B. Creating `r3p-green` adds no data (a new empty overlay); its `--need-gb 2` covers the P9 growth above the script's 20 GB refusal floor.
