# Phase 1 — Confirm L-release E2Term behavior (golden pcap)

## Context Links
- Overview: [plan.md](plan.md)
- Target e2sim: `O-RAN-Testbed-Automation/RAN_Intelligent_Controllers/Near-Real-Time-RIC/e2-interface/e2sim`
- Reference launcher: `…/Near-Real-Time-RIC/install_scripts/run_e2sim_and_connect_to_ric.sh`
- E2Term svc: `…/ric-dep/helm/e2term/templates/service-sctp.yaml` (NodePort 32222, targetPort 36422)
- kpimon-go: `~/Documents/UCLAB/projects/O-RAN-DW/OSC-repos/ric-app-kpimon-go`

## Overview
- **Priority:** P0. **Status:** planned.
- Establish the **known-good L-release wire format** by running the testbed's own bundled KPM simulator against the live E2Term, and pin the connection facts. This is THE reference for Phases 3–6.

## Key Insights
- The bundled `e2-interface` KPM sim is already L-release-compatible → it produces exactly the E2AP v3.01 / E2SM-KPM v3.00 PDUs the E2Term accepts.
- E2Term reachable from the node itself via NodePort 32222 (co-located ns-3 will use the same path).
- kpimon-go's subscribed RAN-function-ID/OID dictates the ID ns-3 must advertise (Phase 4).

## Requirements
- Capture live RIC facts; produce `golden-lrelease-e2.pcap`; document the exact connect params + kpimon func-ID/OID.

## Related Code Files
- Read only: testbed e2sim KPM example (`…/e2sm_examples/kpm_e2sm/src/kpm/kpm_callbacks.cpp` — func ID), kpimon-go E2SM config/asn.
- Create: `plans/.../baseline/golden-lrelease-e2.pcap`, `baseline/lrelease-facts.md`.

## Implementation Steps
1. SSH `oran-kvm-2`. Capture: `kubectl -n ricplt get svc | grep e2term` (NodePort), node IP (`kubectl get nodes -o wide` / `hostname -I`), `kubectl -n ricplt get pods`, e2term image (`kubectl -n ricplt get deploy -o yaml | grep image:`).
2. Read kpimon-go for the RAN-function-ID/OID it subscribes to (E2SM-KPM v3 OID + function ID); record in `lrelease-facts.md`. Decide whether to add kpimon-go as a submodule (default: no, just reference).
3. Start pcap on node: `tcpdump -i any -w golden-lrelease-e2.pcap 'sctp'`.
4. Build + run the bundled KPM sim (per `run_e2sim_and_connect_to_ric.sh`): point it at node-IP:32222. Confirm e2mgr/e2term register the E2 node: `kubectl -n ricplt logs <e2term-pod> | grep -i setup`.
5. Trigger a KPM subscription (kpimon-go xApp or the sim's built-in) and capture ≥1 indication. Stop pcap.
6. In pcap confirm: E2setupRequest→Response (E2AP v3.01), RANfunction accepted, RICsubscriptionRequest→Response, RICindication (E2SM-KPM v3.00 OID, 8-byte TimeStamp). Annotate procedure codes/OIDs in `lrelease-facts.md`.

## Todo List
- [ ] E2Term NodePort + node IP + namespace + image tag recorded
- [ ] kpimon-go RAN-func-ID/OID recorded
- [ ] bundled KPM sim registers with live E2Term
- [ ] `golden-lrelease-e2.pcap` with full setup→subscription→indication
- [ ] `lrelease-facts.md` written; notes file updated

## Success Criteria
Bundled L-release sim completes E2 Setup + KPM subscription + indication against the live RIC; golden pcap + facts pinned.

## Risk Assessment
- E2Term unhealthy / NodePort unreachable from node → check `kubectl -n ricplt get pods`, firewall, `is_running.sh`. Resolve before Phase 2.
- kpimon-go func-ID ambiguous → derive from its E2SM ASN/config; record assumption in notes for user confirm.

## Security Considerations
- Read-only k8s inspection. No secrets in pcaps.

## Next Steps
→ Phase 2: stand up our rebased e2sim (OSC `e2-interface` base) and pass M1–M5 against this same RIC.
