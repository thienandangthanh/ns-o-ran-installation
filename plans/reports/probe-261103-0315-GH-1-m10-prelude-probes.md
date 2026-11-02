# M10 prelude probes (P01): rc claims, identity probe, scale probe, toolchain, standards preflight

Date: 2026-11-03 (KST). Plan: `plans/261103-0008-GH-1-post-m9-realism-m10/phase-01-rc-claims-identity-and-scale-probes.md`. Evidence root: `plans/261103-0008-GH-1-post-m9-realism-m10/evidence/`.

**VM start state:** `r3p-green` instead of the phase file's `f7-rerun-green`. It is a superset: the same M0–M7 install plus rc, the TS xApp and the stub at the M9 pins. AC6 needs a live rc, so the superset is required. The VM is reverted to `fresh-install` after the identity probe, because e2mgr keeps the probe nodebs.

## AC6: rc claims at the deployed rc SHA `a2282ee`

Source: OSC `ric-app-rc` at `a2282eedc9e32f60298bf530456ad367bef0824b` (`scripts/gates/rc-lib.sh:35`).

| Claim | Static evidence (file:line at `a2282ee`) | Runtime result |
|---|---|---|
| An ACK without ControlOutcome panics rc | `control/rcControl.go:345` calls `e2sm.GetControlOutcome(controlAck.ControlOutcome)` for every decoded ACK that is still awaited. `control/rcE2SmRc.go:134` then takes `unsafe.Pointer(&buffer[0])`, so an empty slice is an index-out-of-range panic with no `recover` | (pending: fixture A) |
| The ACK timer is 2 s and only logs | `xapp-descriptor/config.json:72` sets `"controlAckTimer" : 2`. `control/rcControl.go:161-164` reads it as seconds. `:171-181` deletes the map entry on expiry and returns, with only a log line ("Send ErrorIndication message on Timeout" is a comment, `:179`) | (pending: fixture B) |
| A late ACK is dropped | `control/rcControl.go:334-339`: an InstanceId missing from the map logs "RIC_CONTROL_REQ has been deleted!" and returns before the outcome decode | (pending: fixture B) |

## AC6a: identity probe
(pending)

## AC6b: scale probe (10 gNBs)
(pending)

- **UseIdealRrc smoke (informational): not runnable at the M9 pins.** scenario-zero sets `ns3::MmWaveHelper::UseIdealRrc` to `true` with `Config::SetDefault` after `cmd.Parse` (`ns-3-mmwave-oran/scratch/scenario-zero.cc:356`, `:483`), so no command-line value reaches it. Making it settable is T-C code, which may not land before checkpoint 2. AC17's real probe stays in P10. The s10 budget therefore uses the ideal-RRC rate, and P10/P11 re-measure.

## Toolchain (`tools/asn1-indep`)
- Commit `735e2a7`. Image `localhost/asn1-indep:aab70be470e0803c`, 167 MB, saved as `tools/asn1-indep/dist/asn1-indep-aab70be470e0803c.tar` (sha256 `9bfed29f426e045a7a6b058491b342cc8ffe52455eea9e898bd2d9fba76917b2`; the tarball is not in git).
- pycrate 0.8.1 pinned by hash. Inputs: E2AP v03.01, E2SM v03.01 and E2SM-KPM v03.00 from OSC `sim/e2-interface`; E2SM common and E2SM-RC from rc `a2282ee`; X2AP (3GPP TS 36.423 Rel-18) and NR RRC (3GPP TS 38.331 Rel-18, ≥ v18.6.0) from pycrate's bundled modules, recompiled byte-equal from pinned text. Pins are in `tools/asn1-indep/asn/SOURCES.txt`.
- Self-test 45/45 offline (`--network=none`). Every committed asn1c capture of E2AP (RIC control ACK and failure) and all 30 E2SM-RC control headers decode and re-encode byte-equal.
- Three build-time edits to a temporary copy of the ASN.1, none of which changes a wire byte against the spec: a missing `RICtimeToWait` import, the `RICQuery*` import spelling, and `RANParameter-ID` written with the spec's bound `(1..4294967295, ...)` instead of rc's `(1..2^32, ...)`.

### New deviation found: RANParameter-ID is encoded unconstrained (proposed row P14)
- **Spec:** O-RAN E2SM-RC v03.00 ASN.1, `RANParameter-ID ::= INTEGER (1..4294967295, ...)` (Zotero `JRDTL7XS`, p. 287). Under X.691 APER this is an extensible constrained whole number: id 1 encodes as `00 00`.
- **Deployed:** rc `a2282ee` `e2sm/e2sm-rc-2.0.asn:200` writes `INTEGER (1..2^32, ...)`, which is not valid ASN.1 value notation. asn1c dropped the constraint (`e2sm/lib/RANParameter-ID.c:36-38`, `APC_UNCONSTRAINED`), so rc puts each id on the wire as an unconstrained INTEGER (`01 01` for id 1). The agent's RC codec is generated from the same rc tree (`rc-lib.sh` header: "the agent's codec uses the same one"), so rc and the agent agree with each other and disagree with the spec. Every RC control message, every outcome with items and every RC RAN function definition is affected.
- **Effect on this goal:** the P01 probes do not decode RAN parameters. AC12, however, requires a target encoded by an independent spec encoder to be applied, which the current agent cannot decode. Fixing it means correcting the bound in the rc fork's ASN.1 and regenerating rc's and the agent's codecs inside the T-A fork patches (P06/P07). No code is written for it before checkpoint 1.
- **Status:** registered for the user at Stop A, as a scope confirmation: it is not one of P1–P13/N5, but AC12 and R1 ("fix to spec") imply it.


## Standards preflight (F11)

| Document | Zotero key | Present |
|---|---|---|
| O-RAN E2SM-RC v01.03 | `PSHY8566` | yes (PDF) |
| O-RAN E2SM-RC v03.00 | `JRDTL7XS` | yes (PDF) |
| O-RAN E2SM-KPM v03.00 | `F82PYZVK` | yes |
| O-RAN E2GAP v08 | `AE3NUEDK` | yes |
| O-RAN OAD v18 | `TBVJDMLF` | yes |
| 3GPP TS 37.340 | `E6VYJPXJ` | yes |
| 3GPP TS 38.300 | `PSYCJSXT` | yes |
| 3GPP TS 38.323 | `MSNDDXJH` | yes |
| 3GPP TS 36.423 | `3ML7Y29A` | yes |
| O-RAN E2SM common v07.00 (carried) | `QW6VJ83M` | yes |
| O-RAN E2AP v03.00 (carried) | `WEE5IEXF` | yes |
| 3GPP TS 28.552 (carried) | `5SZUBP6M` | yes |
| 3GPP TS 38.331 (R-3 `MeasurementTimingConfiguration`) | none | **missing** |

**T4 on 3GPP TS 38.331.** The phase file says a missing document is PAUSE T4 now. The document is first needed in P06 (R-3's X2AP served-cell constants), and Stop A comes before P06, so the T4 is deferred to Stop A with the user notified on 2026-11-03 at 03:10 KST. This is a recorded deviation from "PAUSE T4 now". No P01–P05 decision depends on 3GPP TS 38.331.

## F10: kpm_sim and the subscription period
- **Static finding:** kpm_sim (OSC `sim/e2-interface` at `da6f82f`, the tree NIST builds it from) ignores the event trigger. `e2sim/e2sm_examples/kpm_e2sm/src/kpm/kpm_callbacks.cpp:590-592` reads `ricEventTriggerDefinition` and comments "We are ignoring the trigger definition". The report loop (`:136-156`) replays `reports.json` with a fixed 50 ms sleep after each indication (`:390`, `:527`) and ends when the file ends (the finite burst seen in M2/M3).
- **Consequence for P03:** any kpimon reporting period, 100 ms included, leaves kpm_sim's output unchanged. M2/M3 predicates that count kpm_sim indications do not depend on the period.
- **Runtime confirmation:** runs in P03 step 2 (M3 with kpimon at 100/100). kpimon's period is hard-coded until P03 makes it configurable (`control.go.previous:437`), so a P01 runtime probe would need an unpinned kpimon rebuild for an answer the source already gives.
