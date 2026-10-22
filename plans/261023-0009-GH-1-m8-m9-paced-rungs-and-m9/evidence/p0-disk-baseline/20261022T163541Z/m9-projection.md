# M9 disk projection, P0 baseline (2026-10-23 01:35 KST)

Formula (review K2): projection = host free now − expected further dev growth − M9 need − 20 GB floor. Overlays already on disk are inside "host free now".

| Term | GB | Basis |
|---|---|---|
| Host `/home` free now | 76 | measured, `df.txt` |
| Image chain on disk | 3.3 base + 37.0 (f7 merged overlay `ubuntu24.1792618143`) + 1.1 (active overlay) | measured, `du`, `chain-sizes.txt` |
| Expected further dev growth P1–P8 (active overlay: ns-3 rebuilds, rc/TS xApp/QP images, per-run VM evidence; plus `r0-green`, `r2-green`, `r3-green` freezing rewritten blocks) | ≈ 20 | inferred; refined at every phase exit from measured overlay sizes |
| M9 need: M0–M7 (measured 39.7 GB merged overlay) + R-rung installs and evidence (≈ 8) | ≈ 48 | 39.7 measured (kongming-2105 §5); +8 inferred |
| Floor | 20 | contract |
| **Projection** | **76 − 20 − 48 − 20 = −12** | negative |

Status: negative projection. Reported, not paused (user, 01:30 KST): it is raised at Stop A and the user frees the measured shortfall at Stop B. T2 fires only when actual free space would cross 20 GB plus the next growth.
