R1 C4 arrival-order fixture: an R1 live run's ledger and pacer summary as they would be if ns-3 applied each
step's controls in arrival order instead of the C4 sort. Case (b) then has no refused/inHandover line (the
first-sent target-3 control is refused alreadyOnTarget), so `r0-checks.py c4` must fail on it; r0-checks.py
--self-test also checks that the sort-order counterpart (that line refused inHandover) passes.
