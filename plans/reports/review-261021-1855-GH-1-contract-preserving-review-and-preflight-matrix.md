# Contract-preserving review and preflight matrix: ns-O-RAN L-release M0–M7

Date: 2026-10-21. Plan: `plans/261021-1823-GH-1-ns-oran-l-release-m0-m7/plan.md`.

**Reviewer.** kongming (Opus 5.5, xhigh), collect-only with no edits. The controller classified every finding before any plan edit, and applied only the `mitigation-within-contract` edits, each as a "Review amendments" section in the phase file it affects.

**Verified by the controller before classifying:**
- The parent repo `thienandangthanh/ns-o-ran-installation` is PRIVATE; the 4 forks are PUBLIC (`gh repo view`).
- scenario-zero hardcodes `nMmWaveEnbNodes=4`, `nLteEnbNodes=1`, `ues=3` (`scenario-zero.cc:378-380`).
- e2-interface `da6f82f2` hardcodes gNB ID `B5C67788` and PLMN `747` (`encode_e2apv1.cpp:158-174`, read via the GitHub API).
- One reviewer sub-claim is **rejected**: the disk chain is a raw base `ubuntu24.04` under a qcow2 overlay (`virsh dumpxml`), not a qcow2 backing image.

## Classification

| ID | Finding (short) | Class | Disposition |
|---|---|---|---|
| K1 | NIST e2sim hardcodes the gNB ID and PLMN, so every agent would be the same node | mitigation-within-contract | Mandatory P3 item. The fix (env-configurable patch, NIST-style) stays inside "built from NIST's pinned e2-interface". Settled at the P3 sign-off. |
| K2 | kpimon Influx has no tags and uses wall-clock time; it drops format-1 on a count mismatch | mitigation-within-contract | Kpimon ingest profile plus synthetic correlation KPIs in P3. The M6/M7 Influx checks join on `(nodeId, simTimeMs)`, so the acceptance meaning is unchanged. A kpimon tag patch would be an OCR and was **not** applied. |
| K3 | NIST wait/connect loops busy-spin or hang without a TTY | mitigation-within-contract | plan.md "Unattended NIST calls", plus P1. |
| K4 | M0 probe skips the non-leaf revert and branch delete | preflight-required | M0 probe strengthened (P0). Fallback is a user decision (D2). |
| K5 | ns-3 E2 code is v1-style and ASN-coupled at compile level | mitigation-within-contract | P3 metric-mapping table; P4 extra work items. |
| K6 | Offline snapshots reboot the guest; no bring-up contract | mitigation-within-contract | plan.md `gate_bringup`, plus P1 and P5. |
| K7 | Agent restart can SIGPIPE ns-3; submgr drops subscriptions | mitigation-within-contract | P3, P4, P6. |
| K8 | Re-running the kpimon install silently keeps the old image | mitigation-within-contract | P2. |
| K9 | The asn1c "0.9.29" generator is not reproducible as named | preflight-required | P0 idle time and the P2 control step. The existing wide-diff STOP is kept. |
| K10 | Multi-agent SCTP via Docker NAT is untested; `-i any` double-counts | preflight-required | P2 two-association probe; capture rule in plan.md. A failure becomes a possible Decision required at P2. |
| K11 | "1 gNB" has no knob; scenario-zero hardcodes 4+1 | **outcome-change-request** | **Decision required (D3)**. |
| K12 | Harness home: the parent repo is private | preflight-required | **User decision (D1)**. The harness SHA is passed as an argument. |
| K13 | kpimon logs cannot give RC_OK counts | mitigation-within-contract | P2: the harness is the RC_OK authority. The M3 pass rule is clarified without lowering it. |
| K14 | `pkill -x` never matches the ns-3 binary | mitigation-within-contract | plan.md process hygiene; P4. |
| K15 | Re-run drift, extra egress, token leakage into evidence | preflight-required + mitigation | P0 egress checks, M1 `versions.txt`, P8 diff, evidence scrubber. |

Minor wording fixes were applied: the P4/P2 ordering sentence, the evidence-rule exemption for M1/M4, and moving the OID check to E2Setup.

Kept unchanged, per the reviewer's "must not change" list:
- offline disk-only external snapshots;
- the L drop-in, and running the installer from a VM-local clone;
- the harness as the RC_OK authority;
- the stock baseline before the patch;
- the wide-diff STOP;
- the M4 linkage checks;
- the P3 sign-off;
- strict ordering;
- per-agent netns plus the Service target.

## Preflight matrix (all phases)

Probes ran on 2026-10-21 and were all read-only: VM via ssh, host via virsh/df/gh, kpimon-go cloned to the scratchpad.

| Phase | Requirement | Check method | Status | Owner / unblock action | Blocking? |
|---|---|---|---|---|---|
| P0 | VM reachable, Ubuntu 24.04.5, `sudo -n` | ssh probe | available | — | no |
| P0 | VM resources (8 vCPU, 15 GiB, `/` 85 GB free) | ssh probe | available (85 GB is tight; monitored) | gate disk checks | no |
| P0 | Host `/home` ≥ 20 GB free | `df` | available (118 GB) | stop rule active | no |
| P0 | `fresh-install` present | `virsh snapshot-list` | available | never delete | no |
| P0 | Snapshot create, revert (non-leaf), branch delete without sudo | M0 probe (K4) | pending | runs first in M0; on failure, STOP and ask | yes for P1+, not for Ready |
| P0 | GitHub push to the 4 forks | `git ls-remote origin` over ssh; `gh auth` repo scope | available | — | no |
| P0 | Harness home cloneable from `fresh-install` without credentials | decision D1 | **pending decision** | user | yes |
| P0 | VM egress: github, docker hub, pkgs.k8s.io, gerrit, nexus3 | curl HEAD | available | — | no |
| P0 | VM egress: packagecloud, dl.google, proxy.golang, Launchpad PPA | M0 curl HEAD | unknown | M0 checks | no |
| P0 | `sctp` module | `modinfo sctp` | available (not loaded) | `modprobe` in M0 | no |
| P1 | noble packages: k8s 1.33, docker 29.5, helm 3.20, containerd.io | M0 repo-index check | unknown | if missing, follow the L-failure path (no N) | no (gated in M0) |
| P1 | NIST ric-dep patches apply to L `ee47a347` | M0 `git apply --check` | pending (erratum 2: blob SHAs identical) | — | no |
| P1 | L images (e2term 6.0.6 etc.) pullable from nexus3 | nexus3 reachable (401 = registry challenge) | available (reachability only) | — | no |
| P2 | Docker → ClusterIP SCTP, 1 and 2 associations, sustained | M2 probe (K10) | unknown | on failure, STOP, kongming, possible Decision | no (gated) |
| P2 | tshark dissects E2AP and E2SM-KPM v3 | M2 `tshark -G protocols`; PPA fallback | unknown | fallback documented | no |
| P2 | kpimon patches apply on `8bbbbbb9` | M0 `git apply --check` | pending | — | no |
| P2 | Reproducible asn1c generator for kpimon `e2sm/lib` | K9 control step | unknown | wide diff means STOP and kongming; hand-edit needs user sign-off | no (gated) |
| P2 | InfluxDB token never printed | evidence scrubber | n/a until P2 | — | no |
| P3 | User sign-off on the agent design journal (K1, K2, K5, K7 inside) | planned gate | pending (by design) | user at P3 | no (in-run gate) |
| P4 | ns-3.38 + oran-interface build with GCC 13 / CMake 3.28 | M4 | unknown | kongming after 2 failures | no |
| P4 | Single-gNB configuration for timing and P5 | decision D3 (K11) | **pending decision** | user | yes |
| P5 | e2term 6.0.6 accepts agent E2Setup with RAN function 2 and a v3 definition | M5 | unknown | — | no |
| P6 | e2mgr accepts reconnect with the same node ID after an e2term pod delete | M7 | unknown | kongming after 2 failures | no |
| P6 | CPU headroom: 5 agents + ns-3 + RIC on 8 vCPU | M7 load evidence | unknown | recorded for the pacing gate | no |
| P8 | Host disk for a second full install on the overlay chain | per-gate `du` budget | unknown | decision D2 fallback | no (decision covers it) |
| all | kongming available (Opus 5.5 xhigh) | used in this review | available | — | no |

## Must provide or decide before the long run
- **D1 (K12).** Where the gate harness and pins live, given the private parent repo.
- **D2 (K4).** The fallback if host space or libvirt branch-delete behaviour blocks the P8 re-run.
- **D3 (K11, outcome-change request).** What "1 gNB" means.

## Can be deferred (allowed by the contract)
- K1 identity mechanism, K2 ingest profile, K5 mapping and K7 restart semantics. All are settled inside the P3 journal and user sign-off.
- The asn1c generator pin (K9), resolved in P2 under its STOP guard.

## Unresolved questions
- Whether the E2SM-KPM v3 dissector in Wireshark 4.2 is enough; resolved at M2.
- Whether the LTE eNB counts as an E2 node in "every scenario-zero gNB" for M7. Fixed at P3 from the ns-3 defaults (`e2lteEnabled`).
