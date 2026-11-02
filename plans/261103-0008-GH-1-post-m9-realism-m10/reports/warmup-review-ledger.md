# Warmup review ledger (contract-preserving, classify-first)

Plan: `../plan.md`. Contract: `plans/reports/contract-261103-0001-GH-1-post-m9-realism-outcome-contract.md` (approved 2026-11-03 00:0x KST; Amendment 1 re-approved 01:10 KST).

Classes: MWC = mitigation-within-contract (plan edit allowed); PRE = preflight-required; BLK = blocker; OCR = outcome-change-request (user decision).

## Round 1 (2026-11-03 00:35–01:05 KST)

Reviewers:
- Planner self-findings F1–F12 (plan.md).
- kongming, Opus 5.5 at xhigh, read-only: `plans/reports/kongming-261103-0034-GH-1-m10-plan-review.md`, verdict go-with-changes.
- Codex `task --fresh --effort high`, read-only, run 1 of this review (no cap, R3), verdict needs-attention.

### Outcome-change requests (ruled by the user, folded into Amendment 1)

| Finding | Ruling | Contract edit |
|---|---|---|
| F1: AC8b literal predictor records, scenario and schedule impossible after AC12/R6 (N5 keys, P1 strings, `via`, `scenarioSha256`) [V `r3p-scenario.json:5,17,27`, `r3p-schedule.json:2,48,52`, M9 `files.json` pins predictor records] | (a) registered transform, predictor numbers literal | AC8b |
| F5: no RIC component sees the en-gNB-UEID values (IPC and KPM carry the IMSI only) | A: KPM carries en-gNB-UEID / eNB-UEID; kpimon → Influx → TS xApp | AC14, new AC14b |
| kongming: kpm_sim (e2sim `send()`) sends PPID 0 in M2/M3 captures vs AC11 | patch e2sim too | AC11, in-scope |

### Plan edits (MWC) and preflight items (PRE)

| Source | Finding | Class |
|---|---|---|
| F2 | SN-initiated execution in-process, zero latency, X2 mapping disclosed at Stop A′ | MWC (interpretation) |
| F3 | HandoverStart − apply = registered c = 3.0 ms | MWC (interpretation) |
| F4 | `decisionSimTimeNs` := `rxSimTimeNs` | MWC (interpretation) |
| F6 | RC action 3 parameter IDs from v01.03 (`PSHY8566`) and v03.00 (`JRDTL7XS`) §8.4.6.3, which match | MWC; resolved |
| F7 | e2mgr 6.0.6 stores no RAN functions for eNB nodes; eNB measurement list from kpimon config, disclosed; AC6a extended | PRE + MWC |
| F8 | eNB sends an init-eNB X2 setup request part | MWC (interpretation) |
| F9 | cell part = 1 | MWC (interpretation) |
| F10 | kpimon 100 ms period across m3 (kpm_sim) | PRE (P03 measures) |
| F11 | Zotero: 3GPP TS 38.323 `MSNDDXJH`, 36.423 `3ML7Y29A` present; 28.552 to check | PRE (P01) |
| F12 | rc patches new; `rcService.go:35` nil `GnbUEID` panic; stale-image guards; protoc byte-equal proof | MWC |
| kongming | independent RIC control injector with own route | MWC |
| kongming | X2AP mandatory field constants | MWC |
| kongming | cp3 ordering: rehearsals + Codex audit before the tag; s10 at cp3 pins; re-bank δ refs at cp3 | MWC |
| kongming | p12 restores 100/100; non-multiple → RIC SUBSCRIPTION FAILURE | MWC |
| kongming | hub: sort on resolved IMSI; source-SN check; tie order | MWC |
| kongming | AC18 seed additions | MWC |
| kongming | budget: T′ = max(method, measured 42 GiB base); `/mnt/data` line; re-measure cold i0/i2/m3 | PRE |
| Codex 1 | NR PDCP header consumers (`lte-ue-rrc.cc:1829`, `lte-rlc-am.cc:1801`) | MWC |
| Codex 2 | replay path rebuilds controls from ledger IMSIs (`pacer.py:63`, `ts-rung-lib.sh:168`) | MWC |
| Codex 3 | R1 addressing assertions (`gate-r1-rc-multi-control.sh:249,275`) | MWC |
| Codex 4 | TS patch validator fixed to two patches (`ts-lib.sh:57,98`) | MWC |
| Codex 5 | agent kind `en-gnb` vs metric map / hello check | MWC |
| Codex 6 | AC6b probe cannot use `measure-ns3-timing.sh` | MWC |

No blockers. Applied by the planner in plan rev 2 (see plan.md "Review disposition").

Late addition: I-9, the AC11 citation named the wineslab e2sim fork, but kpm_sim is built from the Testbed `e2-interface` tree [V `install_e2sim.sh:49-59`]. It is a citation correction and the requirement is unchanged, so this is clerical, not an OCR. The contract was fixed 01:45 KST.

## Round 2 (2026-11-03 01:45–01:50 KST)

Codex `task --fresh --effort high`, read-only, run 2 of this review. Verdict needs-attention. Round-1 items 1–6 are confirmed resolved in rev 2.

| Finding | Class | Disposition |
|---|---|---|
| R2-1: `r3p-prepare.py:48` and `r3p-schedules.py:31` still key on the IMSI | MWC | assigned to the migration; plan rev 3 |
| R2-2: P06b's R2/R3′ exit needs P07's TS xApp consumer, a circular dependency | MWC | integration exit moved after P07; plan rev 3 |
| R2-3: the C4 replacement contradicts the hub sort (target before ctlId) [V `e2-control-hub.cc:248`] | MWC | keep reverse-target arrival; the higher-ctlId/lower-target control applies first; add an arrival-order fixture that must fail; plan rev 3 |
| R2-4: the RC UE-ID transform has no frozen independent mapping | MWC | IMSI → {RNTI, MN cell} mapping frozen and checksummed at P04 from ns-3 at the cp1 commit; negative fixtures; plan rev 3 |

No OCRs or blockers. Rev 3 landed at 02:22 KST. The controller spot-checked it: the status line, R-8, and the P06b+P07 boundary are present, and `DlE2PdcpStatsLte.txt` is in M9's literal digest set [V `reference/r3p/equal/digests.json:17`], so the identity map's source is not circular.

Status: complete
