ts-threshold-log.txt: lines 155-165 of the TS xApp pod log (ricxapp-trafficxapp-...-2hx5c) after gate i2
run 20261024T032221Z. Line 3 is the previous run's threshold line, flushed only by this run's first
payload line (line 5); line 6 is this run's own. lint.sh uses it to test ts_threshold_logged and the
SIGPIPE hazard of `kubectl logs | grep -q` under pipefail.
c9-r2-calib/: the control ledger and the ns-3 EnbHandover{Start,End}Stats.txt of gate r2's calibration run
20261026T133922Z (25 applied controls; IMSIs repeat the same source and target). check-c9-handover-trace.py
--self-test judges it and mutated copies of it; lint.sh runs that self-test.
