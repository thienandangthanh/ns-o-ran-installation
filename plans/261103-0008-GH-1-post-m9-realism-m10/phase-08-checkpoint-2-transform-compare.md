# P08 (MC): checkpoint 2, transform-compare against M9, negative fixtures, tag; then Stop A′

**Start state:** P07 pins; `f7-rerun-green`. **Snapshot at exit:** none (the tag is the checkpoint).

## Context
After T-A, only ipc (the digested sample lines) and traces stay literal. Everything else must equal the M9 files under plan R-2's enumerated transforms (Amendment 1, F1 option a). The compare reads the promoted raw M9 files (`reference/m9-r3p-raw/`, P04) and the M9 digests (`plans/261023-0009-GH-1-m8-m9-paced-rungs-and-m9/reference/r3p/equal/`). The transformed fields sit at these places:
- `scripts/gates/r3p-scenario.json:5,17,27`;
- `r3p-schedule.json:2,10,17,33,40,48,52,58,65`;
- the M9 live1 `r3p/predictor-records.jsonl` (`answer` keys, `target`).

## Requirements (contract, A1)
- **AC8b**, at δ = 0 and before T-C:
  - ipc and traces literally equal to M9;
  - predictor records, scenario and schedule = T(M9 files): the N5 → NCI key, `via` target → source, `scenarioSha256` recomputed, the two P1 strings replaced, `ueId` per AC14b. Every other byte, including every predictor number, is literal;
  - the ledger and `extra` equal after transforms on the enumerated fields only (viaNodeId, the RC UE ID, the RC action and target encoding in rc-multiset, meid);
  - a negative fixture shows a mutated M9 file fails;
  - the passing commit is tagged.
- **Stop A′:** the I-1 message mapping is shown; budget re-projected.

## Design
- `scripts/gates/reference-transform-compare.py RUN M9RAW M9REF`:
  1. Digest-compare ipc and traces (literal).
  2. Apply T to the M9 scenario, schedule and predictor records. T is the pure function of R-2, written once in `scripts/gates/m9-transform.py` and used both to rewrite the committed harness files in P06 and here. Then require byte equality with the run's files.
  3. Apply the enumerated ledger / rc-multiset / meid transforms to the M9 side and require byte equality. The RC UE-ID transform reads only `reference/identity-map-cp1.json` (plan R-8; its sha256 is verified first; a mismatch fails). Input `{…, "imsi": N, …}` → output `{…, "ueId": {"type": "en-gNB-UEID", "mEnbUeX2apId": map.ues[N].mEnbUeX2apId, "globalEnbId": map.globalEnbId}, …}`, with `imsi` removed and nothing else touched. kpm-headers and collet-start-time are compared literally (no enumerated field touches them).
  4. Any byte outside the enumerated fields that differs fails and names the field.
- **Negative fixtures** (`scripts/gates/fixtures/transform-compare/`):
  - (a) ledger `targetCell` changed → fail;
  - (b) rc-multiset `step` changed → fail;
  - (c) one trace byte changed → fail;
  - (d) identity transform on the untouched M9 raw → pass;
  - (e) one predictor `answer` number changed → fail;
  - (f) a schedule `step` changed → fail;
  - (g) a scenario key left in N5 form → fail;
  - (h) an rc-multiset `ueId.mEnbUeX2apId` that differs from `identity-map-cp1.json` for that IMSI → fail;
  - (i) an rc-multiset `ueId.globalEnbId` with a wrong PLMN or macro eNB ID → fail.

## Files
- Create: `scripts/gates/reference-transform-compare.py`, `scripts/gates/m9-transform.py`, `scripts/gates/fixtures/transform-compare/` (fixtures a–i); a `--reference-transform` mode in `scripts/gates/ts-rung-lib.sh` (next to `rung_reference`, `:207-221`), used by `gate-r3p-ts-predictor.sh`.
- Create (Markdown): `docs/journals/<date>-m10-stop-a-prime.md` (including the I-1 mapping table).

## Steps
1. Script and fixtures; host-only self-test.
2. R3′ C1 at δ = 0 at the P07 pins with `--reference-transform`.
2b. **G2 (Stop A, `plans/reports/decisions-261104-0214-GH-1-m10-stop-a-rulings.md`):** R3′ C1 at δ = 150 and δ = 500 at the P07 pins with `--reference-transform` against the cp1 δ references (`reference/r3p-d150`, `reference/r3p-d500`, raw files promoted in P05 step 0). d500 is the most δ-sensitive rung. These give AC16 its checkpoint-2 baseline for the δ rungs.
3. On green, tag `m10-cp2` (harness and forks) and push.
4. Budget re-projection (T′ both bases, /mnt/data, s10 and T-C rebuild costs); Stop A′ packet → `PAUSE A′`.

## Validation
- `python3 scripts/gates/reference-transform-compare.py --selftest`: fixtures a, b, c, e, f, g, h, i fail and d passes.
- R3′ C1 verdict:
  - `liveRunsEqual`, `replayEqual` and `rngRun2Differs` are true;
  - `transformEqualsM9: true`;
  - `transformedFields` equals the R-2 list exactly;
  - `literalComponents ⊇ {ipc, traces}`.
- G2: the d150 and d500 transform-compare verdicts are green with the same predicates as δ = 0 (`transformEqualsM9` read against the cp1 δ reference).
- `git rev-parse m10-cp2` equals the verdict's harness SHA.

## Standards ledger (stub)
| Decision | Document, section | Zotero | Read |
|---|---|---|---|
| None new; each transform traces to a P06/P06b/P07 ledger row. | — | — | — |

## Risks
- kpm-headers change through the rebuilt kpimon or agent (Medium/Low). That component has no enumerated transform, so it fails loudly and goes to the Failure Protocol; if the cause is a legitimate T-A field, it is a T3 (contract) question, not a silent transform.
- T drifts between the file rewrite and the compare (Low). There is a single implementation, `m9-transform.py`.

## Rollback
Tags are never moved. A red C1 is re-run only as a full fresh set after the cause is recorded and a change committed.

## Hand-offs from the P07 exit review (kongming-261105-0536)
Do these first, in this order, before the cp2 chain. Every new or changed check gets its ledger row before code.
1. **Host disk-floor watchdog for dev chains.** Reuse `scripts/vm/host-disk-watchdog.sh` (it already stops the gate unit and shuts the VM down) from `vm-exec.sh` or the chain driver, with `--min-gb 22` (the 20 GiB floor plus a 2 GiB margin, because qcow2 growth continues briefly after the kill) and a 15–30 s interval. A trip fails the gate and enters the Failure Protocol. Add a guest-side guard too: agent and xApp `docker build` under `timeout`, and an abort when the guest root passes 85 %, so kubelet DiskPressure never evicts the RIC.
2. **Evidence of red runs survives.**
   - `scrub-evidence.sh` reads the token from a source that survives an Influx pod eviction (the k8s secret or the installer's token file), still failing closed.
   - `fact()` (`scripts/gates/lib.sh:79`) never emits `{"value":}` for an empty input. Both failed P07 runs (`r1/20261104T175831Z`, `r2/20261104T182917Z`) lost `verdict.json` that way.
   - The `cat … || echo null` call sites (`gate-r1-rc-multi-control.sh:257,321`, `gate-r2-ts-stub-qp.sh:151`) also treat an empty file as missing.
3. **One harness SHA and one pin set** for the whole chain from `f7-rerun-green`: M2–M7, I0, Q8, R0, R1 single, I2, R2 C1, then the three R3′ C1 runs (δ = 0, 150, 500) with `--reference-transform`. `m10-cp2` is tagged at that SHA. This also makes P07's mixed pass set uniform.
4. **One read-only Codex review** over harness `519d2bb..HEAD` plus Testbed `ff704ab..36dbcc3` before the cp2 tag. Never call `adversarial-review --help`.
5. **The TS xApp's Influx test fixture.** A host test, run in the TS image build or `lint.sh`, against InfluxDB 2.7 loaded from an archived `influx-kpimon.csv` (mixed integer and float UeMetrics fields): a present tag passes, an absent tag fails. Add a parser case built from the real HTTP 400 schema-collision body.
6. **Port reservation, second conjunct (row 129 amended first):** no socket holds a local port in 38470–38499 when the check runs (`ss -Htan`, source port in range).
7. **D-06b-1 stays in P10.** If the user rules R-4 "as written" at Stop A′, the kpimon node tag is bundled with it there.
- **No VM `docker image prune` before the user ratifies the prune rule at Stop A′.**
- **Failure Protocol, literally:** each red gets one kongming-guided fix before the fix is made, and a second red is PAUSE T6, as `plan.md` "Cross-cutting rules" says.

## Work record

**Hand-offs from the P07 exit review, done before the cp2 chain (2026-11-05).** Ledger rows 130–136 were committed first (65542db), then the code.
1. **Host disk watchdog** (row 130; 94d0225, then the review fix 4111713). `vm-exec.sh` runs `host-disk-watchdog.sh --min-gb 22 --interval 20` around every gate and writes `host-disk-watchdog.json` into the run dir. A trip exits 125. The guest-side guard (row 131; fdf2a00, then the review fix 1a4e528): `nist_run` stops its command when the guest root passes 85 %. Every agent and xApp installer already runs through `nist_run` (`agents.sh:273`, `kpimon.sh:208`, `bringup.sh:358,477`, `gate-m1-ric-up.sh:49`), so all of them inherit both the guard and their time bound.
2. **Red-run evidence** (rows 132 and 133; fdf2a00, a422192). `fact()` writes an empty value as null and other non-JSON text as a string. The `cat … || echo null` sites (`gate-r1-rc-multi-control.sh:257,321`, `gate-r2-ts-stub-qp.sh:151`) all pass through `fact()`, so an empty file now gives null there too. The scrub reads the InfluxDB admin token from the pod spec, or from the secret its `secretKeyRef` names. An evicted pod therefore no longer blocks the export. All of its fail-closed rules stay. It was tested on the VM: one file redacted, 45 secrets known, the token absent afterwards, rc 0. The lint fakes cover the secret path, a literal value, an evicted pod and a token under 20 characters.
3. **One harness SHA for the whole chain:** see the chain entry below.
4. **Codex review** (two read-only runs; see the triage below).
5. **The TS xApp Influx test** (row 134; c8d3110, Testbed 554d6d6, pin 58fd23d and 92de0ec). The fixture `scripts/gates/fixtures/ts-influx-mixed/ue-metrics.lp` holds 24 UeMetrics points cut from `r2/20261104T190033Z` live1's `influx-kpimon.csv`, with integer and float fields. `ts-influx-query-selftest.py` loads it into a throwaway `influxdb:2.7` container. The query is the one the pinned TS patch builds, extracted from the patch text. A present tag gave HTTP 200 and one `_time` record; an absent tag gave HTTP 200 and none. The pre-fix query from Testbed faeeb34 gave HTTP 400 `{"code":"invalid","message":"runtime error @1:153-1:164: limit: schema collision: cannot group integer and float types together"}`. That body became the csv() case `http-400-schema-collision` in `en_gnb_ue_id_test.cpp.patch`. All 34 cases passed on the host (g++ -std=c++17).
6. **Port reservation, second conjunct** (row 135; fdf2a00). `agents_reserve_ports` also fails when a socket other than TIME_WAIT holds a local port in 38470–38499. On the VM, 304 sockets were checked and none was held.
7. D-06b-1 stays in P10, and there was no VM `docker image prune`.

**Transform compare** (row 136; abc2a74, then the review fix dc0cf0b). `m9-transform.py` is T, the one implementation of R-2. `reference-transform-compare.py` is the compare, and `gate-r3p-ts-predictor.sh --reference-transform M9RAW M9REF` calls it through `rung_reference_transform`. Before any code, T was checked on the promoted M9 raw files: T(scenario), T(schedule) and T(stage-A) equal the committed harness files byte for byte; T(predictor records), T(ledger) and T(rc-multiset) equal the P07 R3′ C1 run `r3p/20261104T194024Z` live1. The same holds for T of the cp1 δ 150 and δ 500 raw scenario files. As a dry run, the compare on `r3p/20261104T194024Z` gives `transformEqualsM9: true`. It reports 17 transformed fields and `fieldsWithoutOccurrence: ["meid"]`, and ipc, traces, kpm-headers and collet-start-time are literal-equal. The self-test runs in `lint.sh`, and in the gate as `r3p_transform_compare_self_test`: fixtures a, b, c and e–j fail, each naming its file and field; d passes; an identity map off its SHA256SUMS is refused; and a T that rewrites a field outside R-2 is caught.
- [I] No compared M9 file carries a meid: rc-multiset has none, and kpm-headers and collet-start-time are literal-equal. So the meid rewrite has nothing to touch, and the compare lists it in `fieldsWithoutOccurrence` instead of `transformedFields`. A meid that occurs and is not rewritten fails. Row 136 was amended before code (07b82bd). This is listed for Stop A′.
- Fixture j was added after the Codex review: a malformed N5 suffix in an M9 rc-multiset `targetKey`, with its checksum re-written. Its amendment is recorded under the ledger's rows 130, 131 and 136 (4d3aef5).

**Codex review (read-only).** Run 1 covered harness `519d2bb..abc2a74` and Testbed `ff704ab..554d6d6` (`adversarial-review --base 519d2bb`, about 25 min). Its verdict was needs-attention, with three findings, each verified against the code and accepted:
1. High: a watchdog trip during a gate's finish could still end green. `vm-exec.sh` killed the watchdog and wrote `tripped: false` without checking. Accepted. The watchdog now writes a latch before it stops anything, and `vm-exec.sh` asks it for one last check (`wd_finish`, `vm-common.sh`) and waits instead of killing it. The self-test gained a trip during the finish (exit 125) and a clean finish. Both cases fail when the old kill is put back.
2. Medium: `nist_run`'s delayed-KILL subshell outlived it. Accepted. GNU `timeout --kill-after` arms the KILL on an external TERM too; this was checked on the host (a command ignoring TERM was killed 3 s after it). The subshell is gone. The self-test asserts that no background job survives, and fails with the subshell back.
3. Medium: T accepted an M9 `targetKey` with a malformed N5 suffix. Accepted. T checks each scenario key against `%08X%02X` of its cellId, refuses a `targetKey` outside the scenario's cells, and leaves no stray 10-hex key. Fixture j covers this.

Run 2 was a verification of those fixes (`--base abc2a74`, about 15 min). Its verdict was needs-attention, with four findings, each verified and accepted. The ledger was amended again before the code (2df76db); the fixes are ea8b681, 791e405 and 749fbd0.
1. High: a `die` during a latched trip (scrub, copy or bootstrap failure) exited 1 without the trip record. Accepted. Every exit after the watchdog starts now passes `wd_on_exit`. Writing its self-test case exposed one more bug: inside an EXIT trap, the watchdog's closing TERM killed the runner with 143. The finaliser now ignores TERM while it completes the trip. The case passes with exit 125 and the trip recorded.
2. High: `wd_finish` waited with no bound, and `virsh domstate` had no timeout. Accepted. `vm_state` is bounded at 10 s, `wait_state` runs to a wall-clock deadline, `wd_finish` is bounded (`WD_FINISH_TIMEOUT_S` 600 s plus the cancel budget), and an unwritable stop request fails the finish. The cases for a hung `virsh` and an unwritable stop request were mutation-checked: without the bound, the finish took 257 s; without the early return, 24 s. Both cases fail in that state.
3. Medium: the stdin producer `sleep` outlived `nist_run`, so the run-1 amendment of row 131 overstated. Accepted. `nist_run` now owns it and kills and reaps it on every return. The self-test checks all three paths by the producer's exact command line, and fails when the cleanup line is removed.
4. Medium: an M9 file with one key already in NCI form passed T unchanged. Accepted. T refuses any 10-hex key other than the scenario's N5 keys before substitution. Fixtures k and l (a partially converted schedule and stage-A classification) fail.
After these fixes, T still reproduces the committed harness files from both the M9 raw files and the cp1 δ 150/500 raw files, and the dry-run compare on `r3p/20261104T194024Z` is still `transformEqualsM9: true`. Lint passes.

Run 3 was a narrow check of the run-2 fixes (`--base 2df76db`, about 3 min). It ran in parallel with a chain started at 749fbd0. Its verdict was needs-attention, with one finding, verified and accepted:
- High: on its abort paths (the bound, an unwritable stop request), `wd_finish` killed only the watchdog shell, so its ssh, virsh and timeout children were orphaned. The verdict was never at risk, since those paths already fail with 125, but it is a process leak. GNU `timeout` makes its own process group, so a group kill would miss those children. The fix (668d1ef, after the row 130 amendment 66d1d29): the watchdog starts as a session leader (`wd_start`), and every stop path ends its whole session with TERM, then KILL after 5 s. The guest shutdown call gets `--kill-after`. The self-test checks that the session is empty after cases 3–7. With the old single-PID kill put back, cases 6 and 7 fail, naming the processes left behind.
- The chain started at 749fbd0 was stopped about three minutes into M2: the VM unit first, then the driver and `vm-exec.sh` (KILL, so its TERM trap could not write a false trip record), then its watchdog. No evidence was exported. The VM was reverted to f7-rerun-green again (`--pending` checked first, no orphan overlays), and the asn1-indep tarball was copied again (`sha256sum -c` OK).
- No fourth Codex run before the chain at first. The user then ruled (2026-11-05 10:38 KST) "don't skip a fourth Codex review", so every fix made for a Codex finding now gets its own follow-up Codex review (runs 4–7 below).

**The cp2 chain** runs at harness 668d1ef with pins Testbed 554d6d6, ns-3 ea6e46f6, oran-interface 53253fe and e2sim e2705816, from f7-rerun-green, in the order of the driver: M2, M3, M4, M5, M6, M7, I0, Q8, R0 single, R1 single, I2, R2 C1, R3′ calibrate, R3′ dryrun stage b, R3′ C1 at δ 0, 150 and 500 with `--reference-transform`, e2i, the δ seam smoke, and R1 C1. It covers P07's whole pass set and the three transform-compare runs.

**The cp2 chain at 668d1ef: superseded, with P08 red #1 at step 15.**
- **Steps 0–14** (M2 through R3′ C1 at δ 0) passed. The δ 0 run is `r3p/20261105T005919Z`, which has `transformEqualsM9: true`.
- **Step 15** (R3′ C1 at δ 150, `r3p/20261105T012217Z`) went red at the runner, not at the gate:
  - **The edit:** while that step's runner was polling, I rewrote `scripts/vm/vm-exec.sh` in this worktree for the Codex run 4 fix. Bash resumed the edited file at a stale byte offset, which gave "ns-3: command not found" (a fragment of a comment) and then "disk_end: unbound variable", and the runner exited 1.
  - **The VM side:** the gate exited 0 and its verdict passes, and the compare has `transformEqualsM9: true`, 17 fields, `meid` without occurrence and no problems. The copy matches the VM (852 files).
  - **What is missing:** `host-disk.tsv` and `host-disk-watchdog.json`. The disk floor held (minimum 54 GiB, no trip file).
  - **Classification:** following kongming-261105-1050, this counts as P08 red #1, so the next red is PAUSE T6. The classification is disclosed for the user at Stop A′.
- **Evidence:** the run dir is kept as incident evidence and is not counted. No missing record was created after the fact.
  - The 16 run dirs at 668d1ef (15 superseded greens and the step 15 incident) have their verdict layer and an `evidence-sha256.txt` committed.
  - Their 3,969 raw files and their watchdog dirs are archived as `plans-evidence-raw-m10-p08a-20261105.tar.zst` (103 MB) with its `.list0`, both in that folder's `SHA256SUMS` and verified.
  - The driver as run, its step log and the step logs are in `evidence/cp2-chain/668d1ef/`.
- **The red's guided fix** (ledger chain procedure note, 813e9c9). This is a procedure change only, with no harness change:
  - The driver now runs every step's host side from a frozen, locked, detached worktree of the chain SHA on /home, with read-only `scripts/`. It checks HEAD and clean tracked files before every step.
  - After every exit 0 it cross-checks the run dir (fresh `.last-<gate>`, `exit_code` 0, `host-disk.tsv`, `host-disk-watchdog.json` with `tripped: false`, a passing `verdict.json`).
  - Its body is parsed whole before it runs.
  - The cross-check was validated offline: it passes the 15 green dirs and fails step 15 with "no host-disk.tsv".
  - The driver is `evidence/cp2-chain/p08-gate-chain.sh`.

**Codex runs 4–7** were read-only follow-up reviews, one per fix. Each finding was verified and accepted, and each amendment of ledger row 130 was committed before its code.
- **Run 4** (`--base 749fbd0`, the 668d1ef fix) found two high findings:
  - an outside or trip TERM skipped the finaliser: it recorded a trip that never happened, wrote the record before the trip record was complete, and left the watchdog session running;
  - the traps were installed only after the start's 0.2 s wait.
  - The fix is 33b4992: `wd_arm` installs the traps first, every exit goes through `wd_on_exit`, and `wd_start` polls for the session. Self-test cases 8–10 were added, and their mutations fail.
- **Run 5** (`--base 1bd18bd`, 33b4992) found three findings:
  - a TERM between the launch and `WD_PID=$!`;
  - `wd_end` marked the run finalised before writing its record;
  - a session id was signalled after the reap.
  - The fix is 293957f: TERM is held across the launch and the end record, and the session is swept once when the watchdog is seen gone and is then forgotten. Cases 11–14 were added, and their mutations fail. One mutation run leaked a watchdog on purpose, and I stopped it. My stop pattern also matched my own tool shell, which ended that shell and nothing else.
- **Run 6** (`--base b4109d2`, 293957f) found one high finding: `wd_end` restored the TERM action before `exit 125`. The fix is 0d32a88: a trip exits with TERM still held. Case 15 was added and fails against 293957f.
- **Run 7** (`--base 20c653d`, 0d32a88) returned approve, with no findings.
- Kongming-261105-1050 also reviewed 293957f and found no verdict-affecting defect. It named the same `wd_end` window that run 6 found.

**The cp2 chain at dd27868: green, 20/20 (2026-11-05 02:21–07:06 UTC).**
- **Setup:** the VM was reverted to f7-rerun-green. The harness is dd27868, whose `scripts/` are identical to 0d32a88, and the pins are unchanged. Every step ran from the frozen worktree with the hardened driver. The route was `systemd-run --user --wait` (unit `p08-cp2-dd27868`, KillMode=mixed). /home had 79 GiB free at launch, against kongming's 80 GiB rule of thumb. The old overlay had been confirmed unlinked. The minimum /home was 55 GiB, and no watchdog tripped.
- **Result:** every step exited 0 and passed the run-dir cross-check. The steps were M2, M3, M4, M5, M6, M7, I0, Q8, R0 single, R1 single, I2, R2 C1, R3′ calibrate, R3′ dryrun stage b, R3′ C1 at δ 0 (`r3p/20261105T052524Z`), δ 150 (`r3p/20261105T054823Z`) and δ 500 (`r3p/20261105T061121Z`), e2i, the δ seam smoke and R1 C1. The step log is `evidence/cp2-chain/dd27868/p08-gate-chain.tsv`.
- **Validation:**
  - `reference-transform-compare.py --selftest` is ok: fixtures a–c and e–l fail, and d passes.
  - All three R3′ C1 verdicts pass at harness dd27868. Each has `liveRunsEqual`, `replayEqual`, `rngRun2Differs` and `transformEqualsM9` true.
  - Each verdict's `transformedFields` holds the same 17 fields, with `fieldsWithoutOccurrence: ["meid"]`. The compare itself requires these two lists together to equal R-2's list. `literalComponents` is ipc, traces, kpm-headers and collet-start-time.
  - G2 holds: δ 150 and δ 500 were read against the cp1 δ references.
- **Tag:** `m10-cp2` is annotated at harness dd27868 (`git rev-parse m10-cp2^{commit}` = the verdicts' harness SHA). The four forks carry `m10-cp2` at their pins: Testbed 554d6d6, ns-3 ea6e46f, oran-interface 53253fe and e2sim e270581. All five were pushed.
- **Evidence:** all 20 run dirs have their verdict layer and an `evidence-sha256.txt` committed (7,293 files hashed). The raw files (5,682, including the watchdog dirs) are archived as `plans-evidence-raw-m10-p08b-20261105.tar.zst` (138 MB) with its `.list0`, and `SHA256SUMS` was verified.

