# M8–M9 paused in P5: the A1 threshold never takes effect in the TS xApp (PAUSE T5), 2026-10-24 ~03:25 KST

Plan: `plans/261023-0009-GH-1-m8-m9-paced-rungs-and-m9/plan.md`. Evidence: `plans/261023-0009-GH-1-m8-m9-paced-rungs-and-m9/evidence/i2/20261023T180301Z/` (see `ts-a1-callback-lines.txt`).

## 1. Why this is a pause
The L-release a1mediator delivers A1 policy type 20008 to the TS xApp (route `mse|20010|20008|…trafficxapp…`, ESTABLISHED connection, three `Policy Callback got a message, type=20010` lines). But it sends the policy body as a JSON **string**: `{"operation":"CREATE","payload":"{\"threshold\":10}",…,"policy_type_id":"20008"}`. The TS xApp at `19e169b` reads `threshold` only as an integer under the key `threshold`, so `Setting Threshold` is never logged and the threshold stays 0. In-scope item 6 ("then the A1 threshold is set") and the R2 n2 negative cannot be met without changing the TS xApp or the a1mediator, or bypassing A1. All three need a user decision.
- **T5:** an L-release incompatibility with no L-only remedy found.
- **T3:** the acceptance signal cannot be met as written.
- **T6:** the re-run of gate i2 is red.

## 2. What P5 has so far (all pushed)
- **Stop A rulings recorded:** `plans/reports/decisions-261024-0204-GH-1-stop-a-user-rulings.md`. Ruling 4 is recorded deviation P8. Influx dumps are now gitignored, with sha256 manifests.
- **Stub QP and RMR injector image,** `tools/rmr-peer/`. Its self-test is green on the VM.
- **Gates and helpers:** `scripts/gates/ts-lib.sh`, gate i2, gate p5 (the stray-ack probe), gate r2 with `r2-checks.py` and `r2-scenario.json`, and `send-rmr.sh`.
- **Gate i2 run 1** (`evidence/i2/20261023T171928Z`) was red: the TS xApp was not registered with appmgr.
  - This is **L finding 2:** xapp-frame-cpp 2.3.6 never registers itself, and appmgr lists only registered xApps, so rtmgr gave the TS xApp no routes.
  - Remedy, per kongming (`plans/reports/kongming-261024-0245-…`): the harness registers the TS xApp and the stub through appmgr's own REST API, then restarts rtmgr.
  - Raised for Stop B.
- **Gate i2 run 2** (`evidence/i2/20261023T180301Z`, harness `59968bf`): every check passes except A1. Registration, rtmgr sessions to every xApp and a1mediator, and the 20010|20008 route all work.
- **Not run yet:** the stray-ack probe, i2 `--part stub`, and gate r2 (calibrate, `--dev`, C1).

## 3. Options for the user (kongming's pause note: `plans/reports/kongming-261024-0320-GH-1-p5-pause-a1-payload-string-ts-xapp.md`)
Kongming verified the cause at the pins (`ric-plt/a1` 3.2.2 `540cb28`, `ric-app-ts` `19e169b`). In the Go a1mediator, every 20010 carries `payload` (and `policy_type_id`) as a string: `pkg/rmr/messages.go:32-37` builds the message from a `map[string]string`. The Python a1mediator 2.5.2 sent an object, and the TS xApp was written for that shape. Kongming found no L-only, no-code remedy: a different API path, the policy-type schema, the a1mediator config, another a1mediator version and the TS xApp config were all ruled out. It confirms PAUSE T5 (T3 and T6 also apply) and records this as **L finding 3** for Stop B. It recommends option 1, rejects option 3 as narrowing a test, and lists a fourth option, an a1mediator patch, as rejected.
1. **A third allowed substitution:** a minimal TS xApp patch of about 8 lines, through the Testbed fork installer's `sed` step like substitution 2, that also parses a string `payload`, applied always. A1 stays end to end. This is a TS xApp change, so it needs your ruling. Pitfalls:
   - The installer's "already built, skipping" check could deploy the old, unpatched image; i2 must assert that the image changed.
   - Moving the Testbed pin needs proof that the agent directory is unchanged.
   - Every verdict carries `substitution3Applied`, and a standards row records that the 20010 payload shape is an O-RAN SC internal format, not an A1 spec decision.
2. **Send 20010 from the harness injector straight to the TS xApp,** with an object payload. This bypasses A1 and the a1mediator.
3. **Run R2/R3 at threshold 0** and drop or re-shape the n2 negative. This narrows a test, so it needs your ruling.

My recommendation is option 1. It keeps the A1 path real and the n2 proof intact, and it is the same kind of change as substitution 2.

## 4. State at the pause
- **VM:** running at `r0-green`, boot time 2026-10-23 07:56:59 UTC. The TS xApp is installed in gRPC mode and registered with appmgr. The stub is not installed. Three test A1 instances exist (`i2-20261023T180301Z-1..3`). No stray processes.
- **Snapshots:** `fresh-install`, `f7-rerun-green`, `r0-green`.
- **Disk:** host `/home` 53 G free; VM 50 G free.
- **Fork pins:** unchanged (ns-3 `962fabc7`, oran-interface `63155c49`, Testbed `4c8397d0`).

## 5. Resume steps
1. Run the 3 resume checks and the boot-time check.
2. Apply the user's ruling.
3. Re-run gate i2 `--part ts` fresh.
4. Run gate p5, then i2 `--part stub`, then gate r2: `--mode calibrate`, then commit W and `a1_threshold`, then `--dev`, then C1.

## 6. After the resume (2026-10-24, 08:25–09:10 KST)
- **User ruling, 08:25 KST:** "allow a third substitution", i.e. option 1 (`plans/reports/decisions-261024-0825-GH-1-substitution-3-a1-payload-ruling.md`). Testbed `c7628145` carries the patch; harness `8670eb9` checks it.
- **Gate i2 run 3** (`evidence/i2/20261023T233300Z`) was red on the threshold only. Substitution 3 worked: the patch applied and the image was rebuilt. But a1mediator still held its run-2 connection to the deleted TS Service's ClusterIP, so the three 20010s were retransmitted into nothing. This is the L7 risk, now observed, recorded as **L finding 4**.
- **kongming** (`plans/reports/kongming-261024-0840-GH-1-p5-i2-a1mediator-stale-ts-connection.md`) confirmed the cause (RMR 4.9.1 reconnects only after a read error; kube-proxy IPVS expires idle entries after 900 s, so the FIN was lost). Remedy: delete the a1mediator pod after the TS/stub pods are replaced and before rtmgr restarts, in gate i2 and in r2's per-run reset, with new freshness and connection checks.
- **Trade-off, written down as kongming asked:** I treat this as an extension of Stop A ruling 6 (the rtmgr restart) and report it rather than pause. The plan does not list L-only remedies, and T5 literally reads "an L-release failure", so the user ratifies L finding 4 at Stop B. A red re-run of i2 is PAUSE T6.
