# P01 (MA): rc claims, identity probe, scale probe, ASN.1 toolchain, standards preflight

**Start state:** `f7-rerun-green` (or a fresh M0–M7 chain), M9 pins. **Snapshot at exit:** none.

## Context
Cheap facts that gate later phases:
- AC6 must hold before any δ > 0 code (P02).
- AC6a decides whether T-A is feasible on the deployed L-release images. A refusal is a Decision required.
- AC6b sets the AC15 simTime and the disk and wall budget.
- The F10/F11 preflight puts any T4 (missing document) here instead of mid-phase.

The probes send E2 Setups and a KPM subscription with an encoder outside the agent, so no T-A code lands before checkpoint 1. The same toolchain later serves AC12 (the independent target encoder), AC13 (the decoded X2AP request part) and the P06 control injector.

The deployed e2mgr is 6.0.6 [V `plans/261023-0009-GH-1-m8-m9-paced-rungs-and-m9/reference/r3p/recorded/deployed-image-ids.json:43`]. At that tag it stores RAN functions only for gNB nodes; an ENB node has no `ranFunctions` [kongming review §1 F7, upstream source].

## Requirements (contract)
- **AC6:** at the deployed rc SHA `a2282ee` (`scripts/gates/rc-lib.sh:35`), verify with file:line that an ACK without ControlOutcome panics rc and that the ACK timer is 2 s. Pre-scouted [V]:
  - `ric-app-rc/control/rcE2SmRc.go:134` takes `&buffer[0]`;
  - `control/rcControl.go:156-197` runs a timer that only logs;
  - `xapp-descriptor/config.json:72` sets 2;
  - the installer edits only the image fields;
  - a late ACK returns at `rcControl.go:335-339`.

  Confirm both at runtime with one fixture each and record rc's RestartCount.
- **AC6a:** the live e2mgr and e2term accept an E2 Setup from an eNB (Global ENB ID, macro) and from an en-gNB (32-bit Global en-gNB ID). Record:
  - the meids (expected `enB_macro_…`, `en_gnb_…` [V `ric-plt-e2/RIC-E2-TERMINATION/BuildRunName.h:150-157,189-191`]);
  - the e2mgr nodeb JSON (`enb`/`gnb` key, `nodeType`, `nbId` length, and **the eNB JSON without `ranFunctions`**);
  - **one KPM subscription sent to the eNB probe node** (through submgr, from a probe xApp identity or kpimon's subscription path) and its decoded answer.

  A refused setup → PAUSE T3.
- **AC6b:** one 10-gNB ns-3 run measures wall seconds per sim second and disk growth.

## Design notes
- **Probe IDs** cannot collide with ns-3 cellIds: en-gNB `0x7F000001`, macro eNB `0xFFFFE` (plan R-3). e2mgr keeps DISCONNECTED nodebs and the TS xApp lists them, so the VM is reverted to the start snapshot after the probe.
- **AC6b needs its own probe.** `scripts/measure-ns3-timing.sh` accepts only `--repeats`/`--simtime` [V `:35-41`] and runs against a null sink. So `scripts/probes/probe-ns3-scale-ten-gnbs.sh` runs `--nMmWaveEnbNodes=10` with **11 live agents** (ports 38470 + cellId), lock-step pacing, the M7 capture settings, and completeness checks: every node CONNECTED, every seq emitted by every node, `ipcDropped = 0`. It records `wallPerSimS` and `du`/`df -BG` growth on the host and the VM.
- **UseIdealRrc smoke (informational):** one short run at `UseIdealRrc=false`, so that s10's simTime and the budget reflect the likely final RRC model. AC17's probe stays in P10.
- **Toolchain:** `tools/asn1-indep/` pins pycrate or asn1tools by version and sha256. Inputs:
  - E2AP v03.01 as used by e2sim [V `sim-e2-interface/e2sim/asn1c/GlobalE2node-en-gNB-ID.h:4`];
  - E2SM common and E2SM-RC text from `ric-app-rc/e2sm/e2sm-common.asn` and `e2sm-rc-2.0.asn`;
  - X2AP from 3GPP TS 36.423 (Zotero `3ML7Y29A`), with the ASN.1 text pinned by sha256.

  The image is saved as a tarball with its sha256 for the offline end run.

## Standards preflight (F10, F11)
- Check in Zotero that each document is present and record the key:
  - E2SM-RC v01.03 `PSHY8566` and v03.00 `JRDTL7XS` (§8 read from the PDF with `pdftotext -layout`, not the truncated `.zotero-ft-cache`);
  - KPM v03.00 `F82PYZVK`; E2GAP v08 `AE3NUEDK`; OAD v18 `TBVJDMLF`;
  - 3GPP TS 37.340 `E6VYJPXJ`, 38.300 `PSYCJSXT`, 38.323 `MSNDDXJH`, 36.423 `3ML7Y29A`;
  - and verify the carried keys: E2SM common v07.00 `QW6VJ83M`, E2AP v03.00 `WEE5IEXF`, 3GPP TS 28.552 `5SZUBP6M`, 3GPP TS 38.331 (for R-3's `MeasurementTimingConfiguration`).

  A missing document → PAUSE T4 now.
- F10: one M3-style run with kpm_sim and kpimon at a 100 ms subscription, as a dev probe only (kpimon config edited on the VM, not pinned). Record kpm_sim's reporting behaviour for P03.

## Files
- Create:
  - `tools/asn1-indep/` (Dockerfile, `build.sh`, self-test round-tripping E2 Setup (en-gNB, eNB), an E2SM-RC header and message, and an X2AP `ENDCX2SetupRequest`);
  - `scripts/probes/probe-e2-identity-setup.sh` (eNB + en-gNB setups with PPID 70, the eNB KPM subscription, graceful teardown, saved JSON and the capture);
  - `scripts/probes/probe-ns3-scale-ten-gnbs.sh`.
- Create (Markdown): `plans/reports/probe-<date>-GH-1-m10-prelude-probes.md`, holding the AC6 citations, AC6a/AC6b results, the UseIdealRrc smoke, the preflight table and the F10 result.

## Steps
1. AC6: record the citations; run both fixture ACKs against a live rc; record RestartCount.
2. Build `tools/asn1-indep`; run its self-test; save the image tarball and sha256.
3. Standards preflight; F10 probe.
4. AC6a on a running RIC: setups, nodeb JSONs, the eNB KPM subscription; then revert the VM.
5. AC6b: the 10-gNB probe; derive the AC15 simTime (step ≤ 45 min) and the s10 terms. Then the UseIdealRrc smoke.
6. Write the probe report; phase exit.

## Validation
- AC6: the report lists each claim with file:line at `a2282ee` plus the runtime result.
- AC6a:
  - both setups get an E2 SETUP RESPONSE on the decoded wire and e2mgr lists both CONNECTED;
  - meids match `^en_gnb_001_001_7f000001$` and `^enB_macro_001_001_[0-9a-f]+$`; the en-gNB `nbId` has 32 characters;
  - the eNB JSON has no `ranFunctions`, and the eNB subscription's decoded outcome (response or failure, with cause) is recorded.
- AC6b: `wallPerSimS`, `diskGiB` and the completeness flags are all true; the chosen simTime and its arithmetic are in the report.
- Preflight: every key listed as present, or PAUSE T4.

## Standards ledger (stub)
| Decision | Document, section | Zotero | Read |
|---|---|---|---|
| Global en-gNB ID / Global ENB ID in E2 Setup | E2AP v03.00 §9.2.6 | `WEE5IEXF` [C] | to cite |
| E2 transport, PPID 70 | E2GAP v08.00 §6.1 | `AE3NUEDK` | to cite |
| en-gNB ID 22–32 bits; macro eNB ID 20 bits | 3GPP TS 36.423 §9.2.112, §9.2.22 | `3ML7Y29A` | to cite |
| KPM subscription to an eNB node | E2AP v03.00 §8.2.1 | `WEE5IEXF` [C] | to cite |

## Risks
- e2mgr may reject an eNB or en-gNB type (High/Low–Medium). That is a Decision required by contract.
- submgr may refuse a subscription to an ENB node that has no RAN functions (High/Medium). The AC6a eNB subscription shows this. If it is refused, the eNB's KPM path needs a ruling before P06 (PAUSE T3).
- pycrate may not compile X2AP/E2AP as is (Medium/Medium). asn1tools is the second option.
- /mnt/data growth from the new images (Medium/Medium): track it against the budget line.

## Rollback
Probes and tools are additive. VM: revert to the start snapshot (also mandatory after AC6a).
