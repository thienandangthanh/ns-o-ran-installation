# Phase 7 — Reconnect ns-3 scenario-zero (end-to-end)

## Context Links
- Overview: [plan.md](plan.md); indications from [phase-06](phase-06-port-kpm-indications.md)
- Scenario: `ns3-mmwave-oran/scratch/scenario-zero.cc`; run helper `ns3-mmwave-oran/run-test.sh`
- Golden refs: `plans/.../baseline/golden-lrelease-e2.pcap`, `bronze-e2.pcap`

## Overview
- **Priority:** P0. **Status:** planned.
- Run the **full unmodified scenario-zero** against the L-release RIC and confirm real KPM flows end-to-end, reproducibly. Finalize docs + harness.

## Key Insights
- Scenario logic is unchanged by design; only the E2 endpoint (node-IP:32222) and the underlying E2/KPM stack changed.
- This phase converts the standalone milestones into a real multi-eNB/UE simulation feeding the RIC.

## Requirements
- `scenario-zero` registers via E2 Setup, receives a kpimon-go subscription, and streams decodable E2SM-KPM v3.00 indications during a full sim run; M1–M6 all green.

## Related Code Files
- Run only: `ns3-mmwave-oran/scratch/scenario-zero.cc`.
- Modify: `README.md` + `docs/` (L-release run flow, prerequisites, new IP/port), `docs/` migration writeup; `scripts/l-release-validation/` (full-run assertion).

## Implementation Steps
1. On `oran-kvm-2`: `cd ns3-mmwave-oran && ./ns3 run scratch/scenario-zero.cc -- --e2TermIp=<node-ip> --e2TermPort=32222 --enableE2FileLogging=false --simTime=10`.
2. Capture pcap for the whole run; confirm E2 Setup → subscription → sustained KPM indications to kpimon-go.
3. Run the full harness (M1–M6) against this run; compare to golden L-release pcap; sanity-check metric semantics vs Bronze baseline (cadence, value ranges).
4. Update `README.md` Quick start with the L-release path (replace Bronze §2/§4 steps or add an L-release section): RIC = testbed on `oran-kvm-2`, e2TermIp=node-IP, port 32222, co-located build.
5. Write `docs/` migration summary (version jump, adapter layer, harness usage, how to re-validate future releases). Update submodule pins; commit on `dev/l-release` per fork + superproject.
6. Finalize `implementation-notes.html`: consolidate decisions/deviations/tradeoffs/open-questions for the user.

## Todo List
- [ ] scenario-zero runs against L-release RIC
- [ ] full-run pcap shows sustained KPM indications
- [ ] harness M1–M6 all green
- [ ] `README.md` + `docs/` updated for L-release
- [ ] submodule pins committed on `dev/l-release` (forks + superproject)
- [ ] `implementation-notes.html` finalized

## Success Criteria
Full scenario-zero drives real E2SM-KPM v3.00 data into the L-release RIC end-to-end; M1–M6 reproducibly green; docs + version-pinned harness in place for future-release migrations.

## Risk Assessment
- Stability under load (many UEs) vs single-sim → start small (`run-test.sh` minimal), scale up; watch e2term/kpimon logs.
- Regression vs Bronze semantics → compare KPM cadence/values; document expected differences (v2→v3) in notes.

## Security Considerations
- None new. Keep pcaps lab-internal.

## Next Steps (follow-up, out of scope)
→ Port **E2SM-RC v2.0** for closed-loop control → enable Traffic Steering / Slicing / Prediction xApp framework on L-release.
