# P5 pause T5: user ruling on the A1 payload shape (substitution 3)

Date: 2026-10-24 08:25 KST. Source: the user's message "allow a third substitution", sent while the M8–M9 goal was being re-issued after PAUSE T5 (`docs/journals/2026-10-24-m8-m9-p5-pause-a1-payload.md`, section 3). It selects option 1 of that journal and of kongming's pause note (`plans/reports/kongming-261024-0320-GH-1-p5-pause-a1-payload-string-ts-xapp.md`, section 4).

## Ruling
The goal packet's list of allowed substitutions gains a third entry:

> (3) the TS xApp also parses an A1 policy body that a1mediator 3.x sends as a JSON string under `payload` (a patch of 13 added lines to `src/ts_xapp/ts_xapp.cpp`, applied unconditionally through the Testbed fork installer before the image build); every verdict carries `substitution3Applied`.

The amendment is written into `goal-packet.md` ("Allowed substitutions"), marked as the user's amendment of 2026-10-24 08:25 KST. Everything else stays Decision required, as before.

## What this settles
- In-scope item 6 ("then the A1 threshold is set") is met end to end through A1 and the L a1mediator 3.2.2. No harness bypass.
- The R2 n2 negative stays the wire-level proof that the policy took effect. No test changes.
- The phase-05 Failure Protocol now reads "any TS xApp change beyond substitutions 2 and 3 is an outcome change: PAUSE T3".
- P8 (R3) and M9 inherit the patch through the same Testbed pin.

## Conditions carried from kongming's checklist (section 5)
1. A separate, named patch step in `install_xapp_traffic_steering.sh` before the build. Substitution 2 stays a separate, probe-conditional step. The install fails if the patch does not apply.
2. The patched build cannot be silently skipped: the patch step rewrites the source, so the installer's "newer than trafficxapp.tar" check rebuilds. Gate i2 also asserts that the tree diff equals the committed patch, and that the image ID changed when the tree was unpatched before the install.
3. `TESTBED_SHA` moves. `git diff --stat <old>..<new> -- RAN_Intelligent_Controllers/Near-Real-Time-RIC/ns3_e2_agent` must be empty, so R0/R1 and M5–M7 need no re-run.
4. A standards-ledger row: the A1 20010 payload shape is an O-RAN SC RMR-internal format, not an A1AP decision.
5. L finding 3 goes on the Stop B list next to L finding 2. The upstream bug in the TS xApp's `String()` handler (it inverts the `operation` comparison) is recorded, not fixed.
