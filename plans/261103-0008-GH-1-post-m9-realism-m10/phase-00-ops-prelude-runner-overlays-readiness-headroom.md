# P00 (MA): ops prelude: runner finish, overlay orphans, receiver readiness, headroom, FU4 note

**Start state:** VM as left after M9 (post-M9 overlay will leak at the next revert). **Snapshot at exit:** none.

## Context
These are the M9 follow-ups FU1–FU5 (`plans/reports/handoff-261029-0540-GH-1-m8-m9-done.md:19-23`). They harden the harness that every later phase and the M10 run use. Nothing here touches the wire or ns-3, so checkpoint 1 is unaffected.

## Requirements (contract)
- **AC1 (FU1):** `finish()` stops the VM gate units without the `kill -0` guard [V `scripts/run-to-m9.sh:122`]; the TERM message [V `:131`] is corrected; a runner self-test case covers "step pid already exited, gate unit still running → unit stopped".
- **AC2 (FU2):** after the M0 probe (branch create/delete) [V `scripts/gates/gate-m0-host.sh:46-52`] and a revert to `fresh-install`, an orphan check lists zero untracked overlays in the image directory. It runs in dev and after the end run (P13).
- **AC3 (FU3):** no check passes on `rtmgr_push_acked` [V `scripts/gates/rc-lib.sh:111`] alone; readiness needs receiver-side evidence like `rt_reader_ok` [V `scripts/gates/bringup.sh:227`]; a fixture with an "OK" push log and a stuck reader fails.
- **AC4 (FU5):** a script computes h = the largest host-free drop over any 370 s window across every M9 attempt's `free-series.tsv` (and, in P11, every dev rehearsal of the new steps). h = 12, trip = 37 (R11). If the worst burst > 12 GiB: stop for a user ruling (PAUSE T3), never raise h silently.
- **AC5 (FU4):** a findings note on the stuck RMR route readers (hypotheses, reproduction attempts); the F″ remedy is unchanged.

## Files
- Modify: `scripts/run-to-m9.sh` (finish(): call `vm_stop_gates` whenever a step ran, independent of `kill -0`; trap text), `scripts/vm/m9-runner-selftest.sh` (new case), `scripts/gates/rc-lib.sh` (`rc_rmr_ready_after_rtmgr` gains receiver evidence; `rtmgr_push_acked` becomes supporting only), `scripts/gates/bringup.sh` (generalize `rt_reader_ok` to an xApp RMR receiver: rc in `ricxapp`, port per its route-table socket [I, measured in dev]).
- Callers of the changed readiness (enumerated): `scripts/gates/gate-i2-ts-xapp-install.sh:69`, `scripts/gates/ts-rung-lib.sh:58` (via `rc_rmr_ready_after_rtmgr`, `rc-lib.sh:123`).
- Create: `scripts/vm/vm-orphan-overlays.sh` (read-only: image-dir files vs every snapshot's and the domain's backing chain; prints untracked files, exit 1 if any), `scripts/disk-burst-h.py` (worst Δfree over 370 s windows; input any number of `free-series.tsv`; output JSON `{worstGiB, file, window}`), fixtures under `scripts/gates/fixtures/` for AC3 (push log "OK" + reader sample with rx_queue > 0).
- Modify (FU2 fix itself): `scripts/gates/gate-m0-host.sh` probe path or `scripts/vm/vm-snapshot.sh` so the probe no longer untracks the active overlay [I: root cause per handoff FU2; the exact fix is chosen in dev from the disk-chain evidence the gate already writes, `gate-m0-host.sh:50`].
- Create (Markdown): `plans/reports/findings-<date>-GH-1-fu4-stuck-rmr-route-readers.md` (AC5).

## Steps
1. FU1: edit `finish()`; add the self-test case; run `scripts/vm/m9-runner-selftest.sh` (host only).
2. FU3: write the fixture; extend readiness; prove the fixture fails the new predicate and a healthy sample passes. Record each predicate change in `check-diff-ledger.md` (AC18 ordinary rows).
3. FU5: `scripts/disk-burst-h.py plans/261023-0009-GH-1-m8-m9-paced-rungs-and-m9/evidence/m9/*/free-series.tsv`; record the worst burst. Expect ≤ 12 (kongming computed 8, 9, 11, 12); > 12 → PAUSE T3.
4. FU2: reproduce the leak on the VM (M0 probe then revert), fix, re-run M0 probe + revert, then `vm-orphan-overlays.sh` → zero. Any leaked file found before the fix is handled only under the 2026-10-28 ruling (checks 1–5, logged).
5. FU4: collect the M9 evidence (`rt-readers-*.txt`, `refresh-ric-*`), one reproduction attempt (cold boot, observe readers), and write the note.
6. Phase exit.

## Validation
- `bash scripts/vm/m9-runner-selftest.sh` exits 0 including the new case (the unit is stopped while `kill -0` would have returned false).
- `bash scripts/vm/vm-orphan-overlays.sh` after M0 probe + revert prints nothing, exit 0 (evidence `evidence/fu2/<ts>/`).
- The AC3 fixture: new readiness predicate exits non-zero; the healthy fixture exits 0.
- `python3 scripts/disk-burst-h.py …` output archived; `worstGiB ≤ 12`.
- `bash scripts/gates/lint.sh` clean.

## Standards ledger (stub)
| Decision | Document, section | Zotero | Read |
|---|---|---|---|
| None: harness and ops only. No O-RAN/3GPP clause applies. | — | — | — |

## Risks
- The FU2 fix touches snapshot handling (High impact, Medium likelihood). Mitigation: protected snapshots are checked before and after; dev-only first; T1 on any doubt.
- The xApp-side reader check may have no stable socket signature for rc (Medium/Medium). Mitigation: measure in dev; if none exists, use a receiver-side RMR round trip (rc's route-dependent reply) as evidence, recorded in the ledger.

## Rollback
Revert the harness commits; the M9 runner at `39b3ba2` stays reproducible from git.
