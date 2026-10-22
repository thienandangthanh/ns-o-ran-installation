# P1 V1 rule: free-run output unchanged by S0 (written 2026-10-23 02:45 KST, before any reference run)

Applies to P1 V1 (phase file and review amendment K19) and to the free-run part of `scripts/gates/gate-s0-free-control.sh`. Written down before the reference runs so the comparison cannot be narrowed after a result (kongming P0 exit, must-do 4).

## Runs
- Fixed CLI for every run: `scenario-zero --nMmWaveEnbNodes=2 --handoverMode=NoAuto --simTime=10 --RngRun=1 --e2TraceDir=<run>/trace`, working directory `<run>/ns3run` (ns-3 writes its trace text files there). Every other attribute is the scenario default. This is the R0 config (D3, D9) without controls.
- E2 peer: `tools/ipc-null-sink/ipc-null-sink.py` on ports 38471–38473, no `--controls`. Free-run output does not depend on the peer (pre-M8 probe P-A).
- Reference: 2 runs at the P0 pins (ns-3 `ace32168`, oran-interface `438a839`), `ref1` and `ref2`.
- Candidates, one run each, at every pinned (ns-3, oran-interface) pair of P1 (kongming R6): `a` = ns-3 commit A `786527b3` with oran-interface `438a839`; `new` = the P1 pins in `scripts/pins.conf` (ns-3 `d3bc4d96`, oran-interface `2817f7e4`).

## Pass condition (each of ref2, a, new against ref1)
1. IPC samples: `scripts/probes/compare-ns3-ipc-sample-digests.py` over the `e2-ipc-trace-<node>.jsonl` files reports `all_equal: true`. In addition, checked explicitly because that script ignores nodes missing from one run: the node set is the same ({1, 2, 3}) and `samples_per_run` is equal for every node. `hello` lines are excluded (they carry the wall-clock epoch, pid run id and, from P1, `minor` 1).
2. ns-3 trace text files: the set of `*.txt` file names in `ns3run/` is the same, and every file's sha256 is equal, with one exception taken from contract C1 (`plans/reports/brainstorm-261022-1739-GH-1-m8-m9-delivery-contract.md:39`): `DlE2RlcStatsLte.txt` is compared with its columns 5–6 removed. `stdout.txt` and `stderr.txt` are process logs (timing), not traces, and are not compared.
3. No `e2-control-ledger.jsonl` exists in any run (no control, so the control path writes nothing).

If `ref2` differs from `ref1` under this rule, the rule itself is wrong for this config; that is a failed Verify (Failure Protocol, kongming), not a reason to edit the rule.
