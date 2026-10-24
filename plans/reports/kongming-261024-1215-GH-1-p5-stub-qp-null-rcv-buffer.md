# Kongming: P5 gate i2 --part stub, stub QP dies on the first idle RMR wait

Advice only, not user approval. Runtime: Claude Code, Opus 5.5.

## TL;DR
Your reading is correct; I checked it against the RMR 4.9.0 and ricxappframe 3.2.2 source. Add `if not buf: continue` to all three receive loops: the stub, the injector, and the self-test's own loop, which has the same bug. Make a dead injector receiver kill the injector process, and extend the self-test to cover "idle before a message" and "idle after a message". Then commit and re-run `i2 --part stub` fresh. This is a plain harness bug, so no PAUSE is needed. The p5 PASS stands.

## Q1: the source confirms NULL on timeout; the guard is correct and safe
- RMR tag `4.9.0` resolves to commit `a1be12a`, the same commit named in the injector.log banner. `rmr_torcv_msg` calls `rmr_mt_rcv(ctx, old_msg, ms_to)` (`rmr_si.c`).
- In `rmr_mt_rcv`, a buffer passed in gets `state = RMR_ERR_TIMEOUT, len = 0` before the wait. When `sem_timedwait` times out, the code runs `mbuf = ombuf; // return caller's buffer if they passed one in`, so it returns NULL when none was passed in. It also returns `ombuf` when the semaphore fires but the ring is empty. When a message arrives, it returns the ring mbuf with `RMR_OK` and calls `rmr_free_msg(ombuf)` itself.
- In ricxappframe 3.2.2 (wheel sha256 `5a7d839b…`, the same as `requirements.txt`), `_rmr_torcv_msg` has restype `POINTER(rmr_mbuf_t)` (`rmr/rmr.py:457`). `message_summary` reads `.contents` (`rmr.py:847`) and raises `ValueError: NULL pointer access`. The framework's own receive path (`rmr/helpers.py:54-57,96-97`, used by `xapp_rmr.py:92`) always passes a pre-allocated buffer, which is why it never sees NULL.
- `buf = rmr.rmr_torcv_msg(ctx, buf, 1000); if not buf: continue` is safe:
  - No leak: a NULL buffer owns no memory.
  - No double free: you never free the receive buffer yourself. RMR either frees it on the next receive or hands it back on timeout.
  - No reprocessing: a buffer handed back on timeout carries `RMR_ERR_TIMEOUT` and `len 0`, so the existing TIMEOUT check still skips it.
  - No busy loop: NULL only comes back after the full 1 s wait.
- **Trap:** `if buf is None` does not work. A NULL ctypes pointer is falsy but is not `None` (I checked this locally). Do not call `rmr_free_msg` on it either, because the wrapper only checks `is not None`.
- Pre-allocating one buffer before the loop (`rmr.rmr_alloc_msg(ctx, 4096)`, as `helpers.py` does) is also correct. The guard is better because one line covers every path that can return NULL. You do not need both.

## Q2: the p5 PASS still holds
- V1 is judged on the TS pod: RestartCount 0 and the same uid `2a81a9db…` before and after both variants.
- The TS log shows it handled every 30003 sent after the stray acks. `burst-ts.log` (cumulative) has 7 `AD Callback got a message, type=30003` lines, and `injector/tx.jsonl` records 7 sends of 30003, all with state 0.
- The dead receiver could not affect the TS xApp. RMR's own receive thread keeps accepting messages and puts them on the ring, dropping them when the ring is full (`mt_call_si_static.c:43-44`). The TS xApp's sends therefore see no back-pressure.
- No gate script reads `rx.jsonl`. The only thing lost is diagnostic data (whether the TS xApp sends anything back to the injector).
- Do not re-run p5. Record the caveat in implementation-notes, not in the evidence directory, so the evidence stays unchanged.

## Q3: a harness bug fix, no PAUSE
Only `tools/rmr-peer` changes. The fix restores K12's "safe default RMR handler" rather than changing it, and the TS xApp is untouched, so T3 does not apply. This is the first run of the stub part, so the Failure Protocol allows one re-run. If it fails again, PAUSE T6.

Steps:
1. Add the guard after `rmr_torcv_msg` at `stub-qp-rmr-peer.py:104`, `rmr-injector.py:56` and `rmr-peer-selftest.py:72`, with the comment you proposed.
2. Make the injector receiver fatal on any error: wrap its body in `try/except BaseException`, then call `traceback.print_exc()` and `os._exit(1)`. A daemon thread that dies quietly is how this bug hid during p5. With this change, the next `send-rmr.sh` call fails and the gate goes red. A `health` op that reports whether the receiver is alive also works, but it is more code and every gate would have to remember to call it.
3. Extend `rmr-peer-selftest.py` (it runs inside the image, no RIC needed):
   - Stub: start `stub-qp-rmr-peer.py --rmr-port 4594 --http-port 18080` as a subprocess, with `RMR_SEED_RT` (including `mse|30000|-1|127.0.0.1:4594`) and `RMR_RTG_SVC=-1`. After the `RMR ready` line, sleep 2.5 s and check it is still running and `/health` returns 200. Then PUT a table, send one 30000, sleep 2.5 s again, and check it is still running and `/log` has exactly 1 rx record. This covers the case where an idle wait follows a received message.
   - Injector: after the existing loopback, sleep 2.5 s and check `p.poll() is None`. Because of step 2, this proves the receiver survived the idle time. Then send one message from the self-test context to port 4592 (for example, add the seed row `mse|30004|-1|127.0.0.1:4592`) and check that `rx.jsonl` gets exactly 1 line within 5 s.
4. Optional but cheap: in `stub_install` (`ts-lib.sh:176`), after `_wait_new_ready`, wait 5 s or more, then check that the stub's restartCount is still 0 and its log has no `Traceback`. Today the Ready check passes a pod that crashes about 1 s after it starts.
5. Make one commit, following the repo's `test(gates): …` style, with no plan or phase IDs. The image tag is the tree id of `tools/rmr-peer`, so the image rebuilds and the self-test runs again.
6. Re-run `scripts/vm/vm-exec.sh gate-i2-ts-xapp-install.sh -- --part stub` fresh.

What proves the fix:
- `rmr-peer-selftest.txt` shows `ok` for the new lines and `pass: true`.
- The rmr-peer image tag is no longer `a33ffe32d8ea`.
- `verdict.json` has `pass: true` and `failed: []`.
- In `i2-pods.tsv`, the stub row is a new pod with RestartCount 0, started at least 30 s before the snapshot. The gate's own runtime provides that idle time.
- The stub pod log has `stubqp: RMR ready on 4560` and no `Traceback`.
- Every other pod still has RestartCount 0.
- At r2, `injector.log` has no `Traceback`.

## Q4: other code in tools/rmr-peer
- **The same bug:** in `rmr-peer-selftest.py:71-74`, `buf` starts as `None` with a 500 ms wait. A loopback slower than 500 ms raises the same ValueError, which shows up as a flaky gate failure. Fix it the same way (step 1).
- **The send paths are safe:**
  - `rmr_send_msg` returns NULL only when malloc fails (`sr_si_static.c:158-162,234-236`) or in an internal fan-out case that cannot happen with a caller's buffer (`:643-646`).
  - A successful send returns a new buffer with `RMR_OK`; a failed send returns the original buffer. So the existing pattern (`out = send`, read the state, free) has no leak.
  - `rmr_alloc_msg` raises `BadBufferAllocation` instead of returning NULL (`rmr.py:302-328`).
- **A similar risk, optional:** if `PUT /table` loads a malformed table, `int(v[0])` or the tuple unpacking in `build_prediction` raises inside the stub's only loop, and the stub dies. The harness owns the table, so the risk is low. Checking the table shape at PUT and returning 400 would close it.

## What to avoid
- Do not free `buf` after processing a message or on timeout. That causes a double free on the next receive.
- Do not work around the bug by changing the timeout to block forever, or by adding a liveness probe. Neither fixes the cause.
- Do not edit the p5 evidence, re-run p5 for this, or touch the TS xApp.

## Assumptions
- The image runs RMR 4.9.0 `a1be12a` (high confidence: the banner in injector.log says so).
- The image's ricxappframe is 3.2.2 as pinned by hash (high).
- This is the first run of `i2 --part stub`, so one re-run is allowed (high: the other five i2 runs in evidence did not include stub checks). If an earlier stub run had failed, the next failure means PAUSE T6.
- I did not read the VM-side stub logs. I relied on your traceback, which matches the p5 `injector.log` traceback exactly (medium-high).

Status: DONE
Summary: The RMR NULL-on-timeout reading is confirmed at source; `if not buf: continue` is correct and leak-free. Apply it in the stub, injector and self-test loops, make the injector receiver fatal, add idle self-tests, and re-run i2 --part stub; the p5 PASS stands.
