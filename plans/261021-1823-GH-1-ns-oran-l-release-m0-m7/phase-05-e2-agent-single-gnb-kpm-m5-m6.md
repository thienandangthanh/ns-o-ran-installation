# P5 — E2 agent + single-gNB KPM (M5, M6)

## Requirements
1. **Agent per the P3 design:**
   - Built with NIST's e2-interface build at `da6f82f2`.
   - Packaged as a container image or pod.
   - Receives IPC samples and does E2Setup (RAN function 2, KPM v3 definition), subscription option A and RICindication with an 8-byte TimeStamp.
   - Connects to the e2term **Service**.
2. Start and stop scripts for 1 agent and 1 gNB (ns-3 configured with one active E2 node), with clean teardown.

## Gate M5 (`gate-m5-agent-setup.sh`)
- Capture on the VM. tshark decodes the agent's E2SetupRequest, with the RAN function ID and definition visible.
- The E2SetupResponse `RANfunctionsAccepted` contains the KPM function ID (expected 2; re-verified against the kpimon subscription).
- e2mgr lists the node CONNECTED with the expected global gNB ID.

Pass → snapshot `l5-agent-setup`.

## Gate M6 (`gate-m6-kpm.sh`)
- kpimon (patched, from `l3-xapps`) subscribes, and tshark decodes the Subscription Request/Response.
- Indications are decoded by tshark as E2AP RICindication carrying E2SM-KPM v3 (header OID/version and message format visible). See the P2 risk note on dissector support.
- **kpimon decoder harness** over the captured window: header `RC_OK` = message `RC_OK` = indication count, with zero `RC_WMORE` and zero `RC_FAIL`. The kpimon log counts agree.
- **InfluxDB vs ns-3 trace:** pick 3 samples (by sim timestamp). For each, the InfluxDB `cellMetrics`/`UeMetrics` field values equal the ns-3 trace values (exact for counters; documented rounding rule for floats).
- Teardown leaves no stray ns-3 or agent process (`ps` plus `ss -Sanp`).

Pass → snapshot `l6-kpm`.

## Risks
- **kpimon may parse the KPM v3 message format differently from v2** (contract: the message decodes as v2 by design). The harness shows it. On a mismatch, consult kongming. A fix that changes the M6 signal is a **Decision required**.
- **Timestamp semantics:** the 8-byte value is ms or s plus fraction. Match what kpimon and Influx expect, and document it in implementation-notes.

## Review amendments (contract-preserving review, 2026-10-21)
- **K2: the M6 Influx check is rewritten without changing its meaning.** Pick 3 samples and join InfluxDB rows to the ns-3 trace on `(ns3.nodeId, ns3.simTimeMs)`. kpimon gives no tags and stamps wall-clock time, so a join on the Influx timestamp is meaningless.
- **E2Setup content.** The KPM OID and version are asserted on the E2Setup RAN-function item, not on the indication header.
- **K6: before M5/M6,** `gate_bringup agents` runs `stop_e2sim.sh` and asserts that the e2mgr CONNECTED set equals the expected agent set, so kpm_sim rows never mix in.
- **K1: the expected global gNB ID** comes from the P3 identity design (env-configured), and it must differ from kpm_sim's `B5C67788`.
