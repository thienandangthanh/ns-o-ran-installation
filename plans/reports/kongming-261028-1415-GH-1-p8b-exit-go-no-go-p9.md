# kongming 2026-10-28 14:15 KST: P8′ exit, go/no-go on P9

Advisory (Opus 5.5, xhigh); never user approval. Recorded by the controller from the agent's report.

## Verdict
GO for P9. P8′ meets V1–V9a and the locked R3′ signals; nothing is T3/T6. As planned, P9 would fail M9 at i2 (warm-only timeouts).

## Q1 findings
- V1–V7 met on host evidence `evidence/r3p/20261028T044557Z`: predictor-records byte-equal live1–3; Influx = IPC 100 seqs/node; N6, c8 null 0 handover rows, observation change, `servingAfterH1` green; restarts 0; W 1.0 s; substitution3Applied true.
- Determinism across gate invocations: host digest of C1 live1 = VM digest (`1ad68acb…`); single `043444Z` live1 = C1 live1 (ledger, ipc, traces, extra, predictor records).
- K14: `git diff d2e1ab4..HEAD -- scripts/gates tools scripts/probes scripts/pins.conf` empty at the time; forks unchanged since 47aee0b.
- Errata: C1 had 167 checks (168th PASS line = verdict line); V8's `snapshots.txt` predates `r3p-green` (record a post-create list); kongming-1230 §130 was wrong: in M9 i2 creates type 20008 and r2/r3p find it.

## Q2 disk
- 42 G M0–M7 host-free drop is the right term; add 1 GiB for m0/m0-host (first sample after m0).
- R section 12 GiB is an estimate ±3, not an upper bound (cold rc/rc-decode build sat under f7 → r0-green; ~5 GB of extra dev runs under r0-green → r2-green).
- Units: GiB as `df -BG`; drop the "2 dev" guess; measure X at Stop B after the last P9 VM run.
- Stop B: P10 starts only when `df -BG /home` ≥ T = (25 + h) + 43 + 12 = 84 GiB; user frees 84 − X. h by `m9-budget.py` (A1 method) = 4; sensitivity h = 8 → T = 88 (optional margin).

## Q3
Run `gate-r3p-ts-predictor.sh --mode c1 --reference plans/…/reference/r3p` at the frozen SHA F after the freeze, before Stop B: only live test of the `--reference` path, r3p's type-create path (`a1PolicyTypeCreated` true), equality across a boot, the exact P10 SHA. No snapshot op; ~1–1.5 GiB; ~35 min; red = PAUSE T6. Pre-register purpose and pass condition; it never replaces the reference.

## Q4 traps
- `reference-compare.py compare` fails on any unlisted file in REFDIR: make into an empty dir; provenance outside.
- Names must match the gate (`predictor-records`, `schedule`, `scenario`, recorded `xapp-image-ids.json`).
- Use live1; record live1 = live2 = live3 = single live1.
- Do not edit `rung-config.json` in P9 (K14 input).
- Keep the gitignored raw C1 traces and Influx CSV until M9 is green.
- Deleting `r0-green`/`r2-green` (non-leaf) frees almost nothing.
- Host scripts run from the worktree while the VM clones `--harness-sha`: P10 must pass exactly F.

## Must-do before Stop B
1. Cold-path timeouts for i0/i2 (inner caps: `rc_install` `nist_run 3600`, `rmr_peer_build` `timeout 1200`); fold cold durations into the wall.
2. `substitution3Applied` on r0/r1 verdicts (false).
3. K14 proof at the freeze.
4. Make the reference; controls (live1–3 and single live1 true, rng2 false, `sha256sum -c` ok); commit, push.
5. Stop B number T = 84 GiB with h basis and optional +4.
6. Record F in the resume card and `m9-budget.md`.

## Should-do
1. Rehearsal C1 `--reference` at F. 2. r0/r1 single at F. 3. Runner refuses a worktree differing from `--harness-sha`. 4. Watchdog free-space series. 5. Substitution-4 validator fixtures (A1 V4). 6. K8: `deployed-image-ids.json` and `agent-image.env` in `recorded/`. 7. tshark 4.4.19 (trixie) recorded, re-checked before P10. 8. Codex inventory: M9-critical files first; code-reviewer fallback for uncovered items. 9. Stale parent gitlinks: update at the freeze or disclose in F10. 10. `--no-snapshots` as an optional user lever (~4 GiB, inferred).

## Unresolved (Stop B)
Optional +4 GiB margin; `--no-snapshots`; the earlier interpretations list (F09 reading, persistence anti-load-balancing, seq erratum, W via R2 block, two-stage dry run, evidence-commit slips, route-owner variance).
