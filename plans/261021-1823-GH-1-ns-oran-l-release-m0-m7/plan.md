---
title: ns-O-RAN → OSC Near-RT RIC L-release on NIST v1.8.0 (M0–M7)
status: ready (goal-warmup 2026-10-21; contract + final summary user-confirmed)
created: 2026-10-21
contract: plans/reports/brainstorm-261017-0308-GH-1-ns-oran-l-release-nist-1-8-0-contract.md (user answers 2026-10-21 + "Current goal scope" win)
scope: M0–M7 only; stop at the pre-M8 planning gate
---

# Plan: ns-O-RAN on L-release RIC (M0–M7)

## Locked outcome (summary; full contract in the goal packet)
On VM `ubuntu24.04` (Ubuntu 24.04.5), rebuilt by scripts from `fresh-install`:
NIST v1.8.0 Near-RT RIC on the **L** pins; kpimon-go with a TimeStamp `SIZE(8)`
patch; ns-O-RAN scenario-zero where every E2 node is served by its own
out-of-process agent (NIST-pinned e2-interface, own netns, connects to the
e2term **Service**). KPM decodes on the wire and via kpimon's own decoder
(`RC_OK` header + message). Multi-gNB robust. Finale: revert to `fresh-install`
→ unattended scripted run → M0–M7 green. Then stop.

Out of scope: M8/RC, R0–R3, pacing design, M9 proper, subscription option B,
N release (no fallback, no diagnostic without asking), Bronze RIC, upstream
PRs, ns-3 radio/scenario changes, host changes, any reuse of
`dev/migrate-to-l-release` / `dev/l-release*` code or design.

## Phases
P7 (RC) of the original contract is deferred; numbering is kept so "P3 sign-off before P4" stays literal.

| # | Phase | Milestone | Snapshot | Status |
|---|---|---|---|---|
| P0 | [Preflight, branches, gate harness](phase-00-preflight-branches-gate-harness-m0.md) | M0 | `l0-preflight` | **done** (M0 green 2026-10-21) |
| P1 | [RIC on L pins](phase-01-ric-l-install-m1.md) | M1 | `l1-ric-up` | **done** (M1 green) |
| P2 | [Reference node, golden pcap, kpimon baseline + SIZE(8) patch](phase-02-reference-node-kpimon-baseline-and-patch-m2-m3.md) | M2, M3 | `l2-refnode`, `l3-xapps` | **done** (M2, M3 green) |
| P3 | [E2 agent design checkpoint](phase-03-e2-agent-design-checkpoint.md) | — (user sign-off) | — | **done** (user sign-off 2026-10-22) |
| P4 | [ns-3 decouple, IPC emitter, scripted build, timing](phase-04-ns3-decouple-ipc-emitter-build-timing-m4.md) | M4 | `l4-ns3-build` | **done** (M4 green) |
| P5 | [Agent + single-gNB KPM](phase-05-e2-agent-single-gnb-kpm-m5-m6.md) | M5, M6 | `l5-agent-setup`, `l6-kpm` | **done** (M5, M6 green) |
| P6 | [Multi-gNB robustness](phase-06-multi-gnb-robustness-m7.md) | M7 | `l7-multignb` | **done** (M7 green) |
| P8 | [Unattended re-run from fresh-install to M7; docs; pre-M8 gate](phase-08-unattended-rerun-to-m7-and-handoff.md) | M0–M7 again | `f7-rerun-green` | in progress |

Dependencies: strictly sequential P0→P1→P2→P3→P4→P5→P6→P8. P3 needs P2's
golden pcap, and P4 starts only after P3 sign-off. Idle time during long
installs (P1/P2) may be used for read-only P3 research and for pinning the
asn1c generator (K9).

## Traceability

| Phase | Contract items | Acceptance signals | Facts (F) / assumptions (A) / prereqs (X) / user decisions (U) |
|---|---|---|---|
| P0 | fork branches; L drop-in; gate scripts; snapshot discipline | M0 list | F: VM 24.04.5, cgroup2, 8 vCPU, 15 GiB, `/` 85 GB free, sudo -n OK, egress OK, sctp.ko present (probe 2026-10-21). F: host 118 GB free, libvirt 12.8, `fresh-install` external/shutoff. A: offline disk-only external snapshots revert cleanly (M0 probe proves). U: gate-harness home (see Open decisions). |
| P1 | RIC on L pins | M1 list | F: L json pins ric-dep `ee47a347`, appmgr `4c05932d`, e2-interface `da6f82f2`; kpimon-go `8bbbbbb9`/rc `a2282ee` are k-release (no L branch exists; L = RIC platform). F: patched installer pins k8s 1.33, helm 3.20, docker 29.5, flannel 0.28.5. A: those packages exist for `noble`. |
| P2 | golden pcap; kpimon stock baseline; kpimon SIZE(8) patch | M2, M3 + baseline incl. `header RC_WMORE` count | F: kpimon decoder = pre-generated asn1c-0.9.29 C in `e2sm/lib`, `TimeStamp.c` hard-codes size 4 (lines 25/43/48). F: kpimon `funcId=2` (control.go:45). F: kpm_sim runs in Docker `oransim:0.0.999` → e2term **ClusterIP**:36422. A: Docker-bridge → ClusterIP SCTP sustains (M2 proves). |
| P3 | agent design (IPC, placement), subscription option A, timestamp in sample | journal + kongming + **user sign-off** | U: Approach A, per-agent netns, Service target, option A. F: ns-3 file-logging mode already produces the metric set without ASN.1. |
| P4 | ns-3 stops linking asn1c/e2sim; IPC emitter; scripted build; timing | M4 list | F: lte/mmwave link oran-interface → `find_external_library(e2sim)`. A: GCC 13 builds 8c42089d with small fixes. |
| P5 | agent per gNB; KPM v3 on wire; kpimon RC_OK | M5, M6 | F: ns-3 timestamp is 8-byte `htobe64` today; kpimon expects func 2. A: Wireshark (noble 4.2.x) dissects E2AP + E2SM-KPM. |
| P6 | multi-gNB; Service reconnect | M7 | F: scenario-zero = 4 mmWave gNB + 1 LTE eNB by default. A: agent restart is enough to reconnect after e2term pod delete. |
| P8 | revert to fresh-install; unattended re-run | M0–M7 green unattended | X: host disk headroom for a 2nd install (see Open decisions). |

## Cross-cutting rules (every phase)
- **Evidence rule.** A gate is green only when wire bytes decode with tshark, and for KPM, through kpimon's decoder harness. Log lines are supporting evidence only. M1 and M4 carry no E2 bytes; their evidence is pinned SHAs and pod state (M1) and the build and linkage checks (M4). Each gate writes `evidence/<gate>/<UTC-ts>/` (tshark text, harness output, `verdict.json`) and copies it back to the host plan dir.
- **Evidence hygiene (K15).**
  - Run every evidence file through a scrubber before copying. It redacts the InfluxDB token, which `install_xapp_kpi_monitor.sh` writes to `influxdb_auth_token.json` and seds into `control.go`.
  - Pcaps stay out of git; commit a sha256 manifest instead.
  - Each gate checks that VM `/` has at least 25 % free and prunes the Docker build cache.
- **Capture (K10).**
  - Capture on a single interface (`docker0` for agent-side traffic, optionally `nsenter` into the e2term pod netns), never `-i any`.
  - Decode with `-d sctp.port==36422,e2ap`. Start capturing before E2Setup.
  - Dedupe by TSN when counting.
- **Unattended NIST calls (K3).**
  - Every NIST script runs with blocking stdin (`sleep infinity | …`) inside `timeout`.
  - Long gates run detached on the VM (`systemd-run --unit=gate-…` or `setsid nohup`). `vm-exec.sh` polls for `verdict.json`, so an ssh drop never kills a gate.
  - Gate watchdog: if e2term is the only unready ricplt pod for more than 10 min, delete it once. This is NIST's own remedy; log and count it.
- **Bring-up contract (K6).**
  - Each gate begins with an idempotent `gate_bringup <profile>`.
    - `ric`: wait for the ricplt pods.
    - `refnode`: NIST `run.sh`.
    - `agents`: `run.sh`, then `stop_e2sim.sh`, then assert that the e2mgr node set equals the expected agents.
  - `run-to-m7.sh` reboots at the same gate boundaries in every run, whether or not it takes a snapshot.
- **Gate scripts.** Every gate is `scripts/gates/gate-mN-*.sh`. They are idempotent and non-interactive (no `read`, no `-it`), exit non-zero on fail, and are callable by `scripts/run-to-m7.sh`. This keeps M9 possible later.
- **Snapshots.** Use `scripts/vm/vm-snapshot.sh create <name>`: graceful guest shutdown, `virsh snapshot-create-as --disk-only --atomic`, start, wait for ssh. Before each create, check host `df /home` ≥ 20 GB plus the expected growth of the next phase; otherwise STOP and ask. Never delete `fresh-install`. On a bad state, revert to the last gate snapshot and log the revert in `implementation-notes.html`.
  - Always shut the VM off before a revert.
  - Save `snapshot-dumpxml` per snapshot to evidence.
  - Names are prefixed per run: `l*` for the dev run, `f*` for the P8 re-run, and `m0-probe-<run>` for the probe, so a re-run never collides with existing names.
  - Inspect chains with `virsh domblklist`/`dumpxml` plus `du`. The image files are `libvirt-qemu`-owned, so `qemu-img` would need sudo.
  - The chain is a raw base `ubuntu24.04` plus qcow2 overlays (verified with `dumpxml`).
- **Code delivery.** Branch `dev/l-release-nist180` on the 4 forks, cut from the upstream pins. Push WIP freely. Gate runs clone from GitHub at the SHAs in `scripts/pins.env`. The NIST installer runs only from a VM-local clone.
- **L only.** On an L failure: stop, root-cause, look for a workaround, report. No N, not even as a diagnostic, without asking.
- **Advisors.** kongming (Opus 5.5 xhigh) at every design fork and after 2 failed attempts on one gate.
- **Records.** `implementation-notes.html` in this plan dir is updated each phase. Journals go in `docs/journals/` for consequential events.
- **Landmines are hypotheses** (funcId 2, 8-byte TimeStamp, OID123, uppercase cell_map, NodePort SCTP). Each one is re-checked by a gate, never assumed.
- **Process hygiene (K14).**
  - Track the ns-3, agent and capture PIDs.
  - Run the ns-3 binary directly (not `./ns3 run`), in its own process group or `systemd-run --scope`.
  - Kill by PGID, then verify with `pgrep -f <full path>` and `ss -Sanp`.
  - `pkill -x` cannot match: `comm` is truncated to 15 characters.

## Contract-preserving review
kongming collect-only review, 2026-10-21: 15 findings (K1–K15). Classification and matrix:
`plans/reports/review-261021-1855-GH-1-contract-preserving-review-and-preflight-matrix.md`.

## Decisions (resolved by user 2026-10-21, during warmup)
1. **D1, harness home (K12).**
   - The harness (`scripts/gates/`, `scripts/vm/`, `scripts/run-to-m7.sh`, `scripts/pins.env`, `tools/`) lives on this parent repo's branch `migrate-l-release-NIST-1-8-0`, pushed to `origin`.
   - The user makes `thienandangthanh/ns-o-ran-installation` **public** before the run starts, so the VM clones it anonymously from `fresh-install`.
   - M0 verifies the repo is public with `gh repo view --json visibility` and proves an anonymous HTTPS clone works.
   - The harness SHA is passed to `run-to-m7.sh` as an argument.
2. **D2, snapshot cleanup (K4).**
   - Before P8, and only after the evidence is archived on the host, the run may delete its **own** snapshots (`l*`, `m0-*`) if the disk budget requires it.
   - `fresh-install` is never touched.
   - If libvirt refuses a delete, STOP and ask.
3. **D3, single-gNB mode (K11, outcome-change request approved).**
   - Add an optional CLI arg `--nMmWaveEnbNodes` to scenario-zero, with **default 4**, so default behaviour is byte-for-byte unchanged.
   - 1-gNB runs (M4 timing, P5) set it to 1.
   - This is recorded as an approved addition to the contract's Allowed substitutions.
   - No other scenario or radio change.

## Rollback
Environment: revert to the previous gate snapshot. Code: `git reset` on the fork branch, done by the orchestrator only. Nothing on the host changes.
