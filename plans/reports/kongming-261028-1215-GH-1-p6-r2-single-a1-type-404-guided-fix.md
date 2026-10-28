# Kongming counsel: the P6 V4 r2 single was red because policy type 20008 returned 404 after the a1mediator restart (guided fix)

- **Date:** 2026-10-28, about 12:15 KST.
- **Model:** Opus 5.5, as the caller asked.
- **Scope:** advisory only. This counsel does not count as user approval.
- **Inputs:**
  - `evidence/r2/20261027T041111Z`, plus every i2 and r2 evidence directory from 2026-10-23 to 2026-10-27;
  - `scripts/gates/ts-lib.sh`, `gate-r2-ts-stub-qp.sh`, `gate-i2-ts-xapp-install.sh` and `run-to-m9.sh`;
  - the vm-exec and scrub scripts;
  - the plan's invariants and T3/T6, phase-06 Amendment A1 (V4) and decisions-261027-2155 (rulings 3 and 6).

## TL;DR
**GO on the fix, with one change to where the ensure goes.**

1. Ensure the type once, at gate level, before the pre reset: move the existing `check r2_a1_policy_type_20008_present ts_policy_type_ensure` from `gate-r2-ts-stub-qp.sh:114` to just above `:107`. This is the order i2 already uses (`gate-i2:46` before `:64`).
2. Make `a1mediator_restart` assert, before it deletes the pod, that the type answers HTTP 200. The survival claim then becomes "200 before and 200 after".

Your variant (an ensure inside `ts_stub_pods_reset`) also fixes the defect. It is second-best: it puts a mutating PUT into every per-run reset, and it would silently re-create the type after a dbaas wipe in the middle of a C1, which today's gate catches.

The root cause is proven by the existing evidence, and no further VM probe is needed.

The fresh r2 single in the current boot will find the type already present. 041111Z created it, and dbaas has not restarted since. So the run proves the V4 regression, not the fix's create path. Record that plainly.

## Q1: Is the root cause proven?
Yes. Every existing i2 and r2 run already answers your proposed check (dbaas `startedAt` against the first A1 PUT).

For each run below, the dbaas start comes from `*a1mediator-restart-pods-before.json`, and "created" means `a1-type-create.txt` is present.

| Runs | dbaas container started | Type 20008 |
|---|---|---|
| `i2/20261023T171928Z`, the first TS xApp install | 2026-10-23T07:57:12Z (inferred from later runs) | **created** |
| i2 ×8 and r2 ×4, from 2026-10-23 23:59Z to 2026-10-26 14:34Z | 2026-10-23T07:57:12Z, restartCount 9 | found; every post-restart GET returned 200 |
| `r2/20261027T041111Z` | **2026-10-26T16:27:22Z**, restartCount 10 | **created** (PUT 201, 0-byte body) |

- **When the type disappears.** It is created exactly once per dbaas container lifetime, by the first gate that touches A1 after a boot.
  - The 07:57 UTC boot on 2026-10-23 is the `r0-green` create (16:57 KST).
  - The 16:26:48 UTC boot on 2026-10-26 is the `r2-green` create. The earlier dbaas container was SIGKILLed (exit 137, finishedAt 16:25:13Z) by that shutdown.
  - `vm-snapshot.sh:10` documents that a snapshot create is "graceful shutdown → snapshot → start".
- **The other hypothesis is refuted inside the same run.** That hypothesis is "the a1mediator restart deletes the type". But the type was created at 04:13:30Z, and live1's a1mediator restart (lkkn6 → bfb26, 04:18:54Z) still returned 200, with the same dbaas container. The 16 restarts in the 2026-10-26 runs also all returned 200.
- **Nothing else was in SDL.** After the PUT, `GET /policytypes` returned `[20008]` only.
- **Mechanism (consistent with the evidence, not checked on the live configmap).** The dbaas chart's redis.conf has `appendonly no` and a bare `save` line, so Redis keeps SDL in memory only. The NIST copy is `install_patch_files/ric-dep/depRicKubernetesOperator/internal/controller/getConfigmap.previous.go:305-310`.
  - Optional, read-only, and only useful for citing in the journal: `kubectl -n ricplt get cm -o name | grep -i dbaas`, then grep that configmap for `appendonly` and `save`.
- **Residual gap.** 041111Z never sent a GET before the pre restart, so "absent before the restart" is inferred, not observed. The precondition GET below closes this gap for every future run.

Restate the defect class precisely. The defect is not "the first r2 after any boot fails". It is: **the first gate that restarts a1mediator after a dbaas restart, without ensuring the type first**. i2 already ensures first, so only r2 is exposed today, and a future R3′ gate would be too if it copies r2's current order.

## Q2: Is the fix correct and complete? Does it weaken the survival assertion?
**Correctness.** Yes. Either placement removes the order dependency.

**Survival assertion.** It is not weakened, as long as the post-restart check stays a GET only, which you keep. Today the post-restart 404 conflates two cases: the type was absent before, or the restart lost it. Ensuring first makes the assertion test what its comment claims. Adding a GET before the restart makes it strictly stronger.

### Recommended edits
**1. `gate-r2-ts-stub-qp.sh`**
- Move the line-114 check, unchanged and with the same name, to just above `:107`.
- Add a comment: the type lives only in SDL, dbaas has no persistence, so a VM boot wipes it, and it must be ensured before any a1mediator restart.
- Directly after the moved check, add:
  ```
  fact a1PolicyTypeCreated "$([ -e "$e/a1-type-create.txt" ] && echo true || echo false)"
  ```
  - The value is literal `true`/`false`, so it avoids the `fact()` raw-write trap.
  - `curl -o` creates that file only on the PUT path, and the evidence directory is new for every gate run.

**2. `ts-lib.sh` `a1mediator_restart`** (`:330`)
- Before the pods-before snapshot and the pod delete, add:
  ```
  base=$(_a1) || return 1
  code=$(curl -s -m 5 -o /dev/null -w '%{http_code}' "$base/policytypes/$TS_POLICY_TYPE")
  echo "policy type $TS_POLICY_TYPE before the restart: HTTP $code"
  [ "$code" = 200 ] || { echo "policy type $TS_POLICY_TYPE absent before the restart: ensure it first (SDL is in-memory; a dbaas restart wipes it)"; return 1; }
  ```
  - When the precondition fails, the function returns before it changes any state.
- Fix the comment at `:347`: the types survive an a1mediator restart but not a dbaas restart.
- Add a one-line precondition note on `ts_stub_pods_reset` (`:281`).
- Do not use plan, phase or finding IDs in comments or test names (global rule).

### Why the gate-level ensure rather than one inside `ts_stub_pods_reset`
- It is the literal "fix the order" from the A1 ruling, and it mirrors i2.
- The per-run resets (live1..3, calib) stay free of mutations, so a mid-C1 SDL wipe still fails closed.
  - With your variant, that wipe would be re-created silently.
  - The `rc_restarts_zero` list does not include ricplt pods, and the background watchdog only flags pods that stay unready, not restarts. So nothing else would catch it.
- **If you prefer your variant** (the argument for it is that R3′ is self-sufficient), take it only with:
  - creation allowed only for the `pre` label;
  - evidence files scoped by label;
  - a `a1PolicyTypeCreated_<label>` fact.
  
  Without those conditions it is a mild narrowing.

### Other callers and orders, checked
| Caller | Finding |
|---|---|
| `gate-i2` `--part all` / `--part ts` | Ensures at `:46`, before the restart at `:64`. Safe. |
| `gate-i2` `--part stub` | Skips the ensure (`:44-47`), so it has the same latent defect. It is used only in dev; M9 runs the default `all`. Leave it: after the fix, the precondition fails fast with an accurate message. |
| `gate-p5-stray-ack-probe.sh` | Sources ts-lib but calls neither function. |
| r0 and r1 | Do not source `ts-lib.sh`. The V4 results m5, m6, m7, r0 single and r1 single are untouched, so do not re-run them. |
| `run-to-m9.sh:50,63-64` | i2 → r2 has no boundary (suffix `-`), so M9 is safe even before the fix. |

The fix still carries weight beyond V4, because these cases would hit the defect without it:
- `run-to-m9.sh --from r2` after any reboot;
- P8′ after any reboot;
- the first R2 or R3′ run after the `r3p-green` snapshot create (a boot), for example the P9 reference work.

`run-to-m7.sh` has no A1. The future R3′ gate should copy r2's corrected preamble; the precondition guard catches it if it does not.

## Q3: What to verify before the fresh r2 single
1. **Commit, push and lint.**
   - `vm-exec.sh:29-31` refuses an unpushed SHA, and the VM clones the public repo.
   - Run `scripts/gates/lint.sh` on the host.
2. **Expect the "found" path.**
   - 041111Z created type 20008 at 04:13:30Z on 2026-10-27 in this boot, and dbaas was unchanged through the end of that run.
   - Expected results: `a1PolicyTypeCreated=false`; the pre `.out` shows HTTP 200 both "before the restart" and "after the restart".
   - **Do not** force the create path:
     - a reboot is not part of this phase, and right after a boot the RIC is still settling (a1mediator was killed with 137 at 16:28:05Z on that boot), which puts the one re-run at risk;
     - deleting the dbaas pod wipes every SDL state mid-chain;
     - deleting the type is blocked by the existing instances. I believe a1mediator refuses to delete a type that has instances, and per `ts-lib.sh:407-408` the TS xApp never answers A1, so instance deletes never complete.
3. **Pre-flight the F09 export (the most likely way to lose the run).**
   - This is the first VM gate exported through the scrub that now fails closed (`1bb00a9` landed after 041111Z).
   - If the scrub exits non-zero, `vm-exec.sh:82-83` copies nothing, and a possibly green run is stranded on the VM.
   - The check is cheap and idempotent. On the VM, with `~/harness` checked out at the new SHA, run `bash ~/harness/scripts/gates/scrub-evidence.sh /home/uc/evidence/r2/20261027T041111Z`. That directory was already scrubbed, so nothing is rewritten.
   - Expect exit 0 and the message `≥1 known secret(s)`.
4. **Resume checks.**
   - `domstate` is running and `snapshot-current` is r2-green.
   - The guest boot time is still 2026-10-26 16:26:48 UTC.
   - dbaas still has restartCount 10 and started at 16:27:22Z. If it differs, the run takes the create path. That is fine with the fix, but record it.
   - No orphan agent, ns-3, pacer, tcpdump or injector container.
   - Host `/home` has ≥ 20 GB free.
5. **Run** `vm-exec.sh gate-r2-ts-stub-qp.sh --harness-sha <sha> --timeout 5400 -- --mode single`, without `--dev`. If it is red, PAUSE T6. There is no second fix.

## Q4: Does the fix change a locked acceptance signal?
No. It does not touch:
- C1–C9;
- the per-run reset contents;
- the RestartCount rules, the route checks, or A1 threshold delivery;
- the rung-config values (T_ctl, W, A1 threshold);
- any check name. Only the position of `r2_a1_policy_type_20008_present` moves.

It is not T3, because every signal can still be met as written. It is not T6's "would change the outcome", because only a bring-up precondition is re-ordered and the survival check is tightened.

R2 C1 `143406Z` stays valid. The type was present before every restart in that boot, so the new precondition would have passed there too.

## What to avoid
- A "create if it is missing **after** the restart" fallback. That would weaken the assertion.
- Reading the green from the found path as proof of the fix's create path. In the records, put the following side by side:
  - the evidence for the sequence "ensure creates the type, then the restart, then it survives": 041111Z (created at 04:13:30Z, live1 restart at 04:18:54Z returned 200);
  - the evidence the next boot will add: the first r2 or R3′ run after it shows `a1PolicyTypeCreated=true` and a PASS for the pre step.
- Capturing judge output inside a `fact` value (the `fact()` raw-write trap).

## Success metrics
- The fresh r2 single verdict is PASS with `failed=[]`.
- The pre step shows HTTP 200 both before and after the restart.
- `facts.jsonl` parses, and `a1PolicyTypeCreated` is present.
- The scrub exits 0 and the evidence is on the host.
- Later: the first post-boot r2 or R3′ run has `a1PolicyTypeCreated=true` and a green pre step.

## Assumptions
| Assumption | Confidence | What would change the answer |
|---|---|---|
| dbaas Redis keeps SDL in memory only. | High from the evidence; medium from the config source, which is NIST's operator copy, not the live configmap. | A live configmap with persistence would make the wipe at boot unexplained, so this would need a look. |
| There has been no boot or dbaas restart since 041111Z. | High (resume card) | If the step-4 checks show one, expect the create path. The fix handles it. |
| a1mediator refuses to delete a type that has instances. | Medium (belief) | Irrelevant if you follow "do not force the create path". |
| The F09 scrub passes on r2 evidence. | Unknown | The step-3 pre-flight decides it. |

## Unresolved questions
- Does the user want the create path exercised before V4 is called green? Default: no. V4 is the regression at the N4 pins, and the create path gets its proof at the next boot. Record this in the journal so the user can overrule it.
