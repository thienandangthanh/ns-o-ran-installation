# Phase 6b Stage D — M-RC4: TS-Driven Mock Closed Loop (DONE)

**Date**: 2026-06-28
**Status**: **GREEN — M-RC4 achieved & asserted.** A mock RMR prediction drove the TS xApp's own gRPC control → 2 distinct forced mmWave handovers, 2 IMSIs, 2 owning gNBs, no grpcurl.
**Component**: TS xApp (deployed testbed binary) → rc → ns-3 E2SM-RC control path; new in-cluster mock-QP injector + re-runnable harness.
**Deliverables (committed)**: `scripts/phase6b-{mock-qp-inject.py,injector.Dockerfile,closed-loop-run.sh}`, `scripts/l-release-validation/m-rc4-closed-loop.sh`, `assert-pcap.sh` control-req/ack checks.

## What Happened

Built and ran the live closed loop the parent plan left as the user-gated demo: an **unsolicited RMR `TS_QOE_PREDICTION` (mtype 30002)**, injected in-cluster, makes the OSC Traffic-Steering xApp emit its *own* gRPC `SendRICControlReqServiceGrpc` to rc → ns-3 forced handover — replacing the Phase-4/5 `grpcurl`. End state: `phase6b-closed-loop-run.sh` prints `RESULT: PASS`, `m-rc4-closed-loop.sh` exits 0. Two UEs handed over: **imsi 1 cell 2→4**, **imsi 7 cell 2→5** (distinct owning nodes …04/…05), each ACK'd; pcap carries 2 RICcontrolRequest + 2 RICcontrolAcknowledge.

No fork code changed — the SCTP fix + Decision-4 identity work were already committed (`222ac76`). Stage D is pure orchestration + a Python injector.

## Three things diverged from the plan (the real story)

**1. The D0 TS rebuild was unnecessary — the plan's premise was wrong on this E2MGR.**
The plan assumed the *running* TS had a broken/empty `cell_map` until rebuilt with the committed case-fix. Live truth: the deployed (un-rebuilt) image builds a working `cell_map` — keyed **UPPERCASE** `16B8CE0N0N`. Why: the served `e2nodeComponentRequestPart` decodes uppercase (Stage C′), and the old code `toupper`'d the gNB-id prefix, so uppercase-vs-uppercase matched. The committed lowercase "bilateral case-fix" only changes the resulting key *case*; it fixes no real breakage here. ⇒ mock JSON keys must be **uppercase** against the deployed image. First lowercase injection dropped (`Cannot find RAN name = 16b8ce0404`); uppercase routed immediately. **User decision: skip the rebuild** (keep working image; the fix stays in testbed source, undeployed).

**2. The actual Stage-D fragility is a flaky rc pod, not the protocol.**
First uppercase inject: TS built a perfect control (`ranName gnb_734_373_16b8ce04`, `TargetCellID 16B8CE0404`, amfUENGAPID 1) but the TS→rc gRPC failed `error_code=14 (UNAVAILABLE) "Socket closed"/"Connect Failed"` — the rc xApp was mid-restart (9 restarts/18d; it became RMR-ready seconds later). Re-inject once rc Ready → full success. The run script now `wait_rc`s for rc Ready + settle before injecting.

**3. The LTE master RRC serializes EN-DC handovers — concurrent controls collide.**
Firing both predictions ~immediately put imsi 2's control 116 ms (sim-time) after imsi 1's, while imsi 1's HO was still in flight → `PerformHandover: ... ## Warn: handover not triggered because the UE is already performing HO!`. EN-DC handover is master-coordinated and one-at-a-time. Fix: the script injects **sequentially, gating each handover's landing** (`ho_count` poll), re-firing a UE whose control raced an in-flight HO. Also discovered: **a UE must be targeted to a cell it is not already on** — imsi 2→5 was a silent no-op because imsi 2 is already on cell 5.

## Technical details

- **Injector image** (`phase6b-injector.Dockerfile`): `python:3.11-slim` + **librmr vendored from the running TS pod** (exact rmr 4.8.1, no packagecloud) + `ricxappframe==3.2.2` (matches `xApps/qp/setup.py`). Needs `gcc`/`libc6-dev` for hiredis (ricsdl dep) — same reason the qp image installs gcc. `docker build` → `docker save` → `sudo ctr -n k8s.io image import` (the testbed's image-into-containerd path).
- **Injector** (`phase6b-mock-qp-inject.py`): writes its own seed RT (`30002 → service-ricxapp-trafficxapp-rmr.ricxapp:4560`) and sets `RMR_SEED_RT` before importing `ricxappframe.rmr` (unregistered sender; rtmgr won't distribute a 30002 route). Pod is a long-lived sleeper; the script is `kubectl cp`'d in (iterate without rebuild).
- **TS prediction mechanics confirmed live**: serving cell = first JSON key; target = highest-downlink key; gate `highest > serving + thresh` with A1 `downlink_threshold` **default 0** ⇒ `serving [1,1] / target [9000,9000]` fires with **no A1 policy push**; then `cell_map.find(target)` → emit on hit, silent `return` on miss.
- **imsi→serving-cell map (NoAuto, 12 UEs = 3×4 mmWave gNBs)**: cell 2 = {1,7,9}, cell 3 = {12}, cell 4 = {5,11}, cell 5 = {2,4,6,8,10}; cell 1 = LTE eNB (never a target).
- **D1 gate is operational, not a log read**: `cell_map[...]=nodeb` has no logging, so the gate is "first injection routes (no `Cannot find RAN name`)".
- **Provenance**: a TS-emitted and a grpcurl-emitted control are byte-identical on the wire. Proof of TS origin = the TS pod-log emit line timestamp-correlated to the wire Control Request **plus no grpcurl in the loop** — documented in the assertion.
- **Evidence (oran-kvm-2)**: `captures/phase6b-closedloop-1782599483.{pcapng, ns3-…log, ts-…log}`. M-RC4 assertion: pcap control-req/ack x2, ns-3 distinct handovers x2 / IMSIs x2 / ACKs x2, TS emits x3, 0 drops → exit 0.

## Code review

`code-reviewer` verdict DONE_WITH_CONCERNS: 1 Medium (`REBUILD_INJECTOR=1` dropped the docker image but not the containerd `k8s.io` image → stale-image reuse; fixed by also `ctr images rm`) + cheap Lows (seed-RT temp-file leak, empty-list exit 0, retry-message-on-final-attempt, `restart_ts` terminating-pod race, `e2mgr_pod` multi-match) — all applied. `assert-pcap.sh` change confirmed additive-only; M1–M5 intact. The VM tshark *does* have the E2AP dissector (the assertion printed exact counts), so the control-req/ack count path — not just the byte-sig fallback — passed.

## Open / next

- **Stage E (real QP)** still deferred: the real predictor reads InfluxDB CellReports whose cell-id format may not equal the 10-char `cell_map` key (open-Q8). The mock sidesteps this by crafting keys.
- A D0 rebuild remains a clean follow-up if source⇄deploy parity is ever wanted (then flip `PREDICTIONS_JSON` to lowercase).
- The rc xApp's restart churn is environmental; `wait_rc` mitigates for the demo but the pod's 9-restarts/18d instability is worth a separate look if it widens.
