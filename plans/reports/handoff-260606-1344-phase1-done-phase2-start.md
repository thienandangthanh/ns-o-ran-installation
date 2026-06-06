# Handoff — Phase 1 closed (L-release E2 Setup golden, tshark-verified) → Phase 2 start

**Date:** 2026-06-06 · **Branch:** `dev/migrate-to-l-release` · **Plan:** `plans/260606-0505-port-ns-o-ran-to-l-release/`
**Scope this session:** verify + close Phase 1 only (per user). No code changed; verification + doc sync.

## What this session did
- Re-decoded the Phase-1 golden pcap **locally with tshark 4.6.5** (independent of the live VM) and confirmed every pinned fact on the wire.
- Stamped verification into `baseline/lrelease-facts.md` (new tshark table), `implementation-notes.html` (Phase-1 card + log), `phase-01-*.md` todo, `plan.md` status (Phase 1 → ✅ DONE).

## Phase 1 result (trusted reference for Phases 3–4)
Golden: `baseline/golden-lrelease-e2.pcap` (10 SCTP pkts; 2 DATA = E2 Setup req+resp). Full decode `baseline/golden-lrelease-e2setup.xml`.

tshark-confirmed PDUs:
| PDU | Key contents |
|---|---|
| **E2setupRequest** (initiatingMessage/id-E2setup=1) | TransactionID 1; GlobalE2node-ID **gNB** `b5c67788` (29-bit); RANfunction-Item **funcID 2 / rev 2 / OID `OID123`**; **E2nodeComponentConfigAddition-List** (interfaceType `ng`) |
| **E2setupResponse** (successfulOutcome/id-E2setup=1) | TransactionID 1; **RANfunctionsAccepted → funcID 2 / rev 2**; E2nodeComponentConfigAdditionAck |

⇒ E2AP **v3.01** wire confirmed: func 2 accepted, OID123 accepted *at setup*, `E2nodeComponentConfigAddition` IE present (absent in Bronze v01.00).

### tshark gotcha (carry to Phase 2 harness)
E2AP rides SCTP **PPID 70**. The IP-fragmented E2setupRequest reads PPID **0** on reassembly → tshark mis-dissects it as X2AP `HandoverCancel[Malformed]`. Force correct decode:
```
tshark -r <pcap> -o ip.defragment:TRUE --disable-protocol x2ap \
  -d 'sctp.ppi==0,e2ap' -d 'sctp.ppi==70,e2ap' -Y e2ap -V
```
Bake these `-d`/`--disable-protocol x2ap` flags into `scripts/l-release-validation/assert-pcap.sh`.

## Pinned RIC facts (from `baseline/lrelease-facts.md`)
- VM `oran-kvm-2` (== `oran-kvm-3`, same host). Repo **already virtiofs-mounted** there.
- E2Term image **`ric-plt-e2:6.0.6`** (not 3.0.1). ns `ricplt`.
- **E2 endpoint for ns-3/e2sim: `192.168.122.78:32222`** (NodePort SCTP → targetPort 36422). NodePort path validated reachable from the node.
- E2 SCTP to e2term pod rides **`cni0`** (pod `10.244.0.48`): `sudo tcpdump -i cni0 -s0 -U -w out.pcap sctp`.
- Bundled KPM sim: Docker `oransim:0.0.999`, `kpm_sim <ip> <port>`, `RAN_FUNC_ID=2`. libe2sim prebuilt at testbed `e2-interface/e2sim/build/`.
- Verify connect: e2mgr `/v1/nodeb/states` → `connectionStatus: CONNECTED`.

## Next: Phase 2 — standalone rebased e2sim (M1–M5, no ns-3)
File: `plans/260606-0505-port-ns-o-ran-to-l-release/phase-02-standalone-e2sim-test.md`. Start checklist:
1. SSH `oran-kvm-2`; install build deps (`build-essential g++ cmake libsctp-dev autoconf automake libtool bison flex libboost-all-dev python3`).
2. `oran-e2sim` fork (branch `dev/l-release`): add `e2-interface` remote, integrate OSC `da6f82f2`. **Decision needed in notes:** (a) vendor wholesale vs (b) merge/rebase — default (a) if histories diverge. (ns-3 wineslab extensions re-applied later as adapter in P4/P6, not needed for standalone.)
3. Build `libe2sim` + bundled `e2sm_examples/kpm_e2sm`; run against `192.168.122.78:32222`.
4. Author `scripts/l-release-validation/` (`m1-sctp.sh`…`m5-dummy-kpm.sh`, `assert-pcap.sh` w/ the tshark flags above, `manifest.txt` pinning e2sim commit + `asn1c` version + e2term tag `6.0.6`).
5. Run M1–M5; diff vs `golden-lrelease-e2.pcap`.

M-targets: M1 SCTP INIT/INIT-ACK · M2 E2setupResponse · M3 RANfunction accepted (no reject) · M4 RICsubscriptionResponse · M5 RICindication (E2SM-KPM v3 OID). M4/M5 also clears Phase-1's deferred indication golden via the sim's built-in subscription.

## Open questions (carried)
- **Q3 (Phase 5):** ns-3 advertises func **2** (mirror sim) vs scp-kpimon subscribing func **0** — resolve empirically when a real subscription runs.
- **Q4 (Phase 2):** capture indication golden standalone via sim in Phase 2 (preferred) vs onboarding scp-kpimon/kpimon-go in Phase 5.
- Minor: harness must pin `asn1c` version — capture the exact version on `oran-kvm-2` during Phase 2 step 1.

## Git status note
Working tree has uncommitted plan/doc edits (this session) + pre-existing `ns-o-ran-gym` submodule mod and untracked dirs. Not committed — user to commit when ready.
