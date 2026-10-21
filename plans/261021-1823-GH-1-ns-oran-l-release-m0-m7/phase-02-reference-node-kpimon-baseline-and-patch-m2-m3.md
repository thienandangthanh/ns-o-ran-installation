# P2 — Reference node, golden pcap, kpimon baseline and SIZE(8) patch (M2, M3)

## Context
- `run_e2sim_and_connect_to_ric.sh` runs `kpm_sim` in Docker `oransim:0.0.999` and targets the `service-ricplt-e2term-sctp` **ClusterIP**:36422. Its success marker is `</E2AP-PDU>` in the log; truth comes from e2mgr `/v1/nodeb/states`.
- kpm_sim hard-codes `gFuncId = 2` (`kpm_callbacks.cpp`). kpimon-go `funcId = 2` (`control/control.go:45`) and filters `RanFunctionId == 2` (`:190`, `:247`).
- kpimon decoder: pre-generated asn1c-0.9.29 C under `e2sm/lib`. Generation flags: `-pdu=auto -fincludes-quoted -fcompound-names -findirect-choice -fno-include-deps -no-gen-example -gen-APER`. `TimeStamp.c` hard-codes size 4 at lines 25, 43 and 48. NIST's `kpm2_0.asn.patch` keeps `SIZE(4)`.
- Install script: `additional_scripts/install_xapp_kpi_monitor.sh`. It uses `kubectl exec -it` at lines 88 and 136, which fails without a TTY.
- InfluxDB: `r4-influxdb-influxdb2.ricplt:80`, org `influxdata`, bucket `kpimon`, measurements `cellMetrics` and `UeMetrics`. The token is created at install time; **never print it**.

## M2 — reference node (`gate-m2-refnode.sh`)
1. Install tshark from noble apt (non-interactive, `DEBIAN_FRONTEND=noninteractive`). Assert that `tshark -G protocols` lists `e2ap`, and record which E2SM-KPM versions the dissector handles.
2. Start a capture with `tcpdump -i any -w … sctp` on the VM, then (re)run kpm_sim through NIST's script.
3. `fetch_connected_e2_nodes.sh` shows CONNECTED. Save the `check_e2ap_version.sh` output.
4. **Sustained association:** the SCTP association stays up for at least 5 min with HEARTBEAT/SACK and no ABORT. This proves Docker-bridge → ClusterIP SCTP, the path every agent will use. The old NodePort failure mode is the hypothesis being tested.
5. tshark decodes E2SetupRequest/Response from the golden pcap now. Subscription and Indication need a subscriber, so they are captured in M3 into the same golden set.

Pass → snapshot `l2-refnode`.

## M3 — xApps (`gate-m3-xapps.sh`)
1. **Stock kpimon.** Install it through NIST's script, run non-interactively via `script -qec` or `ssh -tt`, or ship a fork `.patch` that drops `-it` (mitigation within contract). Then:
   - The golden pcap gains Subscription Request/Response and Indications. tshark decodes them.
   - kpm_sim indications land in InfluxDB: a Flux query counts rows in `kpimon` over the last 5 min, and the count must be > 0.
   - **Baseline:** over a fixed window (10 min), record the counts of `header RC_WMORE`, header `RC_OK`, message `RC_OK` and the other rvals from kpimon logs, plus the indication count seen on the wire.
2. **Decoder harness.** Write `tools/kpimon-decode-harness`. It links kpimon's own `libe2smwrapper` (built from the same image layer or source), extracts the E2SM header and message octets of each RICindication from the pcap (via `tshark -T fields` or `-x`), and prints the `asn_dec_rval_t.code` for header and message. Run it on the stock baseline, then cross-check it against the kpimon log counts.
3. **Patched kpimon.**
   1. Build asn1c **0.9.29** in a throwaway container. Regenerate `e2sm/lib` with the exact flags above from the SIZE(8) `kpm2_0.asn`.
   2. Diff the result against the checked-in `e2sm/lib`. Accept only if the change is confined to the TimeStamp constraint/size, the constraint tables and comments.
   3. If the regenerated output differs widely because of a generator version mismatch, STOP and consult kongming. Hand-editing three constraint lines would be a deviation from "regenerate" and needs user sign-off.
   4. Ship it on the Testbed fork as an updated `install_patch_files/xApps/kpimon-go/e2sm/asn1/kpm2_0.asn.patch`, plus `e2sm/lib/TimeStamp.c.patch` (and headers if touched), applied by `install_xapp_kpi_monitor.sh`.
   5. Redeploy, then re-run the window. With 8-byte kpm_sim, expect header `RC_OK` = all indications, and the harness agrees.
4. Make every step re-runnable by the gate script.

Pass → snapshot `l3-xapps`.

## Risks
- **SCTP via ClusterIP from Docker might fail like NodePort did.** The contract requires the Service target. If step 4 of M2 fails, STOP with evidence and kongming advice; this is a potential **Decision required** for the user.
- **Wireshark 4.2 might lack E2SM-KPM v3 decoding.** Then the "decode as v3" evidence comes from E2AP plus the harness and an e2-interface-based v3 decoder. Record it as a deviation in implementation-notes.
- **nexus3 image pulls during the kpimon build.** Retry them; record the failure if persistent.

## Review amendments (contract-preserving review, 2026-10-21)
- **K10: two-association probe in M2.**
  - Two throwaway containers on the default Docker bridge each hold an SCTP association from source port 36422 to the e2term ClusterIP for 5 min with no ABORT. This proves NAT and conntrack before agents depend on it.
  - Containers cannot resolve `*.svc.cluster.local` (Docker DNS uses the upstream servers), so agents get the ClusterIP resolved by the host at start.
  - If this fails, STOP and get kongming's advice. This is a possible Decision required, because the Service target is locked.
- **K13: M3 baseline counting.**
  - Count kpimon-received indications from `RIC Indication message from` lines.
  - Count WMORE with `grep -o 'header RC_WMORE'` and `grep -o 'MSG RC_WMORE'`, by occurrence, not by line.
  - Count Influx writes from `Wrote ... Metrics`.
  - RC_OK and RC_FAIL counts come from the harness only. kpimon prints nothing for RC_OK and loses RC_FAIL inside a goroutine.
  - The harness links the `.so` copied out of the deployed kpimon image and calls `asn_decode(ATS_ALIGNED_BASIC_PER)` exactly as `wrapper.c:1000` and `:1030` do.
  - M3 passes when the stock baseline is recorded (any values, even 0 Influx rows) **and** the patched kpimon has rows > 0 with harness RC_OK on every header and message.
- **K8: reinstalling kpimon.**
  - `install_xapp_kpi_monitor.sh:39` hardcodes `CLEAN_INSTALL=false`. An existing deployment then gets `rollout restart` and `exit 0` (`:46-53`), and both images share the tag `kpimon-go:latest`.
  - On the fork: honour `CLEAN_INSTALL` from the environment and add an env toggle for the SIZE(8) patch set.
  - The gate uninstalls first (`dms_cli uninstall`), asserts that the image ID changed, and checks the SIZE(8) constraint table in the `.so` copied from the new image.
  - Test `kubectl exec -it` with stdin from `/dev/null` before adding TTY wrappers.
- **K9: making regeneration reproducible.**
  - The generated lib has post-2022 asn1c skeletons (`*_jer.c`, `*_rfill.c`, `*_aper.c`) while still printing "0.9.29". Identify and pin the asn1c commit.
  - **Control step:** regenerate the NIST-patched SIZE(4) schema first. Files derived from the schema must match the shipped ones, ignoring "found in" comment lines.
  - Then switch to SIZE(8) and ship only the files that diff because of the constraint.
  - NIST's `MatchingCondItem-Choice.c` was generated from a different schema file. Leave it untouched.
- **K15: wireshark fallback.** If noble's tshark 4.2 cannot dissect E2SM-KPM v3, use NIST's `ppa:wireshark-dev/stable` (`install_and_configure_wireshark.sh`), non-interactively. The KPM OID and version are checked in the E2Setup RAN-function item.
