# Phase 0 — Freeze working Bronze baseline (regression anchor)

## Context Links
- Overview: [plan.md](plan.md)
- Bronze run flow: `README.md` (Quick start), `colosseum-near-rt-ric/setup-scripts/setup-lib.sh`
- Build: `ns3-mmwave-oran/e2term-ns3-build.sh`, `oran-e2sim/e2sim/build_e2sim.sh`

## Overview
- **Priority:** P0 (must precede any change). **Status:** planned.
- Capture a known-good Bronze E2 exchange as the regression reference, and pin current commits, before any migration edit.

## Key Insights
- ns-3 is the **E2 node (initiator)**: SCTP client → e2term, sends E2SetupRequest, then KPM indications.
- Bronze e2term at `10.0.2.10:36422` (Docker `ric` network). `oran-kvm` holds this working setup.
- Golden Bronze pcap = the semantic baseline to compare L-release behavior against (procedure flow, KPM cadence).

## Requirements
- Functional: reproduce a working Bronze scenario-zero run on `oran-kvm`; capture E2AP/E2SM pcap + e2term logs.
- Non-functional: zero changes to Bronze submodule commits; everything tagged for exact reproducibility.

## Related Code Files
- Read only: `ns3-mmwave-oran/scratch/scenario-zero.cc`, `.gitmodules`, `README.md`.
- Create: `plans/260606-0505-port-ns-o-ran-to-l-release/baseline/` (pcap, logs, commit manifest), `implementation-notes.html`.

## Implementation Steps
1. SSH `oran-kvm`; confirm Bronze RIC up: `docker ps` (db, e2mgr, e2rtmansim, e2term), `ping 10.0.2.10`, `ss -lnp | grep 36422`.
2. Record submodule commits + superproject HEAD into `baseline/commit-manifest.txt` (`git submodule status`, `git rev-parse HEAD`). Tag superproject `baseline-bronze-260606`.
3. On `oran-kvm`, start pcap on the e2term-facing iface: `tcpdump -i any -w baseline/bronze-e2.pcap 'sctp or port 36422'`.
4. Run: `cd ns3-mmwave-oran && ./ns3 run scratch/scenario-zero.cc -- --e2TermIp=10.0.2.10 --enableE2FileLogging=false --simTime=10`.
5. Save e2term logs (`docker logs e2term`) → `baseline/bronze-e2term.log`. Stop pcap.
6. Sanity: in `baseline/`, confirm pcap shows E2setupRequest→Response + ≥1 RICindication (KPM). Note procedure codes + E2SM-KPM v2 OID for later diff.
7. Create branches `dev/l-release` on each fork to be touched (`oran-e2sim`, `oran-interface`, `ns3-mmwave-oran`) — `git checkout -b dev/l-release` (do NOT commit to cloned branches). Superproject stays on `dev/migrate-to-l-release`.
8. Start `implementation-notes.html` with the baseline facts + decisions locked in plan.md.

## Todo List
- [ ] Bronze RIC health confirmed on `oran-kvm`
- [ ] commit-manifest + `baseline-bronze-260606` tag
- [ ] `bronze-e2.pcap` captured (E2 Setup + KPM indication)
- [ ] `bronze-e2term.log` saved
- [ ] `dev/l-release` branches created on the 3 forks
- [ ] `implementation-notes.html` initialized

## Success Criteria
Golden Bronze pcap shows full E2 Setup + KPM indication flow; commits pinned/tagged; branches ready; notes file live.

## Risk Assessment
- Bronze RIC not running on `oran-kvm` → restart per README §2 before capture. (Mitigation: don't proceed without a clean golden pcap.)

## Security Considerations
- None (lab, read-only capture). Do not commit pcaps with any real credentials (none expected).

## Next Steps
→ Phase 1: capture the equivalent **golden L-release** pcap on `oran-kvm-2`.
