# Row 149 at M7: consensus rulings (2026-11-07 09:01 KST)

These rulings came from a unanimous brainstorm consensus under the user's standing rule of 2026-11-07 02:21: questions that would need the user go to a brainstorm, and unanimous answers are applied without asking. They are **not user rulings**. They are shown at the next Stop, where the user can reopen any of them.

Source: `brainstorm-261107-0901-GH-1-row149-m7-ultra-debate.md`.
- Five candidates were run: four kongming and one Codex.
- A blind kongming verifier (`kongming-261107-0850-GH-1-row149-verifier.md`) picked candidate A (kongming #3), with 4 of 5 in agreement.
- Codex, the only dissenter, conceded both questions in the debate round after recounting all 30 archives.

| Q | Ruling |
|---|---|
| Q1 | **Amend row 149 before code with a ±1-epoch switch window.** Switch rows are judged by TxBytes ≤ nTxPDUs × 1310; every other row by equality; at least one equality row is required. The ledger text admits openly that this is weaker than the registered row, which never held at M7. The verifier's corrections are applied: the RLC UM LowLat class and branch; a missing switch file read as "no events"; the counter-reset site; the switch-row fixture built with nTxPDUs above its deficit. |
| Q2 | **The short-TxBytes phenomenon is recorded as a follow-up outside M10.** It is not a P7 blocker: it is pre-existing at `m10-cp2`, unchanged by P7, and a fix would need its own ruling. The entry is in the phase-10 list. |

Also recorded in the same docs commit:
- an additive row 150 amendment, the controller's call because it is stricter: P7's N4 identity part also runs the PDCP volume judge on its ulon run;
- a "Row 148 notes" continuation about pure-LTE DRBs and the AM decode class.

## For the next Stop (disclosure; non-blocking)
1. Row 149 at M7 is now judged by a window rule. This is weaker than the registered row on switch rows, and its evidence is one deterministic scenario.
2. The pre-existing UM forwarding defect at switches: truncated re-submission, silent drops, and double counting in the PDCP TX counters that feed KPM.
3. Under `UseIdealRrc=false`, a switch delay above 100 ms would turn row 149 red. It cannot give a false green.

## Unresolved questions
None blocking.
