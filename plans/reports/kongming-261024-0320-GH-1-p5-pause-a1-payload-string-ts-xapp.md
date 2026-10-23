# kongming: P5 pause, the A1 threshold reaches the TS xApp but is never parsed

2026-10-24, KST. Model: Opus 5.5 (the caller's routing). This is advice only and never user approval. The VM was inspected read-only; nothing was changed.

**What was verified**
- **Source at the pins**, cloned into the scratchpad:
  - OSC `ric-plt/a1` tag `3.2.2` (`540cb28`, `container-tag.yaml` = 3.2.2), plus `origin/master` (tag 3.2.3, the M release) and the Python tag `2.5.2`;
  - `ric-app-ts` `19e169b`.
- **VM:**
  - a1mediator image `ric-plt-a1:3.2.2` (`sha256:7aca81db…`).
  - Its 10 restarts are VM reboots: last state `Completed`, exit 0, and it has been up since 2026-10-23 07:57 UTC. They do not matter here.
  - The TS installer builds the TS xApp from source, with `sed -i` edits at lines 75 and 83 and `docker build` at line 129.
- **Evidence:** `evidence/i2/20261023T180301Z` (`ts-a1-callback-lines.txt`, `checks.jsonl`, `a1-type-20008.json`).

## TL;DR
- **The cause is confirmed at the pins.** It is an upstream incompatibility between the L-release a1mediator and the TS xApp, dating from the I release.
  - a1mediator 3.x builds every 20010 with `payload` as a JSON string.
  - The TS xApp at `19e169b` was written for the Python a1mediator's object payload.
- **There is no L-only, no-code remedy.** I checked the API path, the policy type schema, the a1mediator config, other a1mediator versions and the TS xApp config. None of them helps.
- **PAUSE id:** T5 is the right id to print. T3 and T6 also apply, and the journal already says so.
- **Recommendation:** option 1. Add a third substitution: a minimal TS xApp patch that accepts both payload shapes, applied unconditionally through the Testbed fork installer.

## 1. Cause, verified read-only
- **a1mediator 3.2.2 (Go):**
  - `pkg/rmr/messages.go:32-37`: `PolicyMessage` marshals `map[string]string{"operation", "policy_type_id", "policy_instance_id", "payload": httpBody}`.
  - `pkg/resthooks/resthooks.go:395-423`: the PUT body is first `json.Marshal`led into `httpBodyString`, validated, and passed as that string, then sent as mtype 20010.
  - Every other 20010 sender uses the same function:
    - DELETE (`resthooks.go:751`, payload `""`);
    - the A1_POLICY_QUERY replay (`pkg/rmr/rmr.go:174-180`).
  - So `payload` is always a JSON string, and `policy_type_id` is a string (`"20008"`).
  - `messages.go` has not changed since the Go rewrite (`b7a743a`, 2022-12-07). Master/3.2.3 is identical.
- **The older Python a1mediator 2.5.2** (`a1/messages.py:22-31`) sent `payload` as an object. That is the shape the TS xApp documents in its own comment (`ts_xapp.cpp:143-144`).
- **TS xApp `19e169b`:**
  - `PolicyHandler` (`ts_xapp.cpp:141-207`) sets `found_threshold` only in `Int`/`Uint` under the key `threshold` (`:165-167`, `:178-180`).
  - A string `payload` arrives as a single `String` event under the key `payload`, so the threshold is never seen.
  - `policy_callback` (`:509-525`) parses once and logs `Setting Threshold` only when the threshold was found.
  - `downlink_threshold` starts at `0` (`:96`) and has no other setter. There is no `getenv` and no config key for it.
  - It is used only when it is `> 0` (`:719-720`).
- **The A1 delivery path is proven to work:** route, session, the "message sent" log line, and three callbacks with `length=123`. The failure is only the parse, not L7 (stale a1mediator→TS connection), which is still unobserved.

## 2. No L-only, no-code remedy (each one checked, not guessed)
- **A different API path:** the swagger lists only `/A1-P/v2/...` and `/data-delivery` (`api/swagger.yaml:311`). `/data-delivery` sends mtype 20017 (`resthooks.go:51`), which the TS xApp does not register (`ts_xapp.cpp:901-903`). Every 20010 path goes through `PolicyMessage`.
- **A different policy type schema or body shape:** the schema only validates. Whatever the body is, it is marshalled and then nested as a string, and `json.Marshal` escapes it, so the body cannot inject a top-level key.
- **a1mediator config:** it covers only RMR, ports and logging. Nothing in it touches the message shape.
- **Another a1mediator version:** M/3.2.3 behaves the same. Python 2.5.x is pre-I and not L, which breaks "L-release only".
- **TS xApp config or env:** none exists for the threshold.

## 3. PAUSE id
- **Print `PAUSE T5`.** The trigger is the L incompatibility, and its root cause is now recorded. The plan's rule for that case is "on an L failure: stop, find the root cause, report (T5)".
- **T3 and T6 also apply,** for these reasons:
  - **T3:** every remedy is either a TS xApp change beyond substitution 2 (the phase-05 Failure Protocol makes that T3) or a narrowed or bypassed acceptance signal.
  - **T6:** the i2 re-run is red after one kongming-guided fix.
- The journal's wording is correct. One reading I advise against: the line is not T6 alone, because T6 hides the cause.

## 4. Options for the user
| Option | What it is | Contract cost | P8 (R3) | M9 |
|---|---|---|---|---|
| **1 (recommended):** substitution 3, a TS xApp patch | In `PolicyHandler::String`, keep the `payload` string. In `policy_callback`, when `!found_threshold` and that string is non-empty, re-parse it with a fresh `Reader`. About 8 lines, and the object shape still works. Apply it with the installer's existing `sed`/patch step before `docker build`, unconditionally (it does not depend on the probe). | A TS xApp change, so it needs a user ruling as substitution 3. A1 stays end to end, and the n2 negative stays the wire-level proof that the policy took effect. | Inherits it through the same TS image. No test changes. | Inherits it through the Testbed pin, with a fresh build from `fresh-install`. |
| 2: harness injector sends 20010 with an object payload straight to the TS xApp | No code change. The injector already has a static seed route to the TS xApp. | Bypasses A1 and the a1mediator, so "the A1 threshold is set" becomes untrue as written (T3). i2 would have to drop its threshold check, which is a test change. A forged message would be recorded as a deviation. | The forged A1 is carried into the R3 reference. | The same; the M9 verdict would rest on a fake A1. |
| 3: threshold 0, drop or re-shape n2 | Run with no policy. | Breaks "never weaken, narrow or skip a test". n2 is the only wire proof that A1 took effect. **Reject.** | The threshold becomes meaningless in R3. | The same. |
| 4: patch the a1mediator to send an object (for example, `json.RawMessage`) | An L platform fork. | Bigger blast radius: every xApp that expects the 3.x string shape is affected. The TS xApp is the stale party, so the fix belongs there. **Reject.** | Not applicable. | Not applicable. |

## 5. If the user picks option 1, the checklist
1. **Testbed fork, `dev/l-release-nist180`:**
   - Add a separate, named patch step for "A1 payload shape" in `install_xapp_traffic_steering.sh` before line 129.
   - Keep substitution 2 a separate, probe-conditional step.
   - Fail the install if the patch does not apply.
2. **Defuse "already built, skipping".** The VM holds the unpatched image `sha256:d12fd514…`. Key the skip on the patched source, or remove the image, so the patched build cannot be silently skipped. i2 must then assert that the image ID changed and that the tree diff equals the expected hunk.
3. **Bump `TESTBED_SHA`.** Show that `git diff --stat 4c8397d0..<new> -- <agent dir>` is empty, so the agent tree is unchanged and R0/R1 and M5–M7 need no re-run. Record that.
4. **Re-run i2 `--part ts` fresh.** It is green when the TS log shows `Setting Threshold for A1-P value: 10%`. Then continue the planned sequence: p5 → i2 `--part stub` → r2 calibrate → `--dev` (watch L7 over 2 or more resets) → C1.
5. **Records:**
   - Add `substitution3Applied` to the verdicts.
   - Add a standards-ledger row: "A1 20010 payload shape: no spec decision; OSC RMR-internal format, not the A1AP REST interface".
   - Put "L finding 3" on the Stop B list next to L finding 2.
   - Note the upstream bug in the TS xApp's `String()` handler (it inverts the `operation` comparison). Record it; do not fix it.

## Assumptions
| # | Assumption | Confidence | What would change the answer |
|---|---|---|---|
| A1 | The deployed `ric-plt-a1:3.2.2` image was built from tag `3.2.2`. | High (the tag and `container-tag.yaml` agree; the wire capture matches the code) | Nothing: the evidence's payload line already shows the string shape. |
| A2 | The user accepts a TS xApp patch as substitution 3. | Medium | If refused, only option 2 remains viable, and it needs its own ruling on the A1 bypass. |

## Unresolved questions
- The user's ruling: option 1, 2 or 3.
- L7 (a1mediator→TS after a TS pod replacement) is still to be observed in the `--dev` runs.

Status: DONE. The cause is verified at the pins (a1mediator 3.2.2 sends the payload as a JSON string; the TS xApp `19e169b` reads only an integer `threshold`). No L-only no-code remedy exists. Print PAUSE T5 (T3 and T6 also apply). I recommend option 1: an unconditional substitution 3 through the Testbed fork that accepts both payload shapes.
