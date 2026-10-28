# Docs draft for P10 (A1 "Docs" bullet): README, deployment guide, architecture

Scope: phase-10 Amendment A1 "Docs" bullet (`phase-10-m9-unattended-run-from-fresh-install.md:68`), goal-packet In scope 8 (`goal-packet.md:17`). Uncommitted. Nothing under `scripts/`, `tools/`, `reference/` or `evidence/` touched; `git diff --quiet e0a6ac5 -- scripts tools <plan>/reference` exits 0 after the edits.

Pin sources used for fork claims: ns-3 `ba954440` (`scripts/pins.conf:10`), oran-interface `96efc40e` (:13), Testbed `c6d1434a` (:7). Read with `git show <pin>:<path>`; the submodule HEADs equal the pins.

## Changes

### README.md
1. Intro: agents now speak E2SM-RC too; rungs R0–R2, R3′ and M9 named; removed stale "The control path (RC, M8) is not part of this scope yet". Added **Scope** paragraph (QP fork / real-QP R3 deferred, AD unused).
2. Architecture bullets: one line on the control direction (rc gRPC :7777 → agent → ns-3 → ledger).
3. Prerequisites disk: "70 GB" scoped to M0–M7; M9 points to `m9-budget.md` (no numbers copied).
4. New "Reproduce M9 … with one command": the two commands, runner refusals, verdict path and fail-closed pass rule, one paragraph on R0, R1, R2, R3′, top-rung C1, substitution 4 condition. Stateful line with placeholders.
5. Gate table: rows i0, R0 (M8), R1, i2, R2, R3′.
6. Evidence: M9 root and `m9/<ts>/` contents.
7. Documents table descriptions updated.

### docs/deployment-guide-l-release.md
1. Intro: M9 and the manual rc / TS xApp loops added.
2. §3 new subsection "M9: the chain plus the closed-loop rungs": usage, step order, refusals, "revert yourself", `--no-snapshots`, budget/watchdog/stop paths, `--from/--to` → `notM9`, verdict fields; scope statement with deviations pointer.
3. §5 snapshot table: `n*` row.
4. §7 ns-3 flag table: `--handoverMode`, `--outageThreshold`, `--e2LedgerPath`, `--e2Pacing`, `--e2PacerPort`, `--e2StartTimeout`/`--e2GateTimeout`, `--simStartEpochMs`, `--enableUlTraffic`/`--ulTrafficPattern`.
5. §7 new "Send an rc control by hand" (lock-step via pacer schedule, free-run alternative) and "Drive the TS xApp by hand" (pod reset order, A1 threshold, stub table, injector, trigger). Both marked "unverified as a hand run".
No section renumbering (the guide's internal "section 5" / "section 8" references stay valid).

### docs/system-architecture-l-release.md
1. §2 component table: rows rc xApp, TS xApp, stub QP, pacer + R3′ predictor.
2. §3 stale IPC claims fixed: transport no longer "ns-3 to agent only"; `control`/`controlAck`/`step` no longer "reserved" (minor 1 and 2 described); emitter "never stalls" scoped to free pacing.
3. §4 Ready state: pointer to §8 for RC control requests.
4. **Stale §8 removed** ("RIC Control and M8 … nothing implements it"; "Pacing … run free"). New §8 "RC control path, pacing and the R3′ predictor" (agent, ns-3 D4 + hub + ledger, pacing opt-in, UL/DL PDCP SDU rows, R3′ predictor), each with its WHY. The timing-report rationale moved here.
5. §9 out of scope (was §8): QP and AD (deferred, adapter), deviations pointer, other scenarios (S3), stale "Scenario and radio changes" line rewritten.
6. §10 known gaps (was §9), unchanged content.
7. New §11 "Run your own experiment": `agents-ns3-run.sh:40`, globals only in `scenario-zero.cc`, N5 key digit-only limit, pacing opt-in, QP/AD adapter, deviations.

## Commands documented and their sources

| Command (as documented) | Source |
|---|---|
| `scripts/vm/vm-snapshot.sh revert fresh-install` | `phase-10-…md:17,86` (the runner never reverts: :86); existing README:31 |
| `scripts/run-to-m9.sh --harness-sha <pushed SHA> --run-prefix n --no-snapshots` | `scripts/run-to-m9.sh:2,35-45`; `phase-10-…md:18,87` (M9 ran with F `e0a6ac5ee0b4…`) |
| Runner refusals (prefix f/l, existing prefix, worktree ≠ SHA, untracked, no budget) | `run-to-m9.sh:47-60` |
| Step order, single vs c1 `--reference`, substitution 4 | `run-to-m9.sh:4-9,63-90` |
| `--no-snapshots` (no snapshot incl. M7; reboot per boundary; M0 probe pair kept) | `run-to-m9.sh:22-24,170-178`; `gate-m0-host.sh:21-23` |
| Stop paths (watchdog trip, heartbeat stale, wall deadline) | `run-to-m9.sh:11-15,133-138` |
| Verdict path and fields (`pass`, `problems`, `exactStepSet`, `notM9`, `highestGreenRung`, `equalsReference`, `minHostFreeGb`, `watchdogAlive`) | `run-to-m9.sh:16-21,97-110`; `scripts/m9-verdict.py:3-14,83-89` |
| Evidence root for every M9 step | `run-to-m9.sh:28` |
| `export KUBECONFIG=$HOME/.kube/config` | `scripts/gates/bringup.sh:30-38` (`kc`) |
| `RC_EP=$(kubectl -n ricxapp get svc service-ricxapp-rc-grpc-server -o jsonpath='{.spec.clusterIP}'):7777` | `scripts/gates/rc-lib.sh:74-79` |
| grpcurl at `~/grpcurl-1.9.1/grpcurl` | `rc-lib.sh:36-37,59-71`; `rc-send.sh:11` |
| Harness clone `~/harness` on the VM | `scripts/vm/vm-exec.sh:47` |
| Pacer schedule JSON with `rc-send.sh … 2 6 0000000303` at step 20 | `scripts/gates/gate-q8-rc-smoke.sh:67-71` (schedule), `:11` (meaning) |
| `python3 -I ~/harness/scripts/gates/pacer.py --port 38499 --out ./pacer --t-ctl 30 --schedule sched.json` | `gate-q8-rc-smoke.sh:26,76`; `pacer.py:367-372` |
| ns-3 lock-step CLI `--nMmWaveEnbNodes=2 --handoverMode=NoAuto --simTime=10 --RngRun=1 --outageThreshold=-1000 --e2AgentHost=127.0.0.1 --e2TraceDir=… --e2Pacing=lockstep --e2PacerPort=38499 --e2GateTimeout=10` | `gate-q8-rc-smoke.sh:27,79-80` |
| Agents `--nodes enb:1,gnb:2,gnb:3` | `gate-q8-rc-smoke.sh:24`; `gate-r0-rc-scripted.sh:59` |
| `rc-send.sh <endpoint> <viaNodeId> <imsi> <key> [ackReq]`; exit 0 = queued | `scripts/gates/rc-send.sh:2-7` |
| Ledger fields and header line | `gate-q8-rc-smoke.sh:113-119`; ledger default path `scenario-zero.cc@ba954440:298-301` |
| ACK Format 1 / FAILURE `control-failed-to-execute` | `gate-q8-rc-smoke.sh:11-12,117-118`; `rc-control.hpp@c6d1434a:1-15` |
| Pod reset order (TS xApp + stub, appmgr, a1mediator, rtmgr) | `scripts/gates/ts-lib.sh:281-305`; reasons `gate-r2-ts-stub-qp.sh:15-18`, `ts-lib.sh:16-18,31-35`, `rc-lib.sh:19-20` |
| `A1=http://$(kubectl -n ricplt get svc service-ricplt-a1mediator-http …):10000/A1-P/v2` | `ts-lib.sh:73,379` |
| `curl -s -X PUT -H 'Content-Type: application/json' -d '{"threshold": 10}' "$A1/policytypes/20008/policies/manual-1"` | `ts-lib.sh:416-425`; fresh id `:413-414`; starts at 0 `:52`; log line `:399`; value 10 = `scripts/gates/rung-config.json` `a1_threshold` |
| `STUB_IP=…` (kubectl jsonpath + awk on `ricxapp-stubqp-`) | derived from `ts-lib.sh:446` (`_stub_url`), `STUB_NAME` `:60`; **my construction, not copied** |
| `curl -s http://$STUB_IP:8080/health`; `curl -sf -X PUT --data-binary @table.json …/table` | `ts-lib.sh:448-454`; format `tools/rmr-peer/stub-qp-rmr-peer.py:4-14` |
| Injector (described, not copied) | `ts-lib.sh:458-470`, ports `:63-64` |
| `bash ~/harness/scripts/gates/send-rmr.sh 38510 anomaly 6` | `scripts/gates/send-rmr.sh:2,11`; schedule form `scripts/gates/r2-checks.py:70`; port `ts-lib.sh:64` |
| TS xApp → rc endpoint `service-ricxapp-rc-grpc-server.ricxapp:7777` | `ts-lib.sh:55` |
| R3′ prepare hook replaces the table load | `scripts/gates/r3p-prepare.py:2-15`; `gate-r3p-ts-predictor.sh:4-7,203-216` |
| ns-3 flag defaults added to the table | `scenario-zero.cc@ba954440:253-256,264-268,298-334` |

Bash snippets in the new guide subsections pass `bash -n`; the heredoc schedule renders valid JSON (checked with a dummy endpoint).

## Key claims and evidence class

| Claim | Evidence |
|---|---|
| Agent RC answers and rejects; no wall-clock timer; ctlId | source: `rc-control.hpp@c6d1434a:1-15` |
| Codec = rc's pinned commit, E2SM-RC v2.0 | source: `rc-lib.sh:34-35`; intent: `goal-packet.md:10` |
| N5 bytes `%08X%02X`, eNB keeps `reqpart`, TS xApp reads the hex text as its cell key | source: `e2ap-builders.cpp@c6d1434a:56-61,97-103`; `gate-s0-free-control.sh:12-14` |
| N5 digits-only within IDs ≤ 9; ≥ 10 untested | record: `plans/reports/brainstorm-261022-1739-…:109`, `brainstorm-261027-2241-…:116`; rung node sets `enb:1,gnb:2,gnb:3` |
| Hub order (imsi, viaNodeId, targetCellId, ctlId), d = 0, free vs lockstep, exit 5 | source: `e2-control-hub.h@96efc40e:49-77` |
| D4 `ApplyExternalHandover` prechecks, no RNG, no own event | source: `lte-enb-rrc.h@ba954440:1636-1678` |
| Globals declared only in scenario-zero.cc and mapped to hub/helper attributes | source: `scenario-zero.cc@ba954440:298-323,419-432`; `git grep` at ba954440 finds them only in that file |
| `agents-ns3-run.sh:40` hard-codes `*-scenario-zero-*`; S0/S1 same | source: `agents-ns3-run.sh:40`; `gate-s0-free-control.sh:57,65`; `gate-s1-pacer-lockstep.sh:86,93` |
| IPC minor 1/2 contents | schema: `ns3-e2-ipc.v1.schema.json@c6d1434a` description |
| N4 rows INTEGER kbit, `_Filter` legacy, P9 attribution; UL flag default off, no RandomVariable, flag-off traces equal | source: `metric-map.v1.json@c6d1434a:56-57`; `scenario-zero.cc@ba954440:46-48,325-334`; `gate-n4-ul-metric.sh:3-8` |
| R3′ predictor formula, window, eNB excluded, N6 certifies, Influx inside pod, no secret | source: `r3p-predictor.py:2-16`; `r3p-scenario.json` (`formula`, `window`, `excludedNodes`, `_comment`); `r3p-prepare.py:2-15` |
| Stub QP answers 30002 | source: `stub-qp-rmr-peer.py:4-8` |
| QP/AD need an adapter | NIST: `Near-Real-Time-RIC/README.md@c6d1434a:84,89,96` |
| Scope (QP fork, real-QP R3 deferred) | intent: `goal-packet.md:19`; `m9-run-report-template.md:44` (S1) |
| Persistence predictor is not load balancing | record: `m9-run-report-template.md:60` (interpretation 2) |

## Placeholders left for the controller

| Placeholder | File:line | Fill with |
|---|---|---|
| `<M9-RUN-TS>` | `README.md:51` | M9 evidence timestamp. Resume card (`plan.md:26`) records the in-flight run as `evidence/m9/20261028T092148Z`; insert only after the run ends. |
| `<M9-RESULT>` | `README.md:51` | verdict `pass` / `highestGreenRung` / `minHostFreeGb` from that `verdict.json` |
| `<M9-RUN-REPORT>` | `README.md:51`; `docs/deployment-guide-l-release.md:85`; `docs/system-architecture-l-release.md:181,203` | path of `plans/reports/run-report-<ts>-GH-1-m8-m9-deviations.md` (phase-10 Files, `phase-10-…md:11`) |

## Validation run

- Every repo path named in the three docs exists, except `scripts/gates/r3p-substitution4.json`, which exists only under substitution 4 and is described conditionally.
- Relative markdown links in the three files: all resolve.
- Bare "TS" scan: no hits outside "TS xApp", "3GPP TS <n>", code identifiers and the `<M9-RUN-TS>` placeholder.
- `bash -n` on the extracted new snippets: ok. Schedule heredoc → valid JSON.
- Frozen trees: `git diff --quiet e0a6ac5… -- scripts tools <plan>/reference` → 0.
- Not done (needs the finished run): "every command verified against the M9 log" (A1 Docs bullet). Compare the two M9 commands and the verdict field names against the runner log and `verdict.json` once the run exits.

## Docs impact

Evergreen surfaces now describe the shipped RC path, pacing, N4 rows and R3′, and the stale "not implemented" claims (architecture §3 and §8, README intro) are gone. The manual loops are labelled unverified as hand runs. Stateful values are kept to one labelled README line with placeholders.

## Unresolved questions

1. The task text shows `--harness-sha <F>`. I wrote `<pushed SHA>` to match the README's existing M0–M7 block. The M9 F value is in the plan records. Switch to `<F>` or the literal SHA if you prefer.
2. Should the README also list the M9 run's wall time or step durations? I left them out (stateful); the run report owns them.
3. The manual TS xApp loop leaves the pod reset and the injector start as pointers to `ts-lib.sh` functions, because no standalone script exists. Is a pointer enough, or do you want those commands copied in (long, and duplicated)?

Status: DONE_WITH_CONCERNS
Summary: The three docs are drafted and uncommitted: README M9 section and scope, deployment-guide M9 usage and manual rc / TS xApp loops, architecture stale §3 and §8 fixed plus the RC/pacing/N4/R3′ section and "Run your own experiment". Each claim is cited above.
Concerns/Blockers: The placeholders `<M9-RUN-TS>`, `<M9-RESULT>` and `<M9-RUN-REPORT>` need the finished run. The A1 "verified against the M9 log" check is still pending. The manual loops are unverified as hand runs.
