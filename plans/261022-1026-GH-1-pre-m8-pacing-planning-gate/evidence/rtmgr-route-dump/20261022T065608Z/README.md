# Live dump of the RMR route tables for 12040/12041/12042 (open question 5, gap G9)

Run 2026-10-22T06:56–07:10Z on the VM, after a revert of `f7-rerun-green`. All 14 `ricplt` pods were Ready. At f7, kpimon-go and hw-go are deployed and rc is not.
- Harness on the VM: `c6db1ee` (pushed). Driver: `driver-route-dump.sh` in this dir, run over ssh in the foreground (not committed as a probe).
- rc was installed exactly as in `scripts/probes/probe-rc-control-latency.sh` (NIST `install_xapp_ric_control.sh`, rc `rc-sha.txt`). grpcurl 1.9.1 was sha256-checked, and the call JSON is the same.
- The 5 default agents (`enb:1,gnb:2..5`) ran with kpimon subscribed to all 5. ns-3 was not run.
- Then 10 gRPC controls went to rc, round-robin over the 5 nodes, 3 s apart.
- Captures: RMR TCP on `cni0` (`rmr.pcap`, ports 4560/38000) and SCTP on `docker0` (`e2ap.pcap`). Both pcaps are git-ignored; `pcap-sha256.txt` holds their sha256. The scrub found no secrets to redact.
- Afterwards the VM was reverted to `f7-rerun-green` again.

## Files
| Phase | State | rtmgr's view | Table e2term holds | Other |
|---|---|---|---|---|
| baseline | f7 (kpimon, hw-go) | `baseline-rtmgr-getdebuginfo.raw` | `baseline-configmaps.yaml` (static seed `router.txt`, unused once rtmgr pushes) | |
| p1 | rc installed, no agents | `p1-rtmgr-getdebuginfo.json`, `p1-rtmgr-routetable.txt` | `p1-e2term-stash.txt` (`/opt/e2/router.txt.stash`, "captured from route manager") | `p1-*-stash.txt` (xApp RMR env + stash), `p1-submgr-subscriptions*.json` |
| p2 | 5 agents CONNECTED, kpimon subscribed (subIds 1–5) | `p2-rtmgr-*` | `p2-e2term-stash.txt` | `p2-submgr-subscriptions.json` |
| p3 | after 10 controls | `p3-rtmgr-*` | `p3-e2term-stash.txt` | `calls.tsv`, `calls/`, `log-*.log`, `rc-pod-{before,after}.txt` |

In every phase, rtmgr's table and e2term's stash are the same set of lines in the same order. rc and kpimon keep no e2term-side table (they only receive 12041/12042), and rc's pod has no stash file.

## 12041/12042 entries in e2term's table, in file order
- baseline: `12041|-1` → hw-go, then kpimon. The last write wins, so kpimon gets the fallback.
- p1: kpimon, then **rc**, then hw-go. **hw-go** gets the fallback.
- p2 and p3:
  - the `-1` fallbacks are rc, then hw-go, then kpimon, so **kpimon** gets the fallback;
  - there are also exact keys `12041|N` and `12042|N` → kpimon for N = 1..5, one per kpimon subscription (submgr subIds 1–5 = kpimon's ricInstanceIDs).

For comparison, each kpimon subscription N also gets `12050|N` → kpimon and `12011/12021/12022,submgr|N` → kpimon. Requests (`12010`, `12040`) are sender-scoped to `%meid`.

## How a 12041/12042 from e2term is routed (source, same versions as deployed)
- e2term 6.0.6 sets `sub_id = ricInstanceID` and calls `rmr_send_msg` (`ric-plt-e2@6.0.6 RIC-E2-TERMINATION/sctpThread.cpp:2637-2656` ack, `:2804-2821` failure).
- RMR 4.9.4 looks up key (sub_id, mtype) first and falls back to (-1, mtype) (`si/src/sr_si_static.c:726`, `si/src/rtable_si_static.c:463-479`).
- A repeated key replaces the earlier entry (`common/src/rt_generic_static.c:548-552`), so the last `12041|-1` line wins.

## Wire observations
- RICcontrolRequest frames: 10 of 10 on docker0, 2 per agent.
- RICcontrolAcknowledge/Failure frames: 0. Today's agents do not answer controls.
- RMR on cni0 (`rmr-pcap-scan.txt`, `rmr-pcap-scan.py`):
  - 12040: 20 frames, rc → e2term, sub_id -1;
  - 12010: submgr → e2term with sub_id 1..5;
  - 12011: e2term → submgr with sub_id -1;
  - **12041/12042: 0 frames.**
  - The header offsets were checked on these frames: sub_id is at +212 because the timespec is 8-byte aligned.
- rc's ricInstanceIDs are 2, 4, …, 20 (`log-rc-full.log`). rc RestartCount stayed 0 (same pod before and after).
- Expected destinations under the p3 table: IDs 2 and 4 → kpimon by exact key; 6–20 → kpimon by the fallback. **No ack or failure for these controls would have reached rc.**
