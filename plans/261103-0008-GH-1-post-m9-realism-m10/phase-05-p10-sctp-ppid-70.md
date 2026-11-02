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
1. Implement all three fixes; rebuild the agent and kpm_sim images; a local loopback check shows PPID 70 in tshark.
2. M2, M3 (kpm_sim), then M5–M7 (agents): PPID 70 per node; E2AP decodes without `-d`.
3. One R3′ single run: every agent's chunks carry PPID 70; ledger and traces unchanged vs checkpoint 1.
4. Record the predicate changes in `check-diff-ledger.md`; phase exit.

## Validation
- `e2ap-pcap-facts.py --ppid` on every capture: `{node: {70: n, other: 0}}`, n > 0, for each agent and for kpm_sim.
- `tshark -r <pcap> -Y e2ap` without `-d` counts as many E2AP PDUs as the old `-d` decode did.
- M2, M3, M5–M7 green.

## Standards ledger (stub)
| Decision | Document, section | Zotero | Read |
|---|---|---|---|
| E2AP over SCTP with PPID 70 | E2GAP v08.00 §6.1 | `AE3NUEDK` | to cite |

## Risks
- kpm_sim gets rebuilt from a cached image without the patch (Medium/Medium). Mitigation: the sha256 guard on the copied file, plus the PPID check in M2.
- tshark may still select X2AP by port before PPID (Low/Medium; kongming's assumption). Step 2's count comparison settles it.

## Rollback
Re-pin the previous `TESTBED_SHA` and `E2SIM_SHA`.
