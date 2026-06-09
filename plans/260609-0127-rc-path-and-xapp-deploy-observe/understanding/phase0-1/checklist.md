# Understanding Checklist — Phase 0 & 1 (RC path + deploy-observe)

Plan: `260609-0127-rc-path-and-xapp-deploy-observe`
Legend: ⬜ not started · 🔄 in progress · ✅ mastered

---

## Stage 1 — The Problem (what & why it existed)

- ✅ **1.1 The whole system shape.** ns-3 sim (gNB+UE+channel+E2 node, one process) → SCTP/E2AP → e2term → xApps (kpimon-go, rc) → InfluxDB. E2AP = outer envelope (procedures, routes by funcId); E2SM = inner opaque payload (KPM=monitor funcId 2, RC=control funcId 300). RIC forwards E2SM without decoding; only the xApp decodes it. "L-release" pins the *platform* (tolerant E2AP), not the xApp's E2SM version → mismatch lives at the xApp decoder.
- ✅ **1.2 Why observe before changing.** Bottom-up golden-pcap discipline. Phase 1 is IMPOSSIBLE without Phase 0's captured KPM bytes (fed real 194B into v2 decoder) → Phase 0 produces ground truth, Phase 1 consumes it.
- ✅ **1.3 The version mismatch that motivates everything.** Deployed kpimon-go = KPM v2.0; ns-3 emits v03.00; M6 passed → mechanism unknown → Phase 1 settles it on evidence.
- ✅ **1.4 The new capability.** KPM = send-only (monitor, node→xApp). RC = receive+ACK+act (control, xApp→node). RC is the genuinely new arrow.

## Stage 2 — The Solution (what was done & the whys)

### Phase 0 — Deploy & Observe
- ✅ **2.1 KPM live path.** E2 Setup (advertise funcId 2/300) → RIC Subscription (funcId 2) → RIC Indication (Header+Message, every ~3s) → xApp decodes E2SM → InfluxDB. M4/M5/M6 chain.
- ✅ **2.2 Subscription gotcha.** kpimon scans RNIB for connected gNBs at startup ONLY → if no gNB yet, never subscribes → `rollout restart` after CONNECTED forces rescan. simTime≥60 keeps sim alive for the window. (`pkill -9` ops gotcha: -INT leaves binary holding SCTP port.)
- ✅ **2.3 NodePort vs pod-IP.** SCTP is association-oriented; kube-proxy DNATs the INIT but e2term return path bypasses the NodePort VIP → address-set mismatch → RST after Setup → ns-3 SIGSEGV (no clean error path). Successful handshake ≠ durable association. pod-IP = only sustained path; scripted pod-IP discovery recommended.
- ✅ **2.4 Connect is arg-overridable.** `--e2TermIp` (GlobalValue) + `--ns3::MmWaveHelper::E2Port` (attribute, NOT E2TermPort). mmwave-helper.cc:300 is only a default → "fix hardcode" debt gone; "NodePort durable" debt false.
- ✅ **2.5 RC control plumbing.** rc does NOT self-emit — gRPC-driven forwarder (`:7777 SendRICControlReqServiceGrpc`). Chain: grpcurl → rc → E2SM-RC ControlMessage Format1 → E2AP RIC Control Request (funcId 300) → ns-3 RX 87B ×3, **no ACK** (e2sim has Control types, no handler → that's Phase 4/5; Phase 0 proves *reachability* only). Version 2.0-vs-nov2021 undeterminable on wire (dummy OID) → Phase 3.
- ✅ **2.6 Observability limits.** tshark 3.2.3 had no E2AP dissector (3.5+ needed) → used PPID-70 filter + asn1c/pod logs + offline decode. **UPDATE (this session): tshark v4 installed via Ubuntu PPA on VM → can dissect E2AP/E2SM directly in future runs; retires offline-only workaround (supersedes both reports' open-Q on tshark).**
- ✅ **2.7 SDR-free.** Entire RAN (gNB+UE+channel+E2 node) = single ns-3 scenario-zero process. No USRP/UHD/srsRAN/ZMQ/Open5GS; testbed run.sh RF stack deliberately unused. Fully reproducible, no radio HW.

### Phase 1 — Resolve KPM v3↔v2
- ✅ **3.1 The puzzle restated.** How does a v2.0 APER decoder parse v03.00 bytes and get 5 correct metrics?
- ✅ **3.2 The SPLIT verdict.** Message = ROBUST; Header = BROKEN-but-inert.
- ✅ **3.3 H1 — why Message is robust.** APER puts NO tags on wire (positional, schema-driven; no resync point). Extension marker `...`: post-marker fields APER-invisible unless encoded. v03 MeasurementLabel adds ssbIndex/nonGoB/mIMO after `...` (verified asn:77-80), ns-3 never sends → bytes byte-identical to v2. Format1 = CHOICE root index 0 in both. Real 194B → v2 = `RC_OK 194/194`, `[2154,765,0,86,3]`. Robust BY DESIGN.
- ✅ **3.4 H2 — header breakage.** v2 `TimeStamp SIZE(4)` vs v3 `SIZE(8)` — a ROOT field, no `...` protection (verified asn:31). v2 reads 4 of 8 → cursor mid-timestamp → reads senderName length from garbage → points past 38B buffer → `RC_WMORE consumed=0/38`. Root change = no protection; the SPLIT in one comparison vs H1's post-marker diffs.
- ✅ **3.5 H3 — the salvage chain (why Phase-0 *looked* fine).** (a) `wrapper.c` uses `asn_decode` not `_complete` + RC_WMORE branch returns partial struct not NULL; (b) asn1c sets `present=Format1` from outer CHOICE tag BEFORE failing deep in senderName; (c) `control.go` logs only `present`, header-field reads commented out; (d) kpimon writes its own ingest timestamp. Failure logged only to stderr ("header RC_WMORE" = free health signal). Remove any link → real bug. (See learner open item on timestamp truthfulness.)
- ✅ **3.6 H4 — refuted (confound removal).** Purpose: H1 only holds if sides are genuinely different versions. Evidence: asn1c banner names `kpm2_0.asn -gen-APER`; Format1 struct matches on-disk v2.0; active path = handleIndication→measData (output names = InfluxDB fields); `pm_Containers`/`cellResourceReportList` = dead v1 legacy. → deployed genuinely IS v2.0.
- ✅ **3.7 Robust vs Lucky.** Robust = safe BY DESIGN (bytes provably identical, any valid v3 Format1). Lucky = safe by accident-of-architecture (4-link salvage + kpimon never reads header) — NOT data-dependent, but shatters if a different xApp reads the header.

## Stage 3 — The Broader Context (why it matters)

- ✅ **4.1 Phase-2 steer.** Keep ns-3 at v03.00 — monitoring payload genuinely v2-compatible; rollback gains nothing; RC work is v3/RC-2.0 anyway. Header mismatch = latent risk, activates only if a future xApp reads the indication header (e.g. colletStartTime alignment — learner's case).
- ✅ **4.2 What Phase 0/1 unblock.** golden pcaps (2034 KPM + 1456 RC) + reusable harnesses + proven live path + RC-on-wire (87B) + version settled → runway for Phase 3+ (RC-2.0 ASN.1, receive+ACK, forced handover).
- ✅ **4.3 Carried debts.** NodePort→scripted pod-IP discovery; dummy `OID123`→real OID; ns-3 SIGSEGV-on-reset hardening; funcId-2 hardcode→funcId/OID dispatch; + ingestion-timestamp truthfulness (learner).

---

## Misconceptions to revisit (filled as we go)
- (none yet)

## Learner-surfaced open items (validated, deferred)
- **Ingestion-timestamp vs `colletStartTime` (DATA TRUTHFULNESS).** kpimon writes its own InfluxDB ingestion time, not the payload's collection time → conflates true collection time with Δtransport + Δrouting + Δsubscription-jitter. Correct field *is* the header `colletStartTime` (that's why it exists). **Entangled with the SPLIT:** the header decode currently hard-fails (H2), so the proper field is unreadable anyway → "use ingestion time" is also the only surviving option. Caveats: (1) in ns-3 it's *sim* time, not wall-clock (`kpm-indication.cc:153`); (2) tolerable for live viz (~3s, low-latency single VM) but a real problem for Phase-6 ML training-set construction / closed-loop timing. **Action:** verify kpimon InfluxDB write-time behavior in kpimon-go source + revisit in Phase-2 header decision / Phase-6. (Learner insight, 2026-06-09.)
