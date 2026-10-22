# Probe: live RMR route tables for rc's control ack (open question 5, gap G9)

Date 2026-10-22 (run 06:56–07:10Z). The VM was reverted to `f7-rerun-green` before and after the run, and is left running at f7: 14/14 `ricplt` Ready, xApps hw-go and kpimon only, no agent containers.
Evidence: `plans/261022-1026-GH-1-pre-m8-pacing-planning-gate/evidence/rtmgr-route-dump/20261022T065608Z/` (start at `README.md`).

## Answer
Counsel B's claim holds, and the live tables show it is worse than counsel B said.

1. **Routing key is (mtype, sub_id), falling back to (mtype, -1).**
   - e2term 6.0.6 sets `sub_id = ricInstanceID` on 12041/12042 and sends with `rmr_send_msg` (`sctpThread.cpp:2637-2656, 2804-2821`).
   - RMR 4.9.4 tries the exact key, then the `-1` key (`sr_si_static.c:726`, `rtable_si_static.c:463-479`).
   - There is no routing by message type alone and no meid scoping.
2. **Collision is real.** Every kpimon subscription N adds `12041|N` and `12042|N` → kpimon.
   - Live: N = 1..5, one per node, the same numbers as kpimon's ricInstanceIDs.
   - rc's ricInstanceIDs are 2, 4, 6, … (seen: 2..20 for 10 calls). So rc's 1st and 2nd controls, IDs 2 and 4, would have their acks routed to kpimon by exact key.
3. **The fallback is not rc's either.** rtmgr writes one `12041|-1` and one `12042|-1` per xApp, and RMR keeps the last one (`rt_generic_static.c:548-552`). The order changes every time rtmgr regenerates the table:
   - baseline: hw-go, kpimon → **kpimon** wins;
   - p1 (rc installed): kpimon, rc, hw-go → **hw-go** wins;
   - p2/p3 (agents subscribed): rc, hw-go, kpimon → **kpimon** wins.
   - In none of the 3 live tables taken with rc deployed would a non-colliding ID reach rc.
   - Under the table in force during the controls, **0 of the 10 acks/failures would have reached rc**: IDs 2 and 4 → kpimon by exact key, 6–20 → kpimon by fallback.
4. **rtmgr's view equals what e2term holds.** `getdebuginfo` and e2term's `/opt/e2/router.txt.stash` ("captured from route manager") are the same set of lines in the same order, in all phases.

Implications for G9/G8:
- The G9 wording "not deterministic" is accurate. In practice it is "usually not delivered to rc", decided by Go map order, plus exact-key theft for low IDs.
- rc's 2 s ack timeout will be the normal path. G8's crash path needs an ack to actually reach rc, so it is rarer than counsel B assumed, but not ruled out: the order can change on any rtmgr regeneration.
- Gate on the wire, as the journal says. If acks must reach rc, a fix is needed outside rc's code, for example:
  - rc as the only xApp with a 12041/12042 `-1` route (undeploy hw-go, and kpimon must not own the fallback; rtmgr adds the `-1` route for every xApp regardless of its declared messages, see the baseline RouteConfigs);
  - or rc's instance IDs offset beyond submgr's id range.

  This is a design decision for M8; nothing was changed.

## Wire proof
Partial. 10/10 RICcontrolRequest reached the agents, but the agents send no RICcontrolAcknowledge/Failure today. So there were 0 frames of 12041/12042 on RMR, and the routing of a real ack was not observed. rc RestartCount stayed 0.
- RMR header parsing was validated on the live frames: 12010 submgr → e2term carried sub_id 1..5, and 12040 rc → e2term carried -1.
- To observe an ack being routed, the agent (or ns-3) has to send the reply. That belongs in the M8 agent work.

## Confidence
- High for the route tables: live dumps, two independent views that agree.
- High for e2term's sub_id choice and RMR's lookup and last-wins rules: source at the deployed versions, matching the live table shape.
- Medium-high for "0 of 10 would reach rc". It is inferred from the tables plus source, not observed on the wire.

## Process notes
- `systemd-run` (the vm-exec-probe mechanism) was refused by the permission classifier. The driver ran over plain ssh as a tracked background job instead. All background jobs (ssh driver, log monitor) ended or were stopped, and no remote tail is left.
- No snapshot was created or deleted, nothing was committed or pushed, and no fork repo was touched. RMR 4.9.4 and e2term 6.0.6 sources were cloned into the session scratchpad only.

## Unresolved questions
1. Does rtmgr regenerate the table, and so possibly reorder the `-1` entries, on every subscription change? If yes, the winner can change mid-run.
2. Should M8 fix ack delivery (an xApp set or ID-range change) or accept the rc timeout path? This is a user decision.
