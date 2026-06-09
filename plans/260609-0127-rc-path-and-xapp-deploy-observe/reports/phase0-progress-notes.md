# Phase 0 — Deploy & Observe — Running Notes

**Started:** 2026-06-09 ~03:00 KST · **Target:** M0 (golden pcaps + decoded analysis)
**VM:** ssh `oran-kvm-2` → host `oran-kvm-3` @ 192.168.122.78 (single-node k8s, 8 cores)
**Exec mode:** autonomous to M0 · **Connect target:** pod-IP 10.244.0.13:36422 (NodePort tested → non-viable, see below)
**STATUS: M0 GREEN — DONE.** Final report: `phase0-capture-analysis.md`.

## Post-revert state (verified read-only)
- ricplt fully Running (L-release). e2term-alpha pod IP **10.244.0.13**; SCTP NodePort **36422:32222**.
- ricxapp: only `hw-go`. **kpimon-go absent, no InfluxDB** → must deploy (Phase 0 add).
- ns-O-RAN code on VM = migration branches present (ns3 `dev/migrate-to-l-release@6349d92`, oran-interface `dev/l-release`); e2sim L-libs installed (`libasn1c_e2.a`, `libe2sim_shared.so`, headers Jun 6).
- Stale RNIB: `gnb_734_373_16b8cef1` DISCONNECTED (leftover) → clear before run.
- Port override: scenario-zero uses `CommandLine::Parse` → `--ns3::MmWaveHelper::E2TermPort=32222` works, no code edit.

## Step log
- [DONE] ns-3 cached compile (cache hit, fast)
- [DONE] kpimon-go + InfluxDB deployed: `r4-influxdb-influxdb2-0` 1/1, `ricxapp-kpimon-go-...` 1/1 Running
- [DONE] cleared stale RNIB (`gnb_734_...` → SHUT_DOWN via e2mgr /v1/nodeb/shutdown)
- [DONE] tshark SCTP capture started before traffic → `phase0-logs/pcap-path.txt`
- [DONE] ns-3 scenario-zero run @ **NodePort 192.168.122.78:32222** — see KEY FINDING below
- [running] collecting run evidence (e2mgr states, kpimon logs, influx, pcap)
- [todo] deploy rc xApp + trigger/capture Control Request
- [todo] decode + write phase0-capture-analysis.md (M0)

## KEY FINDING — NodePort SCTP WORKS (feeds Phase-2 durability decision)
- ns-3 e2sim: `[SCTP] Connecting to server at 192.168.122.78:32222 ... Connection established`.
- Contradicts old guide (`run-testbed-with-ns-o-ran.md`) claim "connects to POD IP, not NodePort".
- **No source edit needed**: port via attribute `--ns3::MmWaveHelper::E2Port=32222` (attr is `E2Port`, NOT `E2TermPort`); IP via GlobalValue `--e2TermIp=192.168.122.78`.
- ⇒ The durable NodePort connect (Phase-2 debt, plan §Risks/§Phase2) is **achievable today, zero code change** — just pass the two args. Pod-IP hardcode in `mmwave-helper.cc` is only the *default*, fully overridable.
- RAN funcs registered by ns-3: ID **2** = `ORAN-E2SM-KPM`, ID **300** = (empty desc).

## CORRECTION — NodePort SCTP does NOT sustain the association (CRITICAL Phase-2 finding)
- NodePort run: SCTP INIT handshake OK → E2 Setup Request sent → **`SETUP-RESPONSE-SUCCESS` received (69B)** → then `[SCTP] recv: Connection reset by peer` → `Transport endpoint is not connected` → ns-3 **SIGSEGV**.
- Root cause: **kube-proxy SCTP NodePort** DNATs the INIT, but the e2term pod's return/heartbeat path bypasses the NodePort VIP → SCTP association mismatch → RST right after setup. scenario-zero's multiple parallel gNBs (src ports 38471/38472…) compound it. ns-3 lacks a clean error path → segfault.
- Evidence pcap: `/home/uc/captures/phase0-kpm-1780974558-nodeport-attempt.pcapng` (33KB).
- ⇒ **Revised Phase-2 verdict:** NodePort is NOT a drop-in durable connect with stock kube-proxy SCTP. The handshake *looks* fine (misleading). Durable options to evaluate later: stable e2term ClusterIP, MetalLB/LoadBalancer, hostNetwork e2term, or scripted pod-IP discovery. **pod-IP remains the only sustained path today.**
- **pod-IP run (10.244.0.13:36422):** multiple gNBs `SETUP-RESPONSE-SUCCESS` (60B), connection **stable, no reset/segfault**.

## SUBSCRIPTION GOTCHA — kpimon must restart AFTER gNB CONNECTED (from Phase-7 journal)
- 1st pod-IP run: gNB CONNECTED in e2mgr, but kpimon never subscribed (logged `List for connected gNBs: [gnb_734...]` + `ready to send subscription request` at startup only — before the durable gNB existed). submgr silent.
- **Proven procedure (journal 2026-06-07 line 119):** start ns-3 → wait gNB `CONNECTED` → **`kubectl rollout restart deploy/ricxapp-kpimon-go`** → kpimon rescans RNIB → subscribes → indications. Used `simTime=60` for a comfortable restart+subscribe+indication window (sim blocks waiting for subscription, so gNB stays connected).
- Expected GREEN evidence (journal M4–M6): kpimon `Successfully subscription done` (RANFunctionID 2), `RIC Indication message received`, `No of cell metrics = 5`, `Wrote Cell Metrics to InfluxDB`.

## ✅ M0 KPM LIVE PATH — GREEN (pod-IP, clean run @ 03:24)
- Procedure that worked: kill -9 leftovers → clear RNIB → tshark → ns-3 scenario-zero `--e2TermIp=10.244.0.13 --simTime=60 --reducedPmValues=1 --e2du=1 --e2cuUp=0 --e2cuCp=0` → wait CONNECTED (6s) → `kubectl rollout restart deploy/ricxapp-kpimon-go`.
- M4 `Successfully subscription done (gnb_734_373_16b8cef1)`, RANFunctionID 2.
- M5 `RIC_INDICATION subId=2 len=290/291`, `Indication Header format = 1`, ~3s periodicity.
- M6 `No of cell metrics = 5` → `Wrote Cell Metrics to InfluxDB`.
- InfluxDB `cellMetrics`: DRB.MeanActiveUeDl, RRU.PrbUsedDl, TB.TotNbrDlInitial.{16Qam,64Qam,Qpsk}.
- **pcap (golden KPM): `/home/uc/captures/phase0-kpm-1780975477-podip-full.pcapng` — 2,034 pkts.**
- **v3→v2 mismatch DECODED OK again** (sender e2sim v03.00, kpimon-go v2.0) → confirms Phase-1 "lucky decode"; bytes now captured for H1–H4 analysis.
- **CRITICAL ops gotcha:** always `pkill -9` ns-3 binaries between runs — `-INT` only kills the `./ns3` python wrapper, leaving the real binary holding SCTP src port 38471 → next run dies `connect: Cannot assign requested address`.

## tshark E2SM dissection — ANSWERED (Phase 0.2)
- tshark/Wireshark **3.2.3** on VM → **NO E2AP/E2SM dissector** (added upstream in 3.5+). Capture gives raw SCTP only.
- **Decode strategy (offline fallback):**
  1. Capture raw SCTP (`-w` pcapng), filter E2AP by SCTP PPID (E2AP=70/0x46) + stream.
  2. First-pass decode: kpimon-go pod logs (decoded funcId+metrics) + ns-3 E2 logs + manual `strings`/hex on PDU bytes (dummy `OID123` is ASCII-visible in RANfunction descriptor).
  3. Byte-level confirmation (E2SM version/format) IF needed for Phase 1: minimal asn1c decoder linking installed `libe2sim_shared.so`+`libasn1c_e2.a` (E2AP/E2SM decoders already on VM).
  4. Extract PDU bytes from pcap: `tshark -r f.pcapng -Y 'sctp' -T fields -e sctp.ppi -e data`.

## rc control-trigger mechanism — ANSWERED (Phase 0.4, open Q2)
- rc does **NOT self-emit**. It is a **gRPC-driven control forwarder**: gRPC server on **port 7777**, method `rc.MsgComm.SendRICControlReqServiceGrpc`.
- Trigger via `grpcurl -plaintext -d '<json>' <rc-svc-ip>:7777 rc.MsgComm.SendRICControlReqServiceGrpc` (template in `xApps/rc/unitTest/grpcClient.sh`).
- JSON contract: `e2NodeID, plmnID, ranName, RICE2APHeaderData{RanFuncId:300, RICRequestorID}, RICControlHeaderData{ControlStyle:3, ControlActionId:1, UEID}, RICControlMessageData{RICControlCellTypeVal, TargetCellID}, RICControlAckReqVal`.
- **RanFuncId 300** = the control function — **ns-3 already registers funcId 300** (saw `Adding RAN function ID 300` at E2 setup). ControlStyle 3 = connected-mode mobility (handover) → aligns with Phase 5.
- RC-2.0 contract asn on VM: `xApps/rc/e2sm/{e2sm-rc-2.0.asn,e2sm-rc-nov2021.asn,e2sm-common.asn}` (confirms Phase-3 sourcing).
- ns-3 e2sim has RIC Control ASN.1 **types** (`RICcontrolRequest.h`, `RICcontrolAcknowledge.h` in /usr/local/include/e2sim) but **no handler logic** → ns-3 will RECEIVE a Control Request but not decode/ACK (Phase 4-5). Phase-0.4 goal = capture it on wire.

## BLOCKER (needs user decision): no gRPC client on VM
- No `grpcurl`, no host `go`, no python `grpcio`. Downloading grpcurl was auto-denied (external binary on shared VM).
- Options: (a) install grpcurl binary, (b) run grpcurl as k8s pod (`fullstorydev/grpcurl` image), (c) user installs, (d) defer RC capture.

## Phase 0.4 RC capture — in progress
- grpcurl **v1.9.3** on VM (`/usr/bin/grpcurl`, user-installed). rc gRPC svc `service-ricxapp-rc-grpc-server` = **10.101.81.179:7777**; reflection lists `rc.MsgComm.SendRICControlReqServiceGrpc`.
- ns-3 `simTime` bound = `MakeDoubleChecker(0.1, 100.0)` → max **100** (120 rejected). Use ≤100.
- Control payload targets connected gNB: ranName=`gnb_734_373_16b8cef1`, plmn 373437, RanFuncId 300, ControlStyle 3 (handover), ControlActionId 1, TargetCellID 1113, AckReq 1.

## Open questions tracked
- Q: SCTP NodePort forwarding viable host→32222? (decided by capture: INIT vs INIT-ACK)
- Q: KPM v3↔v2 mismatch mechanism (Phase 1, needs captured bytes)
- Q: does rc self-emit Control Request or need gRPC driver? (Phase 0.4)
