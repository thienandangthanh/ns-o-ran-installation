# M8–M9 goal warmup: contract-preserving review and preflight matrix (2026-10-23 01:15 KST)

**Outcome.** I classified all 27 findings of the collect-only kongming review (`kongming-261023-0020-GH-1-m8-m9-plan-collect-only-review.md`, Opus 5.5 xhigh) before any plan edit, and I did not use the default red-team apply. The user's rulings at 00:46–01:03 KST resolved the one blocker (K1) and the three items that needed a user decision (K2, K4, K11). I folded the 21 contract-preserving mitigations into the phase files as binding "Review amendments" blocks. **Five preflight items remain for the user before `/goal`.** Until they are done, the warmup state is **Blocked**, not Ready.

## 1. Classification

| Finding | Class | Disposition |
|---|---|---|
| K1: M0 probe creates and deletes snapshots inside M9 | blocker → user ruling | **Resolved (user, 00:52/01:03):** the snapshot rule is relaxed as in M0–M7 D2. `fresh-install` and `f7-rerun-green` are never deleted, and `r3-green` is kept until M9 is green. Decision record 01:03 amendment; P0, P9 and P10 amendments. |
| K2: M9 disk budget probably short | preflight-required + user ruling | **User frees ≥ 40 GB on `/home` before `/goal`** (must-provide). Projection formula corrected and computed at P0; a negative result is T2 at P0. |
| K3: permission rules do not match the plan's command forms | preflight-required | Must-provide (§2). |
| K4: no PDCP spec in Zotero; LTE PDCP header on the EN-DC bearer | preflight-required + user ruling | **User adds 3GPP TS 38.323 and 36.323** (must-provide). New recorded deviation **P7** (user, 00:46). |
| K5: R1(b) infeasible with the listed precheck order | mitigation-within-contract | The contract lists the prechecks without an order. D4 checks "in handover" before "already on target"; the R1(b) and R1(c) scenarios are re-specified. P1 and P4 amendments. |
| K6: N6 ignores `UeMetrics` rows | mitigation-within-contract | The contract's N6 says "rows for every seq". The UE-row predicate and seq-keyed selection are added. P7 and P8. |
| K7: G1 mapping half done | mitigation-within-contract | G1 is in scope; the mapping is completed with typed filters and serving cell first. P7. |
| K8: image digest in the equality set | mitigation-within-contract | The contract only requires the digest to be recorded; the reference is split into `equal/` and `recorded/`. P9 and P10. |
| K9: P2 wire check without an RMR sender | mitigation-within-contract | The check moves to the IPC level; a forced-late case is added with the RIC. P2 and P3. |
| K10: missing Verify signals (C5, ipcDropped, droppedNoSub, slack, KPM UE move, per-key positives, reset evidence) | mitigation-within-contract | The verdict fields and Verify lines are added. P2–P5; C5 is added to traceability. |
| K11: C1 replay cannot carry RC/KPM bytes | outcome reading → user ruling | **User accepted (01:03):** the live runs compare all components; the replay compares the ledger, IPC samples and traces. Contract text amended. |
| K12: stub QP registration and probe reach | mitigation-within-contract | P5, P7, P8. |
| K13: M9 inputs left implicit | mitigation-within-contract | `rung-config.json`, `--mode`, install order, decoder on the VM, kpimon re-subscription. P0 and P6. |
| K14: freeze order | mitigation-within-contract | P9 and P10. |
| K15: watchdog margin; VM unit not stopped | mitigation-within-contract | P0 and P10. |
| K16: no evidence `.gitignore` | mitigation-within-contract | P0. |
| K17: weak variation check versus QP `constant()` | mitigation-within-contract | P6 and P7. |
| K18: dump from the wrong run | mitigation-within-contract | P6 and P7. |
| K19: weak free-run digest checks | mitigation-within-contract | P1, P2 and P6. |
| K20: misleading start states | mitigation-within-contract | P6 and P8. |
| K21: stop-clause robustness | mitigation-within-contract | Opener and `plan.md` (own-message markers, ids enumerated, snapshot-current, degraded PAUSE, no "continue"). P7 host work only in segment 2. |
| K22: locked inputs uncommitted | preflight-required | Must-provide (§2). |
| K23: decoder schema and fixture details | mitigation-within-contract | P0 and P1. |
| K24: gate-id regex versus gate names | mitigation-within-contract | P0 and P7. |
| K25: one wrong fact in P6 | mitigation-within-contract | Corrected in the P6 amendment. |
| K26: traceability gaps | mitigation-within-contract | Rows added in `plan.md`. |
| K27: installer stale clone | mitigation-within-contract | P7. |

There is no open outcome-change request. The user approved the contract edits as they arose (00:13 DL PDCP row; 01:03 snapshot rule and C1 reading). They are confirmed again at the final summary.

## 2. Preflight matrix (every phase; non-mutating checks run 2026-10-23 00:20–01:10 KST)

| Phase | Requirement | Check method | Status | Owner / unblock action | Blocking? |
|---|---|---|---|---|---|
| all | ≥ 40 GB freed on `/home` outside the VM images (K2) | `df -h /home` | **missing** (75 G free now; target ≥ 115 G) | user frees space | yes |
| P6 | 3GPP TS 38.323 and 3GPP TS 36.323 in Zotero with PDFs (K4) | zotero-mcp search | **missing** | user adds both | yes |
| all | Permission rules match the plan's command forms (K3) | rule names in `.claude/settings.local.json` | **partial**: 23 allow and 2 deny rules exist, but the `virsh` rules are bare, and bare `virsh` resolves to `qemu:///session` | user edits rules (see "Rule edits" below) | yes |
| all | Locked inputs committed and pushed (K22): the decision-record amendments, the scout, the plan dir, `goal-packet.md`, both review reports | `git status` | **missing** (1 modified, 4 untracked paths) | user approves the commit; the controller commits and pushes | yes |
| all | Exactly one session owns the VM | user confirmation | unknown | user | yes |
| all | Claude Code ≥ 2.1.269; `disableAllHooks` unset; auto mode | `claude --version`; settings key names | available (2.1.308; unset; `defaultMode` auto) | — | no |
| all | zotero-mcp reachable; E2SM-RC v03.00 `XRWZU3SS`, E2SM common v07.00 `QW6VJ83M`, E2SM-KPM v03.00 `F82PYZVK` (PDF), E2AP v03.00 `WEE5IEXF`, 3GPP TS 28.552 V20.2.0 `5SZUBP6M`, 3GPP TS 37.340 V18.7.0 `E6VYJPXJ` | attachment paths resolved, text read | available | — | no |
| all | kongming on opus | this review ran | available (one rate-limit interruption, resumed) | — | no |
| P0 | VM `ubuntu24.04` running at `f7-rerun-green`; `fresh-install` present | `virsh -c qemu:///system domstate`; `vm-snapshot.sh list` | available (running; tree fresh-install → f7-rerun-green) | — | no |
| P0 | Fork heads equal `pins.conf` (Testbed, ns-3, oran-interface, e2sim); QP fork public, `master` = 47a35ca | `git ls-remote`; `gh repo view` | available | — | no |
| P0 | Parent repo public; `gh` authenticated | `gh repo view --json visibility`; `gh auth status` (no token printed) | available (PUBLIC; logged in) | — | no |
| P0–P8 | Upstream gerrit reachable (ric-app/ts, rc, kpimon-go, ric-plt/e2, xapp-frame-cpp, lib/rmr, rtmgr) | `git ls-remote` ref counts | available | — | no |
| P0 | Host tools: grpcurl, docker (podman shim), python3, tshark, virsh, gh | `command -v` | available | — | no |
| P7 | No deployed Influx token in the public trees | name/location checks only | available as baseline: the literal in `kpimon-go/control/control.go.patch:37` comes from NIST's upstream `v1.8.0` tag commit (public placeholder); the P7 gate checks the deployed token by count | — | no |

**Rule edits needed (K3).** Add allow rules for the exact forms the plan uses:
- `Bash(virsh -c qemu:///system domstate *)`, `…snapshot-current *`, `…snapshot-list *`, `…domblklist *`, `…dumpxml *`, `…snapshot-dumpxml *`;
- `Bash(scripts/vm/host-disk-watchdog.sh *)`, `Bash(scripts/gates/lint.sh*)`, `Bash(python3 scripts/*)`, `Bash(tools/rc-decode/*)`, `Bash(docker build *)` / `Bash(podman build *)`, `Bash(gh repo view *)`, `Bash(gh auth status*)`.

Under the 01:03 snapshot rule, replace the deny `Bash(*vm-snapshot.sh delete*)` with denies for the protected names only: `Bash(*vm-snapshot.sh delete fresh-install*)`, `Bash(*vm-snapshot.sh delete f7-rerun-green*)`, `Bash(*vm-snapshot.sh delete r3-green*)`. Keep `Bash(*snapshot-delete*)`, so raw virsh can never delete. If the broad deny stays, every allowed deletion becomes a T8 pause, which is safe but interrupts M9.

**Should decide before the long run:** none open.

**Deferred (allowed by the contract):** the outage fallback count (P3); a TS xApp crash on the stray ack (P5); the N5 match (P3); the R3 schedule (P7); the BLAS library (P7); kpimon's UE field names on the UL-on dump (P7, K7).

## Unresolved questions

None open for the user beyond the five must-provide items above.
