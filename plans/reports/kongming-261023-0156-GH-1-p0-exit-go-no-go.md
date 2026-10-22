# P0 exit go/no-go: M8–M9 plan 261023-0009 (kongming, 2026-10-23 ~02:10 KST)

Runtime: Claude Code, model opus (per user CLAUDE.md). This is advisory only and never counts as user approval. Verified at harness `e336af4`, which is pushed to `origin/migrate-l-release-NIST-1-8-0`. Fork heads equal `pins.conf` (checked with `git ls-remote`). VM `running`, current snapshot `f7-rerun-green`, `/home` 76 G free.

## TL;DR
**GO for P1, once four items are done first.** None needs a user decision, and together they take about 1 h:
- (a) Fix the stale resume card.
- (b) Correct the wrong NR-CGI note in `implementation-notes.html`.
- (c) Land one harness commit: gates must stop reusing stale ns-3/agent builds, and ns-3 traces must stay out of git.
- (d) Fix V1's comparison rule in advance and back it with two reference runs at the P0 pins.

The refused `delete r3-green` probe is not T8 under the locked contract's definition. plan.md's own wording does say it is T8, though. Record it, and let the user rule on it at Stop A.

## 1. P0 deliverables vs the phase file and its binding amendments

| Item | Verdict | Evidence / gap |
|---|---|---|
| K24 regex + self-test | ok | `vm-common.sh:63` `gate_id`, used at `vm-exec.sh:29`. `lint.sh:22-27` prints `m5 r0 s1 q7`. Nit: a name that does not match passes through unchanged (sed), so it fails silently as before. |
| Protected snapshots + V7 | ok | `vm-common.sh:13` and the `is_protected` helper. `vm-snapshot.sh` delete refuses before any virsh call; `check-protected` works. |
| K1 / step 5 runner | ok | `run-to-m9.sh` refuses `f`/`l` and existing prefixes (`:41-47`). `--no-snapshots` creates no snapshot, M7 included (`:123-132`). The m0-probe/branch pair is noted. |
| K15 watchdog + V3 | ok | `--min-gb`, default 25. It stops `gate-*`, shuts down gracefully and records `minHostFreeGb`. Untested: the runner-kill path (`--runner-pid`). The runner also cannot pass `--min-gb` (`run-to-m9.sh:120`), so that path cannot be tested without filling the disk. Fix by P9. |
| K2 projection | ok | Formula and table match K2; the −12 GB result is reported for Stop A. Gap: host-side evidence copies are not a term (see the K16 row). |
| **K16** | **partial** | `.gitignore` covers pcaps, `*.tr.gz`, `*-full-trace*` and Influx dumps. It misses the ns-3 traces the gates actually copy back. The M0–M7 evidence committed `m7/*/ns3run/EnbSchedAllocTraces.txt` (53 MB) and `X2Stats.txt` (51 MB), about 260–280 MB per M7 dir and 1.5 GB in total. P1 re-runs M5–M7, so those files would be committed here. GitHub rejects files over 100 MB, which would lead to `push=refused`. "Gates delete large VM-side traces after the manifest" is not implemented in the M5–M7 gates. |
| K23 decoder | ok | Both .asn files, tshark octets, Format 1 round trip `0000`, works with podman. Building it VM-side is i0 work, by design. |
| K13 config | partial | `rung-config.json` and its provenance are ok. `run-to-m9.sh` does not read it, although K13 says "every gate and run-to-m9.sh read it". The cheap fix: embed the file and its sha256 in the M9 `verdict.json`. Fix by P9. |
| K3 preflight | partial | The `list`, `--once`, `check-protected` and V2 forms ran harmlessly, but nothing records this. The refused probe (§2) is not recorded either. |
| Phase-exit item 2 | **miss** | The resume card still reads `01:36, P0 in progress, harness 1dd16a5, next action P0 step 2`. Only the status table was updated. |
| Notes accuracy | **wrong** | The `implementation-notes.html` decision says the 9-byte valueOctS "is the APER encoding of NR-CGI… the agent (P1) decodes it as NR-CGI". That is false (§3 R4). Left as is, it sends commit D down a path that silently loses the cell id. |
| Minor (by P9) | — | `--harness-sha HEAD` is not resolved to a full SHA before vm-exec/gate-m0-host, so the VM `checkout HEAD` check would fail. The watchdog is not copied into `m9/<ts>/`. `shellcheck` skips `tools/*/*.sh`. The watchdog crashes in Python if `df` returns nothing. |

## 2. Should the refused `vm-snapshot.sh delete r3-green` probe have been T8?
- **The locked contract** (goal-packet constraints and the opener) defines T8 as "a permission refusal of a *scripted* command". The probe was not a plan step, nothing was worked around, and V7 already covers the property by code order. **Under the contract it is not T8**, and the contract outranks the plan.
- **plan.md's own text is stricter.** The cross-cutting "Permissions" rule and K3 both say "A classifier refusal is T8", with no qualifier. Read literally, the plan wanted T8.
- **What to do:** do not pause now; no decision is pending. Log the deviation in `implementation-notes.html` with the time, the exact command, why it was dropped, and the contract-vs-plan reading. Put the question in the Stop A journal so the user can rule.
- **From now on:** apply the unqualified reading (any refusal → T8), and issue no unplanned command whose text names a protected snapshot next to a destructive verb. The classifier was right to block that text.

## 3. P1 risks (most serious first)
- **R1, high: stale artifacts make V1 pass vacuously and V5 falsely green.**
  - `agents-ns3-run.sh:30-43` reuses any scenario-zero binary under `~/m4-build`. It never checks the binary against `NS3_SHA`/`ORAN_INTERFACE_SHA`.
  - `agents.sh:165-177` reuses the image named in `run/image.env` whenever the metric-map sha matches. `run/` is gitignored (`ns3_e2_agent/.gitignore`), so the file survives the checkout to the new `TESTBED_SHA`. Commits D and E do not touch the metric map, so the old agent image would run.
  - Fix: rebuild unless `git -C ~/m4-build/ns-3 rev-parse HEAD` and `…/contrib/oran-interface` equal the pins, and unless the image tag equals `ns3-e2-agent:<short12 of the agent HEAD>` (the installer's own convention, `install_ns3_e2_agent.sh:35-41`). Record the heads and the tag in every verdict.
  - V1's evidence must show reference heads = P0 pins and candidate heads = the new SHAs.
- **R2, high: K19's whole-file trace equality would fail spuriously.**
  - P-A found `DlE2RlcStatsLte.txt` and `stdout.txt` differ from run to run with no input (`plans/261022-1026…/evidence/p-a-free-run-digest/20261022T020913Z/README.md`).
  - The C1 rule excludes `DlE2RlcStatsLte.txt` cols 5–6 (`brainstorm-261022-1739…:39`), but `digest-run.py` only arrives in P2.
  - Fix: before commit A, write the trace rule (the C1 rule; `stdout.txt` is not a trace) into `evidence/p1-free-run-reference/`. Then take **two** reference runs at the P0 pins and show the rule passes between them. Declaring the rule after a red V1 would look like narrowing a test (T6).
- **R3, medium-high: simTime drift.**
  - The M7 simTime comes from the latest M4 timing report (`agents-ns3-run.sh:85-99`). Re-running M4 for the new pins changes it, so the two runs' `samples_per_run` differ and K19 goes red.
  - Fix: use one explicit CLI (simTime, RngRun, indicationPeriodicity) for the reference and the candidate, through gate-s0 or `M7_SIMTIME_OVERRIDE`.
  - Also check the K19 conditions explicitly. The comparator compares common seqs only; a missing node yields `all_equal: true` (`compare-ns3-ipc-sample-digests.py:44-57`).
- **R4, high (correctness): the target-cell octets are raw, not APER NR-CGI.**
  - rc `a2282ee` builds valueOctS as `hex.DecodeString("00"+PLMN+TargetCellID)` (`control/rcE2SmRc.go:101-102`). The live wrapper copies those bytes as they are (`e2sm/wrapper.c:218-276`). The APER `e2sm_encode_nrcgi` path (`:358+`) is inside a comment block opened at `:357`.
  - With N5's `%08X%02X` key, the cell id sits in NCI's 4 pad bits (verifier-1723 #12). An asn1c APER decode drops those bits silently. The fixture `00 00F110 0000000003` would decode to NCI 0, and the key `0000000202` would lose its cell id.
  - Fix: the agent parses valueOctS raw: length 9, byte 0 = `00`, bytes 1–3 = PLMN, bytes 4–8 = the key, which maps to (gNB id, cell id). Anything else gives `control-message-invalid`.
  - Unit-test both the fixture bytes and `0000000202`. Record the NCI-nibble note as covered by N5 (not T4).
- **R5, medium: K5's order mislabels UEs on LTE fallback.**
  - The outage switch sets `m_imsiUsingLte=true` but leaves `m_lastMmWaveCell` and `m_mmWaveCellSetupCompleted` unchanged (`lte-enb-rrc.cc:4762-4768`). An initial LTE attach sets `m_lastMmWaveCell` to the LTE cell id (`:1808-1810`). Outage fallback also runs under NoAuto.
  - Keep K5's order, but define "already on target" as *served by* the target: `!m_imsiUsingLte[imsi] && m_lastMmWaveCell[imsi]==target`. A fallback UE then falls through to `lteFallback`.
  - Put the prechecks in a pure function and test them table-driven, including the row "fallback, target = last mmWave cell → lteFallback". `lteFallback` is hard to provoke live.
- **R6, medium: commit order and module placement.**
  - The IPC emitter lives in oran-interface (`model/e2-ipc-emitter.cc`), which links only `libcore` (`oran-interface/CMakeLists.txt:55-56`). `src/mmwave` links it and attaches one emitter per device (`mmwave-helper.cc:2210, 2513`).
  - So the reader and ledger cannot call `LteEnbRrc` directly. They need a callback that the helper wires to the MN's RRC. The phase-file order A→B→C does not match "reader where the emitter lives".
  - Fix: land C (schema bump + reader + hook, inert without a consumer) before A's scripted test, and log this as a sequence-only deviation. Run V1 at every pinned (ns-3, oran-interface) pair: after D4, and again at the final pair before M5–M7.
- **R7, medium: evidence routing and growth.**
  - `vm-common.sh:18` still defaults to the M0–M7 evidence dir. Export `EVIDENCE_HOST_ROOT` for every P1 `vm-exec.sh` call.
  - Add host-side evidence copies to the P1-exit projection.
- **R8, low-medium: VM overlay growth.** ns-3 rebuilds and new agent images grow the active overlay. qcow2 without discard probably never shrinks (speculation). Run `host-disk-watchdog.sh --once` before each long VM operation, prune superseded agent images, and record the active overlay `du` at P1 exit.
- **R9, low: K23 cross-check.** Take the outcome octets out of the agent-built RICcontrolAcknowledge, not from a standalone encode, and run them through `rc-decode` as `outcome`. Expect ok, consumed 2, and bytes equal to `0000`. rc panics on an ACK without an outcome, which is why this matters.
- **R10, low: RNG.** D4 must construct no `RandomVariableStream`, because an auto-stream shift breaks the digests (D5 landmine). V1 catches it.

## 4. Verdict: GO, after these items, in order
1. **Resume card.** Set last-updated, phase P1, harness `e336af4`, VM running at `f7-rerun-green`, 76 G free, and the next action. This is phase-exit item 2.
2. **`implementation-notes.html`.**
   - Replace the NR-CGI "decision" with the raw-octet layout (R4).
   - Add the refused-probe deviation (§2).
   - Add the K3 harmless-mode record.
   - Note that K13 and K16 are partial.
3. **One harness commit, before any gate runs at non-P0 pins.**
   - SHA-checked reuse of the ns-3 binary and the agent image, with provenance in the verdicts (R1).
   - Extend `evidence/.gitignore` to the ns-3 trace text files the gates copy back (for example `**/ns3run/*.txt`), keeping the sha256 manifests.
   - Check it with `git check-ignore evidence/m7/x/ns3run/X2Stats.txt` (rc 0).
4. **Before commit A.** Write the V1 rule (the C1 trace set, fixed CLI, explicit `samples_per_run` and node-set equality), then take two reference runs at the P0 pins (R2, R3).

Not blocking P1, fix by P9: the runner reads or embeds `rung-config.json`, resolves `--harness-sha`, passes `--watchdog-min-gb`, and archives the watchdog files per run, and the runner-level trip path gets tested.

## Unresolved questions (for the user at Stop A)
1. T8 scope: does "a classifier refusal is T8" (plan) override "a permission refusal of a scripted command" (contract) for unplanned commands?
2. Should the ns-3 trace text files be gitignored for the whole M8–M9 run, as K16 intended? Only manifests and digests would then be committed.

Status: DONE_WITH_CONCERNS
Summary: GO for P1 after four must-do-first items that need no user decision. The real risks are stale-build reuse making V1/V5 vacuous, K19's trace equality hitting known nondeterministic files, and the wrong NR-CGI note, which would make the agent drop the cell id.
Concerns: K16 and K13 are partially delivered; the resume card is stale; the T8 reading differs between the plan and the contract.
