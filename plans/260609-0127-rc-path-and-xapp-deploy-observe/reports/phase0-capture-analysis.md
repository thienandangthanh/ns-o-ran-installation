# Phase 0 — Deploy & Observe — Capture Analysis (M0)

**Date:** 2026-06-09 · **Plan:** `260609-0127-rc-path-and-xapp-deploy-observe`
**VM:** ssh `oran-kvm-2` → host **`oran-kvm-3`** @ 192.168.122.78 (single-node k8s, L-release RIC)
**Status:** **M0 GREEN** — KPM live path reproduced; ≥1 RC Control Request triggered + captured + on-wire; SDR-free confirmed.

> Snapshot was reverted to *before* the ns-O-RAN L-release migration **runtime deploy**. The migration **code** is intact on the VM (ns3 `dev/migrate-to-l-release@6349d92`, oran-interface `dev/l-release`, e2sim L-libs installed); only kpimon-go/InfluxDB deploy + live run were absent. Both redeployed here.

## M0 exit checklist
| Exit criterion | Result |
|---|---|
| kpimon-go + rc Running | ✅ `ricxapp-kpimon-go`, `ricxapp-rc` both Running |
| ns-3 gNB registered (e2mgr) | ✅ `gnb_734_373_16b8cef1` CONNECTED |
| KPM live path GREEN | ✅ subscription → indication → decode → InfluxDB |
| ≥1 RC Control Request captured + decoded | ✅ 3× triggered; rc XER-decoded; ns-3 received 87 B ×3 on wire |
| SDR-free confirmed | ✅ entire RAN simulated in ns-3 (no USRP/UHD/srsRAN) |
| Analysis report | ✅ this file |

## Golden captures (on VM `/home/uc/captures/`, chmod 644)
| pcap | pkts | content |
|---|---|---|
| `phase0-kpm-1780975477-podip-full.pcapng` | 2,034 | KPM full: SCTP INIT, E2 Setup, RIC Subscription, RIC Indication(KPM) ×N |
| `phase0-rc-1780984484.pcapng` | 1,456 | RC: E2 Setup + 3× RIC Control Request (funcId 300) |
| `phase0-kpm-1780974558-nodeport-attempt.pcapng` | ~33 KB | NodePort SCTP reset evidence (see §NodePort) |

## On-wire facts (decoded)
E2AP rides **SCTP PPID 70** (confirmed via `tshark -V`). tshark 3.2.3 on VM has **no E2AP/E2SM dissector** (added upstream 3.5+) → semantic decode taken from xApp/ns-3 asn1c logs + `strings` on PDUs; byte-level decode deferred to Phase 1 (offline asn1c).

| Flow | funcId | E2SM name (on wire) | OID | Format / version | Notes |
|---|---|---|---|---|---|
| E2 Setup RANfunction | **2** | `ORAN-E2SM-KPM` (`strings` ×10) | **`OID123`** (dummy, ×22) | KPM v03.00 (ns-3 e2sim) | dummy OID accepted by e2term 6.x |
| E2 Setup RANfunction | **300** | (empty desc) | dummy/empty | — | control function placeholder, pre-registered by ns-3 |
| RIC Indication (KPM) | 2 | E2SM-KPM | — | **IndicationMessage Format1**, 5 cell metrics | kpimon-go (v2.0 decoder) parses ns-3 v3.00 bytes OK |
| RIC Control Request | **300** | E2SM-RC | — | **ControlMessage Format1** (rc XER) | rc encoded; ns-3 RX 87 B ×3; no ACK (no handler yet) |

### KPM decode (kpimon-go logs)
`Successfully subscription done (gnb_734_373_16b8cef1)`, RANFunctionID 2 → `RIC_INDICATION subId=2 len=290/291` → `Indication Header format = 1` → `No of cell metrics = 5` → `Wrote Cell Metrics to InfluxDB`.
InfluxDB `cellMetrics` fields: `DRB.MeanActiveUeDl, RRU.PrbUsedDl, TB.TotNbrDlInitial.{16Qam,64Qam,Qpsk}`.

### RC control decode (rc pod logs, asn1c XER)
rc emitted `<E2SM-RC-ControlMessage>` → `ric-controlMessage-formats` → `controlMessage-Format1`, wrapped in E2AP `<RICcontrolRequest>` with `<RANfunctionID>300</RANfunctionID>`. gRPC returned `{"description":"Success Response"}` ×3. ns-3 e2sim logged `Received new data of size 87` ×3 (delta exactly = 3 sends) → the Control Requests reached the gNB SCTP socket. ns-3 did **not** ACK (e2sim has RIC Control ASN.1 *types* but no handler logic — Phase 4/5).

## §3 question (v3↔v2 KPM): reproduced, not yet root-caused
ns-3 sends **E2SM-KPM v03.00**; deployed kpimon-go decodes with **v2.0** asn — and it **works** (5 cell metrics, Format1). Confirms the "lucky decode" is real and repeatable. Bytes are in the 2,034-pkt KPM pcap for Phase-1 H1–H4 analysis (Format1 byte-compat / OCTET-STRING leniency / forgiving parse / deployed-build-≠-on-disk).

## RC version (2.0 vs nov2021): on-wire inconclusive by OID
ns-3 advertises funcId 300 with dummy/empty OID, so the wire does not disambiguate. rc encoded with its **compiled** asn (repo ships `e2sm-rc-2.0.asn` + `e2sm-rc-nov2021.asn` + `e2sm-common.asn`). Both expose `ControlMessage-Format1` with the same outer shape. **Confirm exact version in Phase 3** via the rc image's compiled wrapper / byte-level decode. Plan decision (RC-2.0 from rc clone) stands.

## Connect target: NodePort vs pod-IP (Phase-2 input — IMPORTANT)
- **NodePort `192.168.122.78:32222` is NOT viable for sustained E2 with stock kube-proxy SCTP.** Handshake succeeds (E2 Setup Response received) then `Connection reset by peer` → ns-3 SIGSEGV. kube-proxy DNATs the INIT but the e2term pod return path bypasses the NodePort VIP → association mismatch. Multiple parallel gNBs compound it. (evidence: `*-nodeport-attempt.pcapng`)
- **pod-IP `10.244.0.13:36422` is the only sustained path today** (validated, stable, no reset).
- **No source edit needed for either:** `--e2TermIp=<ip>` (GlobalValue) + `--ns3::MmWaveHelper::E2Port=<port>` (attribute; note attr name is `E2Port`, not `E2TermPort`). The `mmwave-helper.cc:300` "hardcode" is only a default.
- ⇒ Phase-2 "durable NodePort connect" debt **cannot** be closed by NodePort as-is. Real options: stable e2term ClusterIP, MetalLB/LoadBalancer, hostNetwork e2term, or scripted pod-IP discovery. **Recommend: scripted pod-IP discovery** (cheapest, robust) until a LoadBalancer is justified.

## SDR-free: CONFIRMED
The entire RAN (gNB + UE + channel + E2 node) is the **ns-3 scenario-zero** process. No USRP/UHD/srsRAN/srsUE/ZMQ/Open5GS in the loop (testbed `run.sh` RF stack deliberately unused — see `docs/run-testbed-with-ns-o-ran.md`). xApps + InfluxDB are pure software pods. Pure-synthetic, no radio hardware.

## Reproducible procedure (validated this session)
```
# 1. deploy (idempotent): kpimon-go+InfluxDB, then rc
sudo ./additional_scripts/install_xapp_kpi_monitor.sh
sudo ./additional_scripts/install_xapp_ric_control.sh
# 2. clean + clear stale RNIB (ALWAYS pkill -9: -INT leaves the ns-3 binary holding SCTP port 38471)
sudo pkill -9 -f scenario-zero
kubectl exec -n ricplt <e2mgr> -- curl -s -X PUT http://localhost:3800/v1/nodeb/shutdown
# 3. capture + run (pod-IP; simTime<=100)
sudo tshark -i any -f 'sctp' -w cap.pcapng &
./ns3 run "scratch/scenario-zero --e2TermIp=10.244.0.13 --simTime=100 --reducedPmValues=1 --e2du=1 --e2cuUp=0 --e2cuCp=0 --enableE2FileLogging=false"
# 4. after gNB CONNECTED: restart kpimon to force subscribe
kubectl rollout restart deploy/ricxapp-kpimon-go -n ricxapp
# 5. RC control: grpcurl -> rc:7777 (payload /tmp/rc-control.json; funcId 300, ControlStyle 3, NR cell)
grpcurl -plaintext -d @ 10.101.81.179:7777 rc.MsgComm.SendRICControlReqServiceGrpc < /tmp/rc-control.json
```

## rc gRPC contract (Phase 4/5 reference)
`rc.MsgComm.SendRICControlReqServiceGrpc(rc.RicControlGrpcReq)` on **:7777**. Key nesting: `RICControlHeaderData.UEID = {GnbUEID:{amfUENGAPID, guami{pLMNIdentity,aMFRegionID,aMFSetID,aMFPointer}, gNBCUUEF1APID[], gNBCUCPUEE1APID[]}}`; `RICControlMessageData.RICControlCellTypeVal` enum (NR=1, EUTRAN=2; the unitTest's `4` is invalid); `RICControlAckReqVal` enum (NO_ACK=1, ACK=2). rc is a **gRPC-driven forwarder** (does NOT self-emit) — answers open Q2.

## Open questions / Phase-1 inputs
1. **§3 root cause** (how v2 decoder parses v3 bytes) — extract Format1 bytes from KPM pcap; run H1–H4. *(Phase 1)*
2. **RC exact version** (2.0 vs nov2021) on wire — needs byte-level decode / rc image asn introspection. *(Phase 3)*
3. **tshark E2SM dissection** — 3.2.3 lacks it; offline asn1c decoder or tshark≥3.6 needed for byte-level work.
4. **ns-3 SIGSEGV on SCTP reset** (NodePort path) — ns-3 lacks a clean error path on association reset; harden if NodePort/LB ever pursued.
