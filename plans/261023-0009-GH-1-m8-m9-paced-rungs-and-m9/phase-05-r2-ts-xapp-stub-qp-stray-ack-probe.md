# P5: R2, TS xApp with a stub QP; stray-ack probe first

**Start state:** `r0-green` (R1 left no snapshot) with the P4 pins. **Snapshot at exit:** `r2-green`, only after the free-space check.

## Context
- The TS xApp (`ric-app-ts@19e169b`) registers only RMR 20010, 30002 and 30003 (`ts_xapp.cpp:901-903`) and has no default handler. rtmgr 0.9.6 gives every non-platform xApp a 12041/12042 route at subid −1 (`rpe.go:165-177`). Under xapp-frame-cpp 2.3.6 and RMR 4.8.1 an unmatched message may be freed twice, so glibc 2.31 should abort at the next message (kongming-1739 §5.1, static reading, not observed). User decision: probe first, patch only on a crash (substitution 2).
- The TS xApp calls `stoi(ue_id)` outside any try block (`ts_xapp.cpp:622-624`), so the stub's `ue-id` must be the decimal IMSI (§5.4).
- The TS xApp sends each control to `cell_map[target]`'s ranName (`ts_xapp.cpp:637-643`, F3). This is recorded deviation P1. `cell_map` is built once at start-up, so the TS xApp starts only after every agent is CONNECTED.
- With the stub QP and harness 30003, the TS xApp's decision is deterministic, so negatives are checked by ledger count (§5.6).

## Requirements (contract)
In scope 6 and 7; R2:
- G3: the TS xApp talks gRPC to rc:7777; starts after all agents are CONNECTED; then the A1 threshold (policy type 20008) is set explicitly.
- Stray-ack probe first: send one 12041, then one 30003, to the TS xApp; record whether it crashes. On a crash, apply substitution 2 (a one-line do-nothing default RMR handler through the Testbed fork) and report it.
- A stub RMR peer for QP (30000 in, 30002 out): fixed predictions, uppercase `%08X%02X` cell keys, decimal-IMSI `ue-id`.
- The harness sends 30003 with one UE per message.
- `cell_map` covers every gNB agent's key: each positive trigger gives a wire RICcontrolRequest whose CGI carries the stub's chosen key, addressed to the target's agent.
- Positive cases pass C1. Negative cases (serving best, or below threshold): no RICcontrolRequest, checked by ledger count plus late = 0.
- W measured (`max(1 s, 3 × p99.9 of L)`); rtmgr route dumps; RestartCount = 0 for rc, TS xApp, kpimon, hw-go and every agent; 12041/12042 −1 owner recorded.

## Files
- Create: `scripts/gates/ts-xapp-install.sh`, `scripts/gates/stub-qp-rmr-peer.py` (or a small C++/Go peer if Python RMR bindings are unavailable on the pinned image), `scripts/gates/send-rmr.sh` (30003, 12041 injection), `scripts/gates/gate-r2-ts-stub-qp.sh`, `scripts/gates/r2-scenario.json`, `scripts/gates/stray-ack-probe.sh`.
- Conditional (substitution 2 only): Testbed fork, the TS xApp install patch with the default handler.
- Modify: `scripts/run-to-m9.sh` (add gate r2).
- **Names as built (2026-10-24, kongming-1815 §3.3 step 2; they follow `run-to-m9.sh:63-64`):** `ts-xapp-install.sh` is `scripts/gates/gate-i2-ts-xapp-install.sh` (TS xApp with the gRPC override, A1 type 20008, stub, routes; M9 runs it with `--part all`). `stray-ack-probe.sh` is `scripts/gates/gate-p5-stray-ack-probe.sh`, a one-time dev run with its own evidence dir (gate id `p5`); M9 does not re-probe and inherits substitution 2 through the Testbed pin. The stub and the injector are one image, `tools/rmr-peer/` (stub `stub-qp-rmr-peer.py`, deployed as xApp `stubqp`; a persistent host-network injector `rmr-injector.py` with a static seed route, driven by `scripts/gates/send-rmr.sh`). Shared VM-side helpers: `scripts/gates/ts-lib.sh`.

## Steps
1. Install the TS xApp at the pinned SHA via `ts-xapp-install.sh`, configured for gRPC to rc:7777.
2. Run `stray-ack-probe.sh`; record the TS xApp pod state and RestartCount before and after. On a crash, apply substitution 2, reinstall, re-probe.
3. Start the stub QP; verify the 30000/30002/30003 routes in an rtmgr dump.
4. Calibration: 10 positive triggers; measure L; set W; record it.
5. Write `r2-scenario.json` (positive and negative cases); run `repeat-gate.sh r2`.
6. Free-space check, then `vm-snapshot.sh create r2-green --need-gb <n>`.
7. Phase-exit checklist.

## Verify (comparison only)
- V1: `stray-ack-probe.sh` writes `probe.json` with `crashed: true|false`; if true, the post-substitution re-probe has `crashed: false` and RestartCount unchanged.
- V2: `gate-r2-ts-stub-qp.sh` exits 0; `verdict.json` C1 fields all true for the positive set.
- V3: every positive trigger: exactly 1 RICcontrolRequest whose decoded NR CGI ends in the stub's key, sent to the target gNB agent; exactly 1 terminal answer.
- V4: negatives: ledger has 0 lines for negative triggers; `verdict.json` `late = 0`.
- V5: `verdict.json` has `wSeconds`, `restartCounts` all 0, `routeOwner12041`, `routeOwner12042`, `substitution2Applied`.
- V6: `vm-snapshot.sh list` shows `r2-green`.

## Standards ledger
| Decision | Document, version, section | Zotero | Read |
|---|---|---|---|
| The TS xApp addresses the target node — **recorded deviation P1** | 3GPP TS 38.300 §9.2.3.1, §9.2.3.2.1; 3GPP TS 37.340 §10.5.1 | per decision record §2 | 2026-10-22 |
| UE ID on the wire — **recorded deviation P4** | E2SM common v07.00 §6.2.2.6 | `QW6VJ83M` | 2026-10-22 |
| A1 policy for the threshold | O-RAN A1 policy type 20008 as defined by the TS xApp (no 3GPP/O-RAN spec decision) | — | — |
| Substitution 3 (user, 2026-10-24 08:25 KST): the TS xApp also parses the 20010 policy body that a1mediator 3.2.2 sends as a JSON string under `payload` (L finding 3, for Stop B) | No spec decision: the 20010 RMR message is an O-RAN SC internal format between a1mediator and the xApp, not the A1AP REST interface (the REST body the harness PUTs is unchanged) | — | 2026-10-24 |
| The TS xApp's control header: `gNB-UEID` with AMF UE NGAP ID = IMSI, GUAMI fixed by the TS xApp (region `10100000`, set `0000000000`, pointer `000001`), gNB-CU UE F1AP ID and gNB-CU-CP UE E1AP ID both = IMSI. rc's encoder ignores the gRPC cell type and AckRequest. The E2SM-RC message equals rc-send's (same NR CGI, PLMN from e2mgr); only the header's GUAMI and the F1AP/E1AP IDs differ. Inside **recorded deviation P4** (the gNB choice is the deviation); the F1AP and E1AP lists are conditional (ifCUDUseparated, ifCPUPseparated) and "may not be included" from the RIC, so including them is allowed | E2SM common v07.00 §6.2.2.6 (UE ID table, pp. 13–14, conditions ifCUDUseparated, ifCPUPseparated) | `QW6VJ83M` | 2026-10-24 |
| Stray acks: 12041/12042 at subid −1 reach the TS xApp through rtmgr's catch-all route | No spec decision: O-RAN SC RMR and rtmgr behaviour, not E2AP (E2AP v03.00 defines the RICcontrolAcknowledge/Failure PDUs, not their RIC-internal routing) | — | 2026-10-24 |
| The harness registers the TS xApp and the stub with appmgr (`POST /ric/v1/register`, body from the deployed descriptor, as ricxappframe 3.2.2 builds it); xapp-frame-cpp 2.3.6 never registers and appmgr 0.5.8 lists, so rtmgr routes, only registered xApps (L finding 2, T5 reading with an L-only remedy) | No spec decision: O-RAN SC appmgr/rtmgr behaviour (A1 20010 delivery and the 30000/30002 routes depend on it) | — | 2026-10-24 |
| RAN function 3 (RC) is not announced in E2 Setup; the agents accept RC controls anyway | **Recorded deviation P8** (user ruling 4, 2026-10-24): E2AP v03.00 §8.2.4.3 expects a FAILURE for an unannounced function. Recorded, not fixed | `WEE5IEXF` | 2026-10-23 |

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
A red C1 is re-run only after its root cause is recorded and a change committed, then as a full fresh set. Any TS xApp change beyond substitutions 2 and 3 is an outcome change: PAUSE T3 (substitution 3 added by the user on 2026-10-24 08:25 KST).

## Phase exit
Run the plan's phase-exit checklist, then spawn kongming (`model: opus`) for a go/no-go on P6.

## Risk and rollback
Risk: the TS xApp crashes even with substitution 2 (for example, a crash on a different path); that is T3. Rollback: revert VM to `r0-green`; revert the harness and Testbed commits.

## Review amendments (binding; they override any conflicting text above)
Source: `plans/reports/kongming-261023-0020-GH-1-m8-m9-plan-collect-only-review.md`, classified in `plans/reports/review-261023-0009-GH-1-m8-m9-contract-preserving-review-and-preflight-matrix.md`.
- **K12 (stub).** The stub QP registers as an xApp through a descriptor, has a safe default RMR handler, and is undeployed before any QP deploy. V7: an rtmgr dump shows exactly one receiver for 30000.
- **K12 (probe).** The probe sends the 12041 straight to the TS xApp's RMR endpoint (a static seed route in the sender), and `probe.json` records the endpoint used.
- **K10.** V3 also requires ≥ 1 positive trigger per gNB key, and verdicts carry the C5 and reset fields.
