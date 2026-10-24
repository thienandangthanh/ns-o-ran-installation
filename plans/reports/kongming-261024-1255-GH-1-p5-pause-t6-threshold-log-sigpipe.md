# kongming: P5 PAUSE T6, threshold-log SIGPIPE (gate i2 --part stub run 2)

This is advice only and is not user approval. Model: Opus 5.5, per the user's CLAUDE.md. The VM was used read-only: `kubectl logs` and local bash tests, nothing else.

## TL;DR
- **Diagnosis:** confirmed. The VM reproduction gave `141 0` three times out of three.
- **Pause id:** T6 is the right id, and no other id applies.
- **The proposed check has a hole.** Count-rise plus "Payload is" would have passed at attempt 1 on a stale line. The TS xApp's unflushed threshold line from the *previous* run surfaces together with this run's first payload line (log line 157).
- **Use an ordering rule instead:** pass only on a threshold line that comes *after* this call's first `Payload is` line. That is strictly stronger than both the old check and the proposed one.
- **Also fix `ts_ready`.** It is load-bearing. Its `printf | grep -q` dies at 60 KB and above. The kept TS pod's log grows about 19 KB/h from RMR stats lines alone, so it crosses that size around 14:00–15:00 KST. After that, the resume run would go red at `i2_ts_ready_listening_no_control_api_error`.
- **Verdict:** conditional GO.

## 1. Diagnosis (verified)
- **The pattern** is `ts-lib.sh:398`, `kc logs | grep -q`, under `set -uo pipefail` (`lib.sh:14`).
- **VM reproduction on pod `…-2hx5c`** (log 175 lines, 26 KB):
  - `grep -q` gave PIPESTATUS `141 0` three times out of three;
  - `grep -c` gave `0 0` twice out of two;
  - so kubectl gets SIGPIPE only when its reader stops early.
- **The stale lines are real.** The log holds instances from 030327Z (lines 18, 29) and 030903Z (lines 123, 136) before this run's 032221Z-1, -2 and -3 (lines 159, 162, 165). The first match is at line 27.
- **Why run 5 (`--part ts`) passed:** the pod was fresh, so the matching line was near the tail and kubectl had nothing left to write. That fits the diagnosis.

## 2. Pause id
- **T6** fits the literal reading of phase-05 Failure Protocol line 65: the same Verify step, re-run after a kongming-guided fix, failed again. A different root cause does not reset the count.
- **Not T3.** The acceptance signal is still met as written: the threshold line in the TS log. The fix changes only how the harness reads it, and makes the reading stricter.
- **Not T5.** This is a harness bug, not an L-release failure.
- **Not T4.** No new deviation from a standard is involved.
- **Record the stricter criterion** as a decision in `implementation-notes.html`.

## 3. Fix review

### 3.1 The hole in "count rises + this instance's `Payload is`"
- **Buffering.** The TS xApp writes `Setting Threshold…%\n` with no flush (`ts_xapp.cpp:535`). The `endl` on `Payload is` (`:517`) flushes everything buffered before it.
- **What the log shows:** line 157 is the threshold line of `030903Z-2`. It became visible only when `032221Z-1`'s callback flushed (lines 157–159 arrived together; RMR's `sends:` stats lines go to stderr and land in between).
- **What the proposed check would do:** before attempt 1 the count was 3 (lines 27, 47, 134). After attempt 1 it was 4, from the stale line 157, and `Payload is …032221Z-1` was present. So it passes at attempt 1, while this run's own threshold line is still in the buffer.
- **When that becomes a false pass:** when a later payload stops parsing but the previous run left a buffered line with the same threshold.

### 3.2 Use ordering instead
- **Why ordering works:** stdout keeps order, and only `policy_callback` prints `Setting Threshold`. So any threshold line after this call's first `Payload is …"policy_instance_id":"<id>-` must come from this call.
- **Which attempt passes:** normally attempt 2, because instance 1's line is flushed by instance 2's callback. That is the same as today's `a1ThresholdAttempt=2` note.
- **Strictness:** every pass of the new rule is also a pass of the old grep and of the count-rise rule, so it is strictly stronger than both.
- **Delivery to the current pod:** this pod's container log must contain this call's payload, so delivery to the current pod is proven too. A restarted container fails the check, which is correct, because the threshold resets to 0.

The matcher (load-bearing):
```bash
# ts_threshold_logged <log-file> <id> <th>: a threshold line after this call's first A1 payload line
ts_threshold_logged() {
    awk -v p="\"policy_instance_id\":\"$2-" -v t="Setting Threshold for A1-P value: $3%" '
        index($0, "[INFO] Payload is ") && index($0, p) { seen = 1; next }
        seen && index($0, t) { found = 1; exit }
        END { exit !found }' "$1"
}
```
In `ts_policy_set`:
1. Each poll runs `kc -n ricxapp logs "$pod" >"$EVIDENCE_DIR/$id-ts-log.txt" 2>/dev/null`, then `ts_threshold_logged`.
2. Print the matched lines from the file. The last file stays as evidence.
3. Optional fact: `a1DeliveredAttempt`, the lowest k that has a `Payload is` line. It separates a delivery delay (L finding 4) from the flush artifact. Record it; do not judge it.
4. Known limit, the same as today: if only instance 3 is delivered, its line stays buffered and the check fails. Accept this, because it signals a delivery problem.

### 3.3 Other sites to fix in the same change
The candidate regex in 3.4 flags exactly these 5 lines.

| Site | Effect today | Fix |
|---|---|---|
| `ts-lib.sh:155,158` `ts_ready`: `printf '%s\n' "$logs" \| grep -q` | **False FAIL once the log is about 60 KB or more.** On the VM's bash 5.2.21 it gave 141 in 2 of 3 runs at 60 KB and 3 of 3 at 70 KB (0 of 6 at 26 KB). RMR stats lines add about 1.6 KB every 301 s, so the kept TS pod (`2hx5c`, 26.5 KB at 03:28Z) reaches about 60–70 KB around 05:15–05:45Z. It runs in i2 `--part stub`, p5 and r2 `ts_at_pin`. | `grep -q 'listening on port 4560' <<<"$logs"` |
| `ts-lib.sh:307` `ts_nodeb_list_check` `grep -m 1` | It gave 141 in 3 of 3 runs on this pod. **It does not fail the check:** `$line` is still captured and the check after the loop only tests that it is non-empty. The cost is about 30 × 2 s of wasted polling. The journal's claim that "r2 would hit it next" overstates this. | `line=$(grep -m 1 'nodeb list is' < <(kc … logs "$pod" 2>&1))` |
| `ts-lib.sh:434` `injector_start` `dk logs \| grep -q '^READY'` | Low risk: READY is the injector's last stdout line. But docker writes each log frame separately, so any later line would SIGPIPE it and fail after 10 s. | `grep -q '^READY' < <(dk logs "$INJ_NAME" 2>&1)` |

These sites are safe and need no change:
- `rc-lib.sh:94`: the pipeline status is ignored and only `-n "$line"` is tested. The journal's claim that it is a "file-first workaround" is wrong: printf into a pipe is not SIGPIPE-proof.
- `gate-m3-xapps.sh:105`: it uses process substitution.
- `grep -c` and `grep -E` without `-q`: they read the whole input.

### 3.4 Recurrence guard (cheap, recommended)
This is the third time the pattern has appeared. Add the following to `lint.sh`:
- a fixture test:
  - build a log from lines 155–165 of this pod;
  - with only the stale line 157 and `Payload…-1`, the check must not pass;
  - with line 160 added, it must pass;
  - the old construction must return 141 on a fixture of 70 KB or more;
- a failing lint pattern:

  ```
  grep -nE '(\blogs\b[^|#]*|"\$[a-z_]*logs?"\s*)\|\s*(grep\s+-[a-zA-Z]*[qm]|head\b)' scripts/gates/*.sh
  ```

  Today it flags exactly `ts-lib.sh:155`, `:158`, `:307`, `:398` and `:434`.

## 4. Go/no-go
**Conditional GO** to resume at i2 `--part stub`, then r2 `--mode calibrate`. The conditions:
1. The user releases T6.
2. The fix covers `ts_policy_set` with the ordering rule, plus `ts_ready`, `ts_nodeb_list_check` and `injector_start`.
3. `lint.sh` passes, including the fixture and the lint pattern.
4. The resume checks and the boot-time check match the card.
5. i2 `--part stub` runs fresh. A plain re-run would fail again, because the 141 is deterministic, so a green run proves the fix.
   - Expect `a1ThresholdAttempt=2` and `a1DeliveredAttempt=1`.
   - Expect the saved `$id-ts-log.txt` to show the matched threshold line after `Payload…-1`.
6. Then r2 calibrate. Its per-run reset gives a fresh TS pod, so no stale lines are expected there, but the ordering rule holds either way.
   - **No-go trigger:** any i2 red other than an L-release cause. That is a third harness red in this segment, so stop and re-scope rather than patch again.

## Assumptions
- **The containerd log keeps stdout order within one stream** (high confidence; it matches every TS log seen). If it did not, ordering would need per-line timestamps (`kubectl logs --timestamps`).
- **The a1mediator payload keeps the exact `"policy_instance_id":"<id>"` spelling, with no spaces** (high confidence; verified in the live log).
- **The RMR stats interval stays about 301 s** (medium confidence). Growth could be faster during traffic, which only makes the `ts_ready` fix more urgent.
- **A record nit (low impact):** plan.md and the journal are stamped 12:55 KST, but the host and VM clocks read 12:28 KST when I checked. Keep evidence timestamps from the clock.

Status: DONE
Summary: Diagnosis confirmed and T6 is correct. Replace count-rise with "a threshold line after this call's first payload line", and also fix `ts_ready` before resuming (conditional GO).
