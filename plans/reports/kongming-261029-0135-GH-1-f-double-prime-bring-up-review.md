# Kongming review: guided fix F″ (bring-up route readers + agent READY backstop)

- Diff reviewed: `git diff fb3554a ce86613 -- scripts`, which touches three files: `scripts/gates/bringup.sh`, `agents.sh` and `rc-lib.sh`.
- Spec: `kongming-261029-0100-...-counsel.md`, section "Addendum after the §4 capture".
- Line numbers below are at ce86613.
- Reviewer: kongming on Opus 5.5 (CX-1: Codex skipped because the run cap was reached). This review is advisory and is not user approval.

## Verdict
**GO for the validation run (`gate-m6-kpm.sh` at ce86613 on the wedged VM).** There is no must-fix.
- I recommend one cheap hardening (S1) before the F″ freeze. It can also go in before the validation run if a recommit is acceptable.
- Two items must be added to the validation acceptance list (V-a, V-b).

## TL;DR
- The code implements the addendum correctly under `set -uo pipefail` (`lib.sh:14`; `check` at `lib.sh:53-62` never aborts).
- The PIPESTATUS indices, return codes, markers and `"${@:2}"` reuse are correct. `AGENTS_SETUP_WAIT_S` is set before use.
- No judged check, verdict, budget, pin, tool or reference input changes. K14 holds by its own definition.
- The one real false-red vector is a transient `kubectl exec` failure on the final sample. I reproduced it with a stub: a drained reader read `STUCK (5 samples, 0 sockets now)`, rc 1.
- The main residual risk is not in the code. After a refresh, a lost first E2 Setup would restart an agent. m7 and the R-gates judge agent RestartCount = 0, so the validation must check it.

## 1. Bash correctness (verified)
| Item | Finding |
|---|---|
| `rt_reader_ok` return, `bringup.sh:258-259` | In `echo \| python3 \| tee \| tail`, `PIPESTATUS[1]` is the python exit. Correct. Python and `tail` read all input, so there is no SIGPIPE. |
| `ric_refresh_routes` rtmgr pipe, `:288-289` | `PIPESTATUS[0]` is `ric_restart_rtmgr`. Correct. The `while` subshell leaks nothing. |
| Sample loop, `:236-239` | Runs in a subshell. `kc` and the knobs are visible there. The `[ ] && sleep` exit status is irrelevant because only stdout is used. Exec errors are silent (see S1). |
| Until-loop pipeline, `:232` | Under pipefail, a non-zero `kubectl exec cat` (for example, no `/proc/net/tcp6`) fails the pipeline even when awk found the socket. That would give "no ESTABLISHED socket" for 120 s. **Latent only:** the live capture shows tcp6 tables in both pods (`m6-diagnosis/live-*/tcp-{e2mgr,submgr}.txt`), and the images are pinned. Optional fix in S2. |
| Field parsing | awk `$2/$4` and Python `f[1]/f[3]/f[4]` match the `/proc/net/tcp` layout. `endswith(":11D1")` also matches IPv4-mapped tcp6 rows. 4561 = 0x11D1. |
| Return codes | `_bringup_ric` → bare `return` (`:123`) gives the status of `_ric_route_readers_ready`, which is the refresh status on failure. `ric_refresh_routes` ends with `sleep`, i.e. 0. `agents_bringup` ends with `connected && ready`. All correct. |
| Locals and dynamic scope | `tag`, `c`, `deadline`, `old` and `new` are local in every function. Nothing assigns `_check_*`. The local `tag` in `rt_reader_ok` is unused (cosmetic). |
| `AGENTS_SETUP_WAIT_S`, `agents.sh:212` | The assignment runs at source time. `_bringup_agents` sources the whole file, and globals assigned in a sourced file are global, so the variable is set before `agents_bringup` runs, including the log at `:202`. Correct. |
| `"${@:2}"`, `agents.sh:195,206` | Positional parameters are unchanged between the two uses (no `shift` or `set --`). They expand to empty under `-u` when absent. The `--env` args of s1 survive. Correct. |
| Markers, `:268` | `mkdir` is atomic. There is one marker per level per `EVIDENCE_DIR`, and no gate reassigns `EVIDENCE_DIR`, so the scope is the whole gate. Example: r3p C1 gets one RIC-level and one agent-level refresh across its 4 runs. The marker survives a failed refresh, so there is no second try (as specified). |
| `rc_restart_rtmgr` → `ric_restart_rtmgr`, `rc-lib.sh:129` | The body is byte-identical. Every gate that sources `rc-lib.sh` or `agents.sh` sources `bringup.sh` first (14 of 14 checked). `lint.sh:77` extracts only the restart judges. Correct. |

## 2. Side effects per caller
- **m1** (`gate-m1-ric-up.sh:69`)
  - The check runs after pods are Ready and e2term is registered. rtmgr wormholes to e2mgr and submgr are persistent: the capture shows them, and `rtmgr_sessions` is judged green in the R-gates.
  - A refresh lowers the restart baseline (`:169-170`, "a drop lowers the bar"). The image checks see the same images.
  - Not exposed beyond +~22 s.
- **m2 and m3** (refnode)
  - `_bringup_ric` runs up to 3 times in m2 and once per tag in m3. Each check is read-only (~22 s). There is at most one refresh. A stuck reader after the marker is spent gives `return 1`, which is red by design.
  - A refresh before kpm_sim is fine. If kpm_sim's single setup were lost, `REFNODE_ATTEMPTS` already retries.
- **m5, m6, m7**
  - Refresh at RIC level happens before any agent exists. The SCTP-only capture (`ip proto 132`) is untouched.
  - In the remedy path, old-agent setups stay in the pcap. The judges are unaffected:
    - m5 setup queries accept any match;
    - indications and RC requests come only from the new IPs (`agents_record_ips` runs after bring-up, and `e2-facts-query.py:182-190` is informational);
    - m7 `ips_distinct` sees only new containers because `agents_stop` removes the old ones.
  - m6 kpimon restart delta: kpimon is not touched.
- **R-gates (r0, r1, r2, r3p)**
  - Order: `rc_ric_reset` (rtmgr restart) → capture → `gate_bringup agents` → reader check (`ts-rung-lib.sh:50-53`, `r3p:131-132`, `r0:159-165`). This is the order the addendum wanted.
  - A refresh replaces only ricplt pods. `rc_pod_snapshot` and `rc_restarts_zero` cover ricxapp pods plus agents (`rc-lib.sh:150-171`), and `check-ric-reset.py` reads ricxapp only.
  - An extra rtmgr restart is the same class every R-run already does, and `ts_stub_pods_reset` restarts it again in r2 and r3p.
  - `rtmgr_push_acked` still reads a gate-restarted rtmgr, so the own-pod rule holds.
  - Remedy agents are new containers (RestartCount 0, ctlId restarts at 1), and their stats/ledger begin after bring-up.
  - Nothing feeds the digests or the ledger.
- **i0 and i2**: not exposed. They make no `gate_bringup` call, and `rc_restart_rtmgr` keeps the same behaviour.
- **s0, s1, q8, n4, p5** (non-M9): same semantics as above. The s1 withholding agent still reaches READY (its `all_subscribed` requires 3/3 READY).
- **Budget**
  - Green path: about +22 s per `_bringup_ric` plus ≤ 5 s READY wait, roughly 15–20 bring-ups in M9, so +6–8 min against `globalWallS` 20199.
  - Per-gate timeouts keep at least 2× headroom.
  - With a RIC-level refresh, m6 needs about 325 s + 4–5 min, which fits 1088 s.
  - With both levels in one m6, it needs about 1050 s. That is tight, but this path is the off-ramp anyway.
- **Evidence**: the new text files are covered by `scrub-evidence.sh`, which walks every file. `watchdog.log` is not judged; m1 reads only `.watchdog.fired`.

## 3. Narrowing, A1 and K14
- **No narrowing.** No `check`, judge, verdict field, budget or pin is changed.
- The refresh and the agent remedy are bounded, logged bring-up remedies in the same class as the K3 e2term watchdog and NIST's e2term roll. They can turn a would-be-red gate green.
- **Must-do (run report, not code):** list every `ric refresh (<level>)` line in `watchdog.log` and every `agents-ready-remedy.txt` as a disclosed deviation in the M9 run report. A rescued green must not be silent.
- **K14.** Its definition (`phase-09:59-63`) is "fork pins + pacer, scenario, schedule, rung-config". F″ touches none of these, and `git diff --name-only fb3554a ce86613 -- scripts tools <plan>/reference` lists only the 3 bring-up files.
  - The `reference/r3p/equal` digests (extra, ipc, ledger, traces; predictor-records, scenario, schedule) are produced in lock-step after bring-up. They were already equal across live1–3 and an independent single run, so they are insensitive to bring-up timing. **`reference/r3p` stays valid; do not regenerate it.**
  - The record must change, though. `m9-budget.md:56` ("no file the r3p gate reads has changed") and `:81` become false at F″, because r3p sources all 3 files. The F″ freeze addendum must restate K14 against the definition. It must also set `<frozen>` = ce86613 for `phase-10:56` and fix the template line "only two host files differ".

## 4. False-red analysis
- **S1 (should-fix, cheap): one failed exec on the final sample means STUCK.**
  - Python resets `last` at every `sample` header (`:246-247`). An empty final sample therefore gives `last = {}`, and the result is STUCK.
  - Reproduced: a stub with a drained copy of the live tcp file and the 5th exec failing printed `STUCK (5 samples, 0 sockets now, stuck [])`, rc 1.
  - Consequence:
    - on the first check, an unneeded refresh (~4–5 min, plus the e2term residual below);
    - on the post-refresh check, a red, which would be PAUSE T6 after F″.
  - Fix: decide on the last sample whose output contains the `/proc` header line (`sl  local_address`). That separates "exec failed" from "no socket". Key it on the header, not the exec exit, so a tcp6-less `cat` still counts. Optionally log exec failures.
- **S2 (optional, latent):** `:232` should be `{ kc ... || true; } | awk ...`, or equivalent, so the awk result decides.
- **Healthy reader mid-read in all 5 samples:** not credible. A live RMR collector drains each ~4 KB push at once, and the samples span about 8 s.
- **tcp6-only sockets:** handled.
- **Old dead socket lingering ESTABLISHED with data:** unread data means the reader was not reading that fd, which is the wedge itself.
  - A healthy reader drains before the peer dies, and the FIN arrives through IPVS: the entry is alive because rtmgr pushes every ~40 s, well under the 900 s idle timeout. The socket then closes or sits in CLOSE_WAIT (state 08), which is excluded.
  - After a refresh, all sockets are new. No false STUCK comes from this.
- **Nit, `:262` comment:** "pod delete … so two copies never share the SDL" is not strictly true. The ReplicaSet starts the replacement while the old pod is still in its grace period.
  - This is harmless here: at RIC level no agents are connected, and at agent level they were stopped first.
  - The serial delete (not "together" as in the spec) only costs about 30–60 s.
- **Nit, backstop scope:** the agent remedy fires only after the CONNECTED set is exact (`agents.sh:198`). A multi-node wedge that desynchronizes the CONNECTED windows would time out without a remedy. The RIC-level detector is the primary guard, so accept this.

## 5. Validation acceptance (add V-a, V-b to the addendum's 1–6)
- **V-a: agent RestartCount = 0 after READY** (`agent-inspect.json` `.RestartCount`, or column 2 of `agents_stats_all`).
  - Why: after e2mgr is replaced, e2term's RMR connection to the e2mgr VIP:3801 is old. I expect FIN, then a clean re-dial, because keep-alives every 120 s keep the IPVS entry alive.
  - If the first E2 Setup is lost instead, the agent exits 3 (setup timeout 10 s, `e2-session.hpp:1-7`) and `--restart always` brings it back.
  - m6 would still be green, but m7 (`endurance-eval.py:10`) and the R-gates (`rc_restarts_zero` over agents) would be red in M9.
  - RestartCount ≥ 1 means: do not launch. Record it and consult.
- **V-b: the path actually taken.** The log should show:
  - `rt-readers-ric-*.txt` STUCK with rx about 126 KB;
  - one `ric refresh (ric)` start/done pair in `watchdog.log`;
  - `rt-readers-refresh-ric-*.txt` OK with rx 0;
  - no `(agents)` refresh;
  - the refresh duration, to confirm the budget estimate.
  - If the VM is no longer wedged (rebooted since 16:17Z), the first check passes and the remedy stays unproven live. F″ is still no worse than F′, so a launch is defensible, but record that.
- The agent-level remedy stays untested live. That is acceptable for a backstop.

## Assumptions
- High: e2mgr/submgr images and kernel are as captured (tcp6 present, `cat` available). Pinned images make this stable.
- Medium: the healthy rx_queue is 0. This is inferred from rtmgr's tx_queue 0 on healthy sessions and from RMR reader behaviour; the post-refresh OK in validation is the first live proof.
- Medium: e2term re-dials the e2mgr VIP cleanly after the replacement. V-a tests this.
- Low: a transient `kubectl exec` failure rate below 1e-3 per call. If it is higher, S1 becomes a must-fix.

## Unresolved questions
- None blocking. Applying S1 before or after the validation run is the caller's call. If it is applied after, re-run lint and the stub test, and K14 still lists the same 3 files.

Status: DONE_WITH_CONCERNS
Summary: F″ is correct and does not narrow any check, and reference/r3p stays valid under K14. GO for the m6 validation. S1 (false STUCK on a failed final exec) is a recommended cheap fix, and agent RestartCount = 0 must be checked in validation.
