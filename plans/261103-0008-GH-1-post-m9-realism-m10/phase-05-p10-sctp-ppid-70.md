# P05 (MC, T-A P10): SCTP PPID 70 on every E2 node (ns-3 agents and kpm_sim)

**Start state:** checkpoint-1 pins; `f7-rerun-green`. **Snapshot at exit:** none.

## Context
- The ns-3 agents send every E2AP message with PPID 0 through their own `::send` [V `ns3_e2_agent/src/sctp-association.cpp:147`]; their socket options are set at `:29-65`.
- The M2/M3 reference node kpm_sim also sends PPID 0. The Testbed builds it from OSC `sim/e2-interface` (`install_scripts/install_e2sim.sh:49-59`, which copies `install_patch_files/e2-interface/…` over the clone), and its plain `send()` is at `sim-e2-interface/e2sim/src/SCTP/e2sim_sctp.cpp:235` [V, OSC clone at `da6f82f`].
- The contract cites the wineslab fork (`oran-e2sim/e2sim/src/SCTP/e2sim_sctp.cpp:228`, pin `E2SIM_SHA`), which kpm_sim does not use. Both trees are fixed (plan I-9).

## Requirements (contract, A1)
- **AC11:** in every live capture of the end run, every E2 node → e2term DATA chunk carries PPID 70, judged per node, and tshark decodes E2AP without `-d sctp.port==36422,e2ap`. "Every E2 node" means the ns-3 agents and kpm_sim. This phase builds the check and proves it in dev (M2, M3, M5–M7 and one rung); P13 judges the end run.

## Design
- **Agent:** after connect, set `SCTP_DEFAULT_SNDINFO` with `snd_ppid = htonl(70)`. If the option fails, use `sctp_sendmsg` with the PPID; if neither works, association start fails loudly.
- **kpm_sim:** new `install_patch_files/e2-interface/e2sim/src/SCTP/e2sim_sctp.cpp`, the pinned file with `sctp_sendmsg(…, ppid = htonl(70), …)` at the send site. `install_e2sim.sh` gains one `cp` line next to `:54-57`, and a guard checks that the copied file's sha256 equals the patch file's.
- **wineslab fork:** the same one-line fix on `dev/l-release-nist180`; bump `E2SIM_SHA`.
- **Check:** `tools/e2-evidence/e2ap-pcap-facts.py --ppid` builds a per-source PPID histogram (tshark `sctp.data_payload_proto_id`) and maps each source address to its E2 node (agents by container IP, kpm_sim by its pod IP).

## Files
- Agent: `ns3_e2_agent/src/sctp-association.cpp`, `ns3_e2_agent/src/sctp-association.hpp`.
- Testbed: new `install_patch_files/e2-interface/e2sim/src/SCTP/e2sim_sctp.cpp`, `install_scripts/install_e2sim.sh`.
- wineslab e2sim fork: `e2sim/src/SCTP/e2sim_sctp.cpp`.
- Harness: `tools/e2-evidence/e2ap-pcap-facts.py`, `scripts/gates/capture.sh` (decode without `-d`), PPID checks in `gate-m2-refnode.sh`, `gate-m3-xapps.sh`, `gate-m5..m7`, the rung capture checks and the new `gate-e2i-interop.sh` (P06); `scripts/pins.conf` (`TESTBED_SHA`, `E2SIM_SHA`).

## Steps
0. Stop A carry-ins (`plans/reports/decisions-261104-0214-GH-1-m10-stop-a-rulings.md`):
   - **G2, host-only, before any VM work:** promote each δ reference's raw ledger and predictor records into `reference/r3p-d{100,150,200,500}/raw/` the way `reference/m9-r3p-raw/` was made (`trace/e2-control-ledger.jsonl`, `r3p/predictor-records.jsonl`, `extra/*.json`, the frozen scenario), from the P04 run dirs or the `plans-evidence-raw-m10-p04-20261103.tar.zst` archive; write each dir's `SHA256SUMS`; `sha256sum -c` passes.
   - **S3, P15 scoping read (code only, no VM):** find why kpimon's per-cell Format 1 loop builds no action for ns-3 nodes (the RAN function definition the agent sends, or e2mgr's cell list). Record the answer and the fix size in this phase's exit record. If the fix needs e2mgr RAN-function cell lists (the F7 limit), P15 exits to record-only and that exit is reported at Stop A′.
   - **S5:** the chain scripts write `df -BG /home` and the active overlay's `du -BG` at every gate boundary into the run log, from this phase on.
1. Implement all three fixes; rebuild the agent and kpm_sim images; a local loopback check shows PPID 70 in tshark.
2. M2, M3 (kpm_sim), then M5–M7 (agents): PPID 70 per node; E2AP decodes without `-d`.
3. One R3′ single run: every agent's chunks carry PPID 70; ledger and traces unchanged vs checkpoint 1.
4. Record the predicate changes in `check-diff-ledger.md`; phase exit.

## Validation
- `e2ap-pcap-facts.py --ppid` on every capture: `{node: {70: n, other: 0}}`, n > 0, for each agent and for kpm_sim.
- `tshark -r <pcap> -Y e2ap` without `-d` counts as many E2AP PDUs as the old `-d` decode did.
- M2, M3, M5–M7 green.
- G2: `sha256sum -c reference/r3p-d*/raw/SHA256SUMS` passes. S3: the scoping answer is in the exit record. S5: every chain log has a `df`/`du` line per gate boundary.

## Standards ledger (stub)
| Decision | Document, section | Zotero | Read |
|---|---|---|---|
| E2AP over SCTP with PPID 70 | E2GAP v08.00 §6.1 (p. 44): "The Payload Protocol Identifier assigned by IANA to be used by SCTP for the application layer protocol E2AP is 70. This value is to be used for all deployment configurations"; 71 and 72 reserved | `AE3NUEDK` (PDF `WVKTACCS`, `pdftotext -layout`) | 2026-11-04 |
| PPID per message through an SCTP_SNDINFO control message, or as the socket default through SCTP_DEFAULT_SNDINFO | IETF RFC 6458 §5.3.4 (SCTP_SNDINFO), §8.1.31 (SCTP_DEFAULT_SNDINFO) | not in Zotero (socket API, not an O-RAN/3GPP choice) | 2026-11-04 |

## Risks
- kpm_sim gets rebuilt from a cached image without the patch (Medium/Medium). Mitigation: the sha256 guard on the copied file, plus the PPID check in M2.
- tshark may still select X2AP by port before PPID (Low/Medium; kongming's assumption). Step 2's count comparison settles it.

## Rollback
Re-pin the previous `TESTBED_SHA` and `E2SIM_SHA`.

## Exit record (in progress)
- **Step 0, G2 (host-only):** `reference/r3p-d{100,150,200,500}/raw/` promoted from the P04 run dirs (`evidence/r3p/20261103T{072946,075243,081614,084045}Z/runs/live1`, harness 876c8d6): ledger, predictor records, schedule, `extra/*.json`, frozen scenario/schedule/stage-A at 876c8d6, `SOURCES.txt`; every copied file's sha256 equals its run's `evidence-sha256.txt` entry; `sha256sum -c` passes for all four (13 files each). Commit 58629fc.
- **Step 0, S3 (P15 scoping read, code only):** kpimon builds no per-cell Format 1 action for ns-3 nodes because its cell list is empty, and the list never comes from e2mgr RAN-function cell lists.
  - kpimon (`install_patch_files/xApps/kpimon-go/control/control.go.patch`, `initializeNode`) reads `Glob_Ran_cell[meid]` from its in-pod sidecar `f1apServer` (`http://localhost:8090/getdata?gnbid=<meid>`; upstream kpimon-go 8bbbbbb `f1apHelper/f1apServer.go`, started by `entripoint.sh`). The sidecar fetches the e2mgr nodeb, takes the `nodeConfigs` entry whose `e2nodeComponentInterfaceType` is `"f1"` (else entry 0), base64-decodes its request part and decodes it as an F1AP F1 SETUP REQUEST (`decodeF1apGetCellIds`) for served-cell NR CGIs.
  - The ns-3 agent registers one NG component whose request part is the ASCII text `0000000202` (`evidence/e2-identity-setup/20261102T184414Z/ranfunc-src.json`: `MDAwMDAwMDIwMg==`), so there is no F1 entry, the F1AP decode yields no cell and the Format 1 loop (`encode_actionsToBeSetup`) is empty; only the Format 3 action is built (kpimon log `evidence/r3p/20261103T072946Z/runs/live1/kpimon.log`: one action, ActionID 1). No "Unable to read F1 cell metadata" error appears: the sidecar answers with an empty list.
  - e2mgr 6.0.6 does store `nodeConfigs` for both node types (gNB: the NG entry above; eNB probe: an `x2` entry, `evidence/e2-identity-setup/20261102T192656Z/e2mgr-nodeb-enB_macro_001_001_0ffffe.json`). The F7 limit is about `ranFunctions` on eNB nodes, not about cell lists.
  - **Answer: P15 stays a fix (no record-only exit).** Fix size, medium, in P10 as ruled: (a) kpimon learns each node's cells from the E2 node component that P06 makes spec-shaped (the en-gNB's X2 component; its request part carries the served NR cells per R-3/I-5), decoded in the kpimon fork, not through the F1-only sidecar; (b) the agent answers each admitted action in the format it asked for (Action Definition Format 1 → Indication Format 1 for that cell; Format 3 → Indication Format 2), instead of both formats under one action; (c) the p12 judge and the KPM checks re-baselined at cp3 (P11). It depends on P06's X2 component and on the Amendment 2 e2mgr patch for en-gNB setups, both already in plan.
- **Step 0, S5:** `scripts/vm/vm-exec.sh` writes `host-disk.tsv` (start and end: UTC, `/home` free GiB, active vda overlay, its allocated GiB from `du -BG`) into every gate's evidence dir and logs both lines (harness 601c988; allowlisted in `plans/.gitignore`). `run-to-m9.sh` runs every step through `vm-exec.sh`, so the M10 runner inherits it.
- **Step 1, fixes:**
  - Agent (Testbed d48c792): `SctpAssociation::finish_connect` sets `SCTP_DEFAULT_SNDINFO` with `snd_ppid = htonl(70)`; if the kernel refuses it, every send carries an `SCTP_SNDINFO` control message with PPID 70 (a send that cannot is Lost). New `tests/sctp-ppid-loopback-test.cpp` (CMake target, installed in the image). Host loopback: PASS on both paths (`evidence/p05-ppid-offline/20261103T180737Z/agent-loopback.txt`).
  - kpm_sim (Testbed d48c792, d84068c): new `install_patch_files/e2-interface/e2sim/src/SCTP/e2sim_sctp.cpp` (OSC e2-interface da6f82f with `sctp_send_data` sending through `sendmsg` + `SCTP_SNDINFO` PPID 70); `install_e2sim.sh` copies it, checks its sha256 and labels `oransim:0.0.999` with `e2sim.sctp.sha256`.
  - wineslab e2sim fork e270581: the same `sctp_send_data` fix.
  - **Design deviation (recorded):** the design named `sctp_sendmsg`. libe2sim does not link libsctp, so both e2sim trees use `sendmsg` with the `SCTP_SNDINFO` control message that `sctp_sendmsg` wraps (RFC 6458 §5.3.4); same wire effect, no new link dependency.
  - Harness 601c988, b39595a: decode by PPID at every gate/tool site (ledger row 61); `e2ap-pcap-facts.py --ppid` + `e2-facts-query.py ppid` and the per-gate PPID checks (row 62); the kpm_sim image guard in M2/M3 (row 63). Offline: cp1 live1 capture (nodes PPID 0) fails the judge (7 vs 778 E2AP frames); the same capture with node PPIDs rewritten to 70 passes 778 = 778; e2-evidence self-test with six new `ppid` cases ok (`evidence/p05-ppid-offline/20261103T180737Z/`).
- **Steps 2–3 (VM):** chain `m10-p05-chain-1` from `r3p-green` (as P03 attempt 1; it carries the i0/i2 installs that the r3p run needs; ns-3 pins unchanged, so M4 is not re-run), harness b39595a: M2 → M3 → M5 → M6 → M7 → r3p `--mode single`. Host /home 88 GiB after the revert unlinked the 52 GiB overlay; /mnt/data 20 GiB.
