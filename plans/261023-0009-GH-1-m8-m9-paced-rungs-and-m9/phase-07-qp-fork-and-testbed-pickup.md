# P7: QP fork (D6) and the Testbed installer pickup (N7)

> **Deferred by user ruling S1 (amendment A1, 2026-10-27 23:24 KST).** Not on the M9 path of this goal; kept for a later goal, not deleted. R3′ ([phase-08b](phase-08b-r3prime-ts-xapp-harness-predictor.md)) replaces it. Do not execute any step here. The QP fork commit `381a824` (tree `aece41f6`, = the earlier `901f8c5`) stays pushed on `dev/l-release-nist180`; no `QP_URL`/`QP_SHA` in pins.conf.

**Start state:** any; host-side work may begin after P0. VM work needs the P6 UL-on dump. **Snapshot at exit:** none.

## Context (resolved read-only during warmup planning)
- **Stock QP** (`ric-app-qp@47a35ca`): `qp_config.ini` uses `cellmeas=CellReports`, `uemeas=UEReports`, `cid=nrCellIdentity`, `thptDL=pdcpBytesDl`, `thptUL=pdcpBytesUl`; `database.py:123` builds `thptparam=[UL, DL]`. QP writes predictions `astype(int)` (`prediction.py:38`) and skips the model when a column is constant (`prediction.py` ~29). QP trains once per cell at the first request and never retrains (`main.py:123-125`, `qptrain.py:136-138`). `qptrain.py:60` uses `df.iteritems()`, which pandas 2.x removed.
- **NIST's 4 QP patches** (`install_patch_files/xApps/qp/{src/qp_config.ini.patch, src/database.py.patch, insert.py.patch, setup.py.patch}`): the patched reader queries `range(start: -1600ms)` of wall time (`database.py.patch:98`); `setup.py.patch:17-18` loosens pandas to `>=1.1.3` and adds unpinned numpy.
- **kpimon's names:** measurement `cellMetrics`, untagged, cell identity in the int field `ns3.nodeId`; values are fields named after the measName.
- **The TS xApp** reads the first number of each prediction pair as DL and parses unsigned integers only (`ts_xapp.cpp:224-243, 230-235`). Stock QP sends UL first, so the fork sends **DL first**. The VAR forecast does not depend on column order.
- **Image:** base `continuumio/miniconda3:23.10.0-1`, Python 3.11 (`Dockerfile:17-18`), deps via `pip install /tmp`. No thread variables are set anywhere. Pip wheels bundle OpenBLAS (inference, verified in the image in step 6).
- **Installer** (`additional_scripts/install_xapp_qoe_predictor.sh`): clones gerrit `qp.git` into `qp` and runs `cd qp` (`:62-70`); applies the 4 patches with `git apply` under `set -e` (`:87-111`), which would abort on a fork that already carries them; seds the Dockerfile (`:113-118`) and writes the token line (`:124`) at install time. The deployed token lives in `influxdb_auth_token.json` (gitignored). The literal in `kpimon-go/control/control.go.patch:37` comes from NIST's upstream `v1.8.0` tag commit (NIST's own public placeholder, replaced at install time); it is not our deployed token.

## Requirements (contract)
In scope 5: commit 1 = NIST's 4 patches, verified as an empty tree diff; a sim-time window reader; the G1 field mapping; N2 exact pins (pandas 1.5.3, numpy 1.26.4, statsmodels 0.14.6, scikit-learn exact, base image by digest); N3 (pod restart per run, single-threaded BLAS by default, forecast hash across the 3 live runs); uppercase `cellKey`; decimal-IMSI `ue-id`; G7 (never 30002 without a valid serving pair); eNB rows excluded; values clamped to uint32; unit tests inside the image; the Testbed pickup (no `git apply`, NAME=qp, the Dockerfile and token sed kept at install time, the token never in the public fork). `QP_URL`/`QP_SHA` in pins.conf.

## Files
- QP fork `github.com/thienandangthanh/ric-app-qp`, new branch `dev/l-release-nist180` from `47a35ca`: `src/qp_config.ini`, `src/database.py`, `src/main.py`, `src/prediction.py`, `setup.py`, `Dockerfile` (`ENV OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1`; base by digest), `tests/` (pytest), a pinned `requirements.lock` (`pip freeze`).
- Testbed fork: `additional_scripts/install_xapp_qoe_predictor.sh` (clone `QP_URL` at `QP_SHA` with NAME=qp; drop the 4 `git apply` steps; keep the seds), `commit_hashes_l_release.json` (QP entry).
- Harness: `scripts/pins.conf` (`QP_URL`, `QP_SHA`), `scripts/gates/gate-qp-fork-token-check.sh`, `scripts/gates/qp-dry-run.sh`.

## Steps
1. Commit 1: apply NIST's 4 patches to `47a35ca`; verify an empty tree diff against a scratch clone of gerrit + `git apply`.
2. Commit 2: N2 pins (overriding the NIST loosening) and the base-image digest; thread variables in the Dockerfile.
3. Commit 3: G1 mapping (`cellmeas=cellMetrics`, `uemeas=UeMetrics`, `cid=ns3.nodeId`, `thptDL=DRB.PdcpSduVolumeDL`, `thptUL=DRB.PdcpSduVolumeUL`), DL-first pair order; eNB (`ns3.nodeId=1`) excluded.
4. Commit 4: sim-time window reader (the 1600 sim-ms window = 16 steps ending at the trigger's `ns3.simTimeMs`, replacing the wall-clock range).
5. Commit 5: `cellKey = %08X%02X` uppercase; decimal-IMSI `ue-id`; G7; uint32 clamp; forecast hash written to the log and a file.
6. Unit tests inside the built image against the scrubbed P6 UL-on dump: mapping, window, G7, clamp, key case, and 3 runs giving bit-identical forecasts. Record `numpy.show_config()` (BLAS library) and `pip freeze`.
7. Testbed installer pickup; pin bump.
8. Token gate on the VM: fresh anonymous clone of the QP fork; count occurrences of the deployed token (read from the VM file, never printed) in the tree and history; print the count only.
9. Offline dry run (`qp-dry-run.sh`) of the fork on the P6 UL-on dump picks R3's fixed trigger schedule (steps where the fork's prediction makes the TS xApp choose a non-serving gNB). If no feasible schedule yields a QP-driven handover: PAUSE T3.
10. Phase-exit checklist.

## Verify (comparison only)
- V1: `git diff --stat <commit1> <scratch-gerrit+apply>` prints nothing.
- V2: in-image `pytest` exits 0; the 3-run forecast SHA-256 values are equal.
- V3: `numpy.show_config()` output names the BLAS library; recorded in `implementation-notes.html`.
- V4: `gate-qp-fork-token-check.sh` prints `token occurrences: 0` and exits 0.
- V5: the installer on the VM builds and deploys QP from the fork at `QP_SHA`; the qp pod is Ready with RestartCount 0.
- V6: `qp-dry-run.sh` writes `r3-schedule.json` with ≥ 1 trigger whose expected outcome is a handover.

## Standards ledger
| Decision | Document, version, section | Zotero | Read |
|---|---|---|---|
| QP inputs = PDCP SDU volume UL/DL, kbit | 3GPP TS 28.552 V20.2.0 §5.1.2.1.1.1, §5.1.2.1.2.1; E2SM-KPM v03.00 §7.9.1 | `5SZUBP6M`, `F82PYZVK` | 2026-10-22/23 |
| Prediction pair order, key format, `ue-id` | xApp interface (TS xApp source), no 3GPP/O-RAN spec decision | — | — |

## Failure Protocol
If any Verify step does not meet its stated pass condition, STOP this phase.
Do not improvise a fix, retry blindly, or reason around the failure.
Spawn the `kongming` subagent (`model: opus`) for next-step counsel and pass:
- the phase and task id,
- what you attempted (the steps you ran),
- the exact command and its full output (scrubbed),
- the pass condition it failed to meet.
Apply kongming's guidance, then re-run the Verify step. If it fails again, or the guidance would change the locked outcome, print `PAUSE T6 evidence=<path> journal=<path>` and call no further tool.
If `kongming` cannot be spawned, STOP and print the same PAUSE line with the failure evidence. Never continue by self-reasoning. kongming's counsel is never user approval.
Any sign of the deployed token in a committed file or public tree: PAUSE T7 immediately.

## Phase exit
Run the plan's phase-exit checklist, then spawn kongming (`model: opus`) for a go/no-go on P8.

## Risk and rollback
Risk: pandas 1.5.3 has no wheel for the base image's Python (then pin the base image's Python, not pandas; T3 if impossible). Rollback: revert the Testbed installer commit; QP stays undeployed.

## Review amendments (binding; they override any conflicting text above)
Source: `plans/reports/kongming-261023-0020-GH-1-m8-m9-plan-collect-only-review.md`, classified in `plans/reports/review-261023-0009-GH-1-m8-m9-contract-preserving-review-and-preflight-matrix.md`.
- **K7 (G1, complete).**
  - Mapping: `ue → ns3.imsi`, `servcell → ns3.l3.servCellId`, `nbcells → ^ns3\.l3\.nbr[0-9]+\.cellId$`.
  - Typed (int) Flux filters, never a string compare; eNB UE rows (`ns3.nodeId = 1`) excluded.
  - Emit the serving cell first (the TS xApp treats the first cell as serving, `ts_xapp.cpp:225-228`), and DL first in each pair.
  - Unit tests cover each item, plus a decimal-IMSI `ue-id` (kongming-1739 §5.4).
  - Confirm kpimon's UE field names on the P6 dump; a mismatch is fixed in the fork mapping (not in kpimon).
- **K6.** The fork selects UE rows by `(ns3.nodeId ≠ 1, ns3.imsi, ns3.seq = T)`, never by `_time` or `limit=1`.
- **K17.** The unit tests assert that a model file is created for each R3 cell.
- **K27.** The Testbed pickup always removes `qp` and clones `QP_SHA` afresh; V5 also checks that `git -C qp rev-parse HEAD` equals `QP_SHA`.
- **K12.** Undeploy the stub QP before any QP deploy; V5 adds an rtmgr dump with exactly one receiver for 30000.
- **K24.** The token gate is named `scripts/gates/gate-q7-qp-token-check.sh`.
- **K18 (step 9).** The dry run uses the P6 null-control R3-config UL-on dump, plus a scripted offline replay of the TS xApp's decision. The schedule is committed at `scripts/gates/r3-schedule.json`.
- **K21.** Host-side P7 work starts only in segment 2.
