# Stop A: user rulings on the segment-1 milestone

Date: 2026-10-24 02:04 KST. Source: the user's message "accept the suggestions from plans/reports/milestone-261023-1810-GH-1-m8-m9-segment-1-stop-a.md", given when the M8–M9 goal was re-issued for segment 2. Every item below takes the milestone's recommended default.

| # | Item | Ruling |
|---|---|---|
| 1 | T8 reading of the P0 refused probe (01:38 KST, 2026-10-23) | Not T8: it was not a scripted command. From now on any permission refusal counts as T8. |
| 2 | K5 shown by integration cases (S1 fb1, R1 (b)), not by an ns-3 unit test | Accepted. |
| 3 | "late" also covers a control that misses its barrier mid-run (K9 in R0, S1 `midlate`) | Yes. |
| 4 | RAN function 3 is not announced in E2 Setup; the agents accept RC controls anyway (E2AP v03.00 §8.2.4.3) | Listed as **recorded deviation P8** (named "deviation P8" wherever it could be confused with phase P8). Recorded, not fixed, like P1–P7. |
| 5 | kpimon and hw-go pods are recreated each run | The deployment stays; only the pod is recreated. This reads "hw-go (stays deployed)" literally and keeps RestartCount = 0 meaningful. |
| 6 | rtmgr restart in the per-run reset, and the T5 reading (rtmgr never reconnects to a replaced xApp pod) | Accepted. Both rtmgr's and e2term's views of the −1 route owner are recorded; owner identity is not a pass condition. |
| 7 | ns-3 trace text files gitignored, with sha256 manifests | Accepted. |
| 8 | Fault run (ii) through the eNB agent; nodes 2 and 3 answer `late` (read from the code, never run); the two P2-deferred fork items dropped | Accepted. The departure fix may optionally be bundled into P6's fork change; it is not required. |
| 9 | C9 file naming: `EnbHandover*` read by the checker, `UeHandover*` named in the contract | Accepted. |
| — | Influx dump of R1 live1 committed against `evidence/.gitignore` | Default: gitignore `influx-*.csv` and keep a sha256 manifest in git. |

kongming's Stop A review (`plans/reports/kongming-261023-1815-GH-1-stop-a-segment-1-review-and-p5-go-no-go.md`) gave P5 a GO conditional on ruling 6, which is now accepted.
