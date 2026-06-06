# Handoff — Phase 2 (standalone rebased e2sim, M1–M3 green + golden-matched) → Phase 3 start

**Date:** 2026-06-06 · **Branch (super):** `dev/migrate-to-l-release` · **Plan:** `plans/260606-0505-port-ns-o-ran-to-l-release/`
**Scope this session:** Phase 2 only — build rebased OSC L-release e2sim on the VM, validate M1–M5 vs live E2Term, author the versioned harness. No ns-3.

## What this session did
- **Vendored** OSC `e2-interface` `da6f82f2` wholesale into the `oran-e2sim` fork `e2sim/` subtree on branch `dev/l-release` (decision fork resolved → (a) wholesale; see below).
- **Built** `libe2sim` + bundled `kpm_e2sm` (`kpm_sim`) fresh on `oran-kvm-2` from the vendored tree.
- **Ran** the self-built sim against the live L-release E2Term `6.0.6` → **M1/M2/M3 GREEN**, structural diff vs the Phase-1 golden **byte-identical**.
- **Authored** `scripts/l-release-validation/` (M1–M5 + assert + manifest + README), runnable on the VM and locally.
- Found **M4/M5 need an external subscriber** (the sim is reactive-only) → escalated (Q4). Updated notes/plan/phase todos.

## Phase 2 result (trusted reference for Phase 3)
| M | Target | Result |
|---|---|---|
| M1 | SCTP INIT/INIT-ACK | **GREEN** (sim "[SCTP] Connection established") |
| M2 | E2setupResponse | **GREEN** (successfulOutcome/id-E2setup, TransactionID 1) |
| M3 | RANfunctionsAccepted, no reject | **GREEN** (ranFunctionID **2** ×2, OID123, no RANfunctionsRejected) |
| M4 | RICsubscriptionResponse | **BLOCKED** — needs KPM xApp subscriber (Q4) |
| M5 | RICindication (E2SM-KPM v3) | **BLOCKED** — gated on M4 |

**Structural diff vs golden = identical**: E2setupReq+Resp, RANfunctionID 2 (×2), ranFunctionOID `OID123`, `E2nodeComponentConfigAddition`/`Ack` v3.01 IEs present, no `RANfunctionsRejected`. ⇒ the rebased OSC e2sim emits wire-identical E2 Setup to the golden.

**Evidence pcap:** `scripts/l-release-validation/captures/phase2-m1-m3-selfbuilt-setup.pcap`
**Golden ref:** `plans/260606-0505-port-ns-o-ran-to-l-release/baseline/golden-lrelease-e2.pcap`

## The vendoring decision (resolved → wholesale)
Histories are **disjoint** (`da6f82f2` not in our wineslab fork history; different upstreams) and tree layouts differ (OSC ships `asn1c/`, `Dockerfile_kpm`, `files.txt`). Applied the plan/handoff **default (a) wholesale-vendor** — clearly safe, non-destructive: replaced only the `e2sim/` subtree via `git read-tree --prefix=e2sim/ da6f82f2:e2sim`; the wineslab `develop` branch (ns-3 extensions) is preserved for the P4/P6 adapter. **Verified exact:** staged `e2sim` tree SHA `2031409…` == `git rev-parse da6f82f2:e2sim`.

## Manifest pins (`scripts/l-release-validation/manifest.txt`)
- **e2sim:** OSC gerrit `sim/e2-interface.git`, commit **`da6f82f286cdbb38af1178f82f85877b12c2f85b`** (`da6f82f2`); `e2sim` tree `2031409…`. ASN.1 module `e2ap-epd-v03.01.asn` (E2AP **v03.01**).
- **asn1c:** **`0.9.29`** — from the committed generated-file banner. *Build does NOT run asn1c* (OSC ships pre-generated C); never hand-edit, re-vendor to bump.
- **e2term:** `nexus3.o-ran-sc.org:10002/o-ran-sc/ric-plt-e2:`**`6.0.6`**, ns `ricplt`.
- **Endpoint:** `192.168.122.78:32222` (NodePort SCTP → targetPort 36422). Capture iface `cni0`. e2mgr `10.100.86.178:3800`.
- **RAN func:** id **2**, short_name `ORAN-E2SM-KPM`, OID `OID123` (dummy, accepted at setup), rev 2.

## Build recipe (reproducible, oran-kvm-2, g++ 13.1.0)
Pure **CMake** — `libtool` NOT needed; `asn1c` NOT needed.
```
# lib (.deb carries headers):
cd oran-e2sim/e2sim && mkdir build && cd build \
  && cmake .. && make package && cmake .. -DDEV_PKG=1 && make package
sudo dpkg -i e2sim_1.0.0_amd64.deb e2sim-dev_1.0.0_amd64.deb && sudo ldconfig
# kpm app (stage asn1c sibling + nlohmann):
sudo apt-get install -y nlohmann-json3-dev
sudo cp /usr/include/nlohmann/json.hpp /usr/local/include/nlohmann/
#   stage: cp -r e2sm_examples/kpm_e2sm/. <stage>/ ; cp -r asn1c <stage>/asn1c
cd <stage> && mkdir build && cd build && cmake .. && make   # -> src/kpm/kpm_sim (static libe2sim.a)
```
Self-built `kpm_sim` currently lives at `oran-kvm-2:/tmp/kpm-build-stage/build/src/kpm/kpm_sim` (regenerable).

## Harness usage
Run on the VM; set `KPM_SIM` to the built binary:
```
export KPM_SIM=/tmp/kpm-build-stage/build/src/kpm/kpm_sim
cd /home/uc/ns-O-RAN-installation/scripts/l-release-validation && bash run-all.sh
```
M1–M3 → GREEN; M4/M5 → NOT-RUN until a subscriber exists.

## tshark / assert commands (carry forward)
**E2AP rides SCTP PPID 70; the IP-fragmented E2setupRequest reads PPID 0** → force decode (else mis-labeled X2AP `HandoverCancel[Malformed]`):
```
tshark -r <pcap> -o ip.defragment:TRUE --disable-protocol x2ap \
  -d 'sctp.ppi==0,e2ap' -d 'sctp.ppi==70,e2ap' -Y e2ap -V
```
**VM tshark 3.2.3 has NO E2AP dissector** — `assert-pcap.sh` auto-falls back to byte signatures on SCTP DATA payloads: E2setupResponse `20 01`, RICsubResponse `20 08`, RICindication `00 05`, RANfunctionsAccepted IE `00 09`, ASCII `ORAN-E2SM-KPM`/`OID123`. Run asserts on a tshark 4.x host for the richest decode (both give same PASS/FAIL). `capture_exchange` retries ×3 because IPVS-SNAT occasionally drops the setup DATA from `cni0`. e2mgr shows `DISCONNECTED` post-run (sim ABORTs on timeout) — **trust the pcap, not the REST status** for M1–M3.

## Open questions (carried)
- **Q3 (Phase 5):** ns-3 advertises func **2** (mirror sim) vs scp-kpimon subscribing func **0** — resolve empirically when a real subscription runs.
- **Q4 (ESCALATED — needs decision):** M4/M5 require an external `RICsubscriptionRequest`. The bundled sim is reactive-only. **Decide:** onboard `scp-kpimon`/`kpimon-go` (RIC-cluster-modifying; also exercises Q3) to capture the indication golden now, **or** defer M4/M5 to Phase 5 when the xApp is onboarded anyway. Phase 3 (E2 Setup port) does **not** depend on M4/M5, so deferral is safe.

## Git status / what's uncommitted (orchestrator/user to approve)
- **`oran-e2sim` fork, branch `dev/l-release`:** vendored OSC `da6f82f2` content **staged but NOT committed** (`5821 files changed`). Remote `e2interface` (OSC gerrit) added. Suggested commit (when approved): `feat(e2sim): vendor OSC e2-interface da6f82f2 (E2AP v3.01 / E2SM-KPM v3) onto dev/l-release`. After committing the fork, the **superproject submodule pin** must be bumped from `2209995` → new fork commit.
- **Superproject:** `scripts/l-release-validation/` is **untracked** (new harness + evidence pcap). Plus pre-existing untracked dirs and `ns-o-ran-gym` mod from earlier sessions. Suggested commit: `test(l-release): add versioned M1–M5 E2 validation harness + Phase-2 setup evidence`.
- Plan/notes doc edits this session are uncommitted too.
- VM build dirs cleaned; no stray artifacts in the fork tree.

## START CHECKLIST — Phase 3 (Port E2 Setup: A SCTP + B E2AP)
File: `plans/260606-0505-port-ns-o-ran-to-l-release/phase-03-port-e2-setup.md`.
1. **Relink `oran-interface` (ns-3) onto the new e2sim base.** Our `oran-interface` is on `dev/l-release` pinned at upstream `l-release` (Q2-resolved: already v3-shaped — S-NSSAI, htobe64 8-byte TimeStamp — but still emits dummy `OID123` + `ric_ReportStyle_Type`). Point its build at the vendored `oran-e2sim` `da6f82f2` `libe2sim` (headers `/usr/local/include/e2sim`, lib `/usr/local/lib/libe2sim_shared.so` or static `.a`). Reconcile any header/symbol drift from wineslab v1.0 → OSC `da6f82f2`.
2. **Build the ns-3 E2 termination** (`ns3-mmwave-oran` + `oran-interface` adapter) against the new lib on `oran-kvm-2`.
3. **M2 from ns-3:** drive the ns-3-built termination → E2Term `192.168.122.78:32222`; capture on `cni0`; assert with the harness (`m2-e2setup.sh` pattern / `assert-pcap.sh e2setup-response ranfunc-accepted no-ranfunc-reject`). Target: E2setupResponse + RANfunctionsAccepted, golden-matched (decide func id per Q3 — start with **2** to mirror the sim).
4. Keep the public `E2Termination` API stable (adapter layer in `oran-interface/model/`, per locked decision).
5. Append Phase-3 entries to `implementation-notes.html`; tick `phase-03` todos.

**Key pinned facts unchanged from Phase 1/2:** VM `oran-kvm-2` (==`oran-kvm-3`), repo virtiofs-mounted at `/home/uc/ns-O-RAN-installation`; e2term `6.0.6`; NodePort `32222`; capture `cni0`; sudo passwordless on VM.
