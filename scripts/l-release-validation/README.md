# L-release E2 validation harness (M1–M5)

Version-pinned, re-runnable assertions that the **rebased OSC L-release e2sim**
(vendored from `e2-interface` `da6f82f2`) speaks correct E2AP v3.01 / E2SM-KPM v3
to the live L-release Near-RT RIC E2Term. Built for Phase 2 of the
ns-O-RAN → L-release migration; re-usable for future RIC releases by bumping
`manifest.txt`.

## Where to run
**On the VM `oran-kvm-2`** (== `oran-kvm-3`). The E2 SCTP rides `cni0`; capture
needs `sudo`. Decode is richest with a recent tshark (VM has 3.2.3; copy pcaps
to a 4.x host for fuller `-V` output — assertions work on both).

## Prereqs
- Self-built `kpm_sim` from the vendored OSC tree. Build:
  ```
  # e2sim lib (produces .deb with headers):
  cd oran-e2sim/e2sim && mkdir build && cd build \
    && cmake .. && make package && cmake .. -DDEV_PKG=1 && make package
  sudo dpkg -i e2sim_1.0.0_amd64.deb e2sim-dev_1.0.0_amd64.deb && sudo ldconfig
  # kpm app (needs e2sim/asn1c staged as a sibling, + nlohmann json):
  sudo apt-get install -y nlohmann-json3-dev
  sudo cp /usr/include/nlohmann/json.hpp /usr/local/include/nlohmann/
  # stage: cp -r e2sm_examples/kpm_e2sm/. <stage>/ ; cp -r asn1c <stage>/asn1c
  cd <stage> && mkdir build && cd build && cmake .. && make
  ```
  Point the harness at it: `export KPM_SIM=<stage>/build/src/kpm/kpm_sim`
- Live `ricplt` E2Term reachable at `192.168.122.78:32222`.

## Milestones
| # | Script | Asserts | Status |
|---|--------|---------|--------|
| M1 | `m1-sctp.sh` | SCTP INIT/INIT-ACK + sim "Connection established" | GREEN |
| M2 | `m2-e2setup.sh` | `E2setupResponse` (successfulOutcome/id-E2setup) | GREEN |
| M3 | `m3-ranfunction.sh` | `RANfunctionsAccepted` func 2, no `RANfunctionsRejected` | GREEN |
| M4 | `m4-subscription.sh [pcap]` | `RICsubscriptionResponse` | BLOCKED (Q4) |
| M5 | `m5-dummy-kpm.sh [pcap]` | `RICindication` + E2SM-KPM v3 | BLOCKED (Q4) |

`run-all.sh` runs all five and prints a summary (M4/M5 report NOT-RUN until a
subscriber exists).

## Why M4/M5 are blocked
The bundled `kpm_sim` is **reactive-only**: it registers a subscription callback
and blocks on "Waiting for SCTP data". Indications flow **only after** it
receives a `RICsubscriptionRequest` from a KPM xApp. No KPM xApp is deployed
(`ricxapp` has only `hw-go`). Choosing the subscriber (onboard `scp-kpimon` /
`kpimon-go`, which also surfaces the func-id 2-vs-0 mismatch, Q3) is an open
decision — see the Phase-2 handoff and `implementation-notes.html`.
Once a subscriber drives a subscription, capture during it and pass the pcap to
`m4`/`m5`.

## Files
- `common.sh` — shared endpoints/paths + capture/run helpers.
- `assert-pcap.sh` — tshark force-decode (PPID 0+70 → e2ap, x2ap disabled) + checks.
- `m1..m5*.sh`, `run-all.sh` — milestones.
- `manifest.txt` — pinned versions (e2sim commit, asn1c 0.9.29, e2term 6.0.6).
- `captures/` — pcaps; `phase2-m1-m3-selfbuilt-setup.pcap` is the Phase-2 evidence.
