# Hand-off Report — ns-O-RAN → L-release migration (Phases 0 & 1 done)

**Date:** 2026-06-06 · **Plan:** `plans/260606-0505-port-ns-o-ran-to-l-release/` · **Superproject branch:** `dev/migrate-to-l-release`
**Running notes (read this):** `plans/260606-0505-port-ns-o-ran-to-l-release/implementation-notes.html`
**Next action:** start **Phase 2** (standalone L-release e2sim, M1–M5).

---

## Status

| Phase | Status | Milestone evidence |
|---|---|---|
| 0 Freeze Bronze baseline | ✅ DONE | Full pub-sub golden pcap (5 E2setup + 5 sub req/resp + ~787 indications) |
| 1 Confirm L-release E2Term | ✅ DONE (setup golden; indication deferred) | M2+M3 live (e2mgr CONNECTED via NodePort 32222) |
| 2–7 | ⏳ pending | — |

Tasks #1, #2 completed in Claude Task list; #3–#8 pending.

---

## Environment (verified live, both VMs healthy)

- **`oran-kvm`** = Bronze RIC (Docker). All 5 containers up; SCTP `10.0.2.1:36422`; e2term `10.0.2.10`. scenario-zero pre-built (`ns3-mmwave-oran`). Regression reference only.
- **`oran-kvm-2`** (SSH alias; real hostname `oran-kvm-3` — **same VM**, rename pending) = OSC **L-release** RIC.
  - ns `ricplt` (139d uptime); e2term pod `10.244.0.48`; **image `ric-plt-e2:6.0.6`** (NOT 3.0.1 as recon said).
  - E2Term SCTP svc NodePort **`32222`** → targetPort 36422; **node IP `192.168.122.78`** (iface `enp2s0`); pod bridge `cni0`; kube-proxy **IPVS**.
  - Testbed at `~/O-RAN-Testbed-Automation`; **OSC `e2-interface` already built** (`.../e2-interface/e2sim/build/libe2sim*`); runnable sim image **`oransim:0.0.999`**.

SSH works passwordless to both; `sudo` passwordless on oran-kvm (tcpdump OK).

---

## Phase 0 artifacts (`plans/.../baseline/`)

- `bronze-e2.pcap` — **full pub-sub** (~1.4 MB, 1470 SCTP DATA): 5 E2setupRequest, 5 RICsubscriptionRequest→Response, ~787 RICindication. Captured on bridge **`brric`** (`host 10.0.2.10`).
- `bronze-e2term.log`, `bronze-e2setup-decoded.txt` — Bronze RAN-function bytes: funcID **200 (KPM)** + **300 (RC)**, dummy `OID123`, `ranFunctionRevision 2`. **Exact v01.00/v2 format Phases 3–6 replace.**
- `commit-manifest.txt` + git tag **`baseline-bronze-260606`** (superproject HEAD `885a088`).
- Submodule pins: oran-e2sim `2209995` (v1.0), oran-interface `5f547ae`, ns3-mmwave-oran `4e5073c3`, colosseum `e3161c1`.
- `dev/l-release` branches created (local, at pins) on: oran-e2sim, oran-interface, ns3-mmwave-oran.

**Bronze full pub-sub recipe** (KPM indications need a subscriber): start scenario-zero → wait ~50s for gNB E2 registration → start sample xApp: `colosseum-near-rt-ric/setup-scripts/start-xapp-ns-o-ran.sh` (container `sample-xapp-24`, GNB_ID=ns-o-ran) then inside `/home/sample-xapp/run_xapp.sh`. scenario-zero wall-clock ≈ 375s for simTime=10. (First attempt was setup-only — no xApp running.)

---

## Phase 1 artifacts (`plans/.../baseline/`)

- `golden-lrelease-e2.pcap` — L-release E2 Setup handshake (10 SCTP pkts; 2 DATA = E2setupRequest + **E2setupResponse**). Has `E2nodeComponentConfigAddition-List` (v3.01 IE, absent in Bronze).
- `golden-lrelease-e2setup.xml` — full decoded sim PDU.
- `lrelease-facts.md` — **pinned RIC facts + reproducible capture how-to** (read this for Phase 2).
- Verified: bundled `kpm_sim` (func **2**, OID123) → NodePort `192.168.122.78:32222` → `Connection established`; e2mgr `/v1/nodeb/states` → `connectionStatus: CONNECTED` ⇒ **M2 (E2 Setup) + M3 (RAN function accepted) demonstrated**.

---

## Decisions / findings that reshape the plan

1. **oran-interface needs no separate l-release port.** Our pin `5f547ae` == upstream/master == upstream/m-release; upstream/**l-release** differs by **only README.md**. Decision (user): base Phase 3–6 adapter on **upstream/l-release**. Its `model/` is already v3-shaped (S-NSSAI, `htobe64` 8-byte TimeStamp) but still emits dummy `OID123` + `ric_ReportStyle_Type`. ⇒ Real work = **relink onto the new e2sim + finish v3 field renames**, not a from-scratch rewrite.
2. **Phase 2 base is pre-built.** The testbed's `e2-interface` (= OSC `da6f82f2` equivalent) is already compiled on oran-kvm-2 with a working `kpm_sim`. Vendor that proven tree into the `oran-e2sim` fork on `dev/l-release` (wholesale, per plan option a).
3. **e2term 6.0.6 accepts dummy `OID123`** at E2 Setup ⇒ OID is a *subscription* concern (Phase 5), NOT a setup-acceptance blocker. Revises the Phase-4 assumption that OID123 "will be rejected."
4. **RAN-func-ID ambiguity:** bundled sim registers func **2**; testbed `ric-scp-kpimon` subscribes with func **0** (`control/control.go:90`). Working assumption: ns-3 advertises **2**; confirm empirically in Phase 5.
5. **No xApp deployed on L-release** (`ricxapp` ns empty) ⇒ L-release indication golden (M4/M5) deferred until scp-kpimon/kpimon-go onboarded (or standalone sim-driven in Phase 2).

---

## Capture gotchas (reusable)

- Bronze E2 SCTP rides Docker bridge **`brric`** (10.0.2.1↔10.0.2.10), NOT `-i any` (`sctp` BPF on `any` caught 0 pkts).
- L-release E2 SCTP to e2term pod rides **`cni0`** (pod 10.244.0.48); capture `-i cni0 'sctp'`.
- tcpdump errors `Permission denied` if reusing a savefile owned by dropped-priv `tcpdump` user → write a fresh path each run.
- tcpdump `timeout` must exceed sim wall-clock (~375s for simTime=10).
- `./ns3 run scratch/scenario-zero.cc -- --args` — do NOT wrap target+args in one quoted string (the `--` leaks to the binary).

---

## Next session — start here (Phase 2)

Goal: rebased `oran-e2sim` builds on oran-kvm-2; standalone KPM sim passes **M1 SCTP / M2 E2 Setup / M3 RAN func / M4 subscription / M5 dummy KPM** against live E2Term; build versioned harness `scripts/l-release-validation/` (manifest pins e2sim commit / asn1c version / e2term image `6.0.6`).

1. Read `implementation-notes.html` + `baseline/lrelease-facts.md`.
2. Install build deps on oran-kvm-2 if missing (repo virtiofs-mounted there): `build-essential g++ cmake libsctp-dev autoconf automake libtool bison flex libboost-all-dev python3`.
3. On `oran-e2sim` fork `dev/l-release`: add `e2-interface` remote; vendor the testbed's `da6f82f2` tree wholesale (proven-built). Keep `build_e2sim.sh` recipe.
4. Build `libe2sim` + headers on oran-kvm-2; build bundled KPM example; run vs node-IP `192.168.122.78:32222`.
5. Author `scripts/l-release-validation/` (m1…m5 + assert-pcap via tshark on E2AP proc codes / E2SM v3 OID) + `manifest.txt`.
6. For M4/M5: decide indication-golden source (onboard scp-kpimon vs standalone sim self-trigger).

---

## Unresolved questions

- Q3 (Phase 5): does the real subscription target RAN-func **2** or **0**? Confirm empirically.
- Q4: L-release indication golden — onboard scp-kpimon/kpimon-go, or drive standalone from the sim in Phase 2?
- Q (Phase 2): is asn1c installed on oran-kvm-2 and at what version? (Needed if regenerating; pin in manifest. Note: prefer not to regenerate — testbed e2-interface already ships generated v3 C.)
