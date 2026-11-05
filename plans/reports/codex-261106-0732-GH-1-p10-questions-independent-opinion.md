# Codex: independent opinion on the five P10 user questions

Date: 2026-11-06 07:32 KST. Codex task, read-only, effort high, fresh thread. Brief: /tmp/claude-1000/-home-andang-orca-workspaces-ns-o-ran-installation-migrate-l-release-NIST-1-8-0/fdfe16a0-64f3-4277-9ef6-e00f0ee9ba0c/scratchpad/codex-p10-questions-brief.md (scratchpad). Codex read the code, not the spec PDFs. Cross-checked by kongming in `kongming-261106-0500-GH-1-p10-pre-registration-verification.md` §"Cross-check of Codex (2026-11-06)".

Verbatim answer:

I recommend fixing UB, accepting Q1’s vendor renames, choosing Q2 Option A, accepting Q3 with a stricter fallback, and choosing **12-bit SNs for Q4**.

I made no changes and ran no builds or simulations. Standards conclusions below depend on the supplied clause/page citations; I did not read the spec PDFs.

**UB**

Recommendation: Approve Amendment 4 and fix the neighbour loop in its own ns-3 commit before P6. Preserve the historical references and attribute the resulting cp3 IPC changes explicitly.

Confidence: High.

Why: Decrementing `begin()` is undefined regardless of whether a particular library happens to produce usable output. The defect is visible in the report path at [mmwave-enb-net-device.cc:1001](ns-3-mmwave-oran/src/mmwave/model/mmwave-enb-net-device.cc:1001). I independently tallied the saved r2 live1 IPC: node 2 has one neighbour in all 416 UE records; node 3 has zero in 82 of 178. Banking cp3 with this known defect would preserve an implementation-dependent measurement artefact.

Strongest counter-argument: It does not feed the current R3′ predictor, and fixing it adds another build, regression cycle and reference difference. Disclosure would preserve the present scope and continuity evidence.

Missed by both reports: The fix needs more than a two-entry regression. With exactly eight map entries, `nNeighbours` remains eight although only seven entries are neighbours; CSV padding then uses that intended count rather than the emitted count. Check singleton maps, ties and both sides of the eight-neighbour cap. Derive eligibility after excluding the serving cell and pad from the actual emitted count. See [mmwave-enb-net-device.cc:993](ns-3-mmwave-oran/src/mmwave/model/mmwave-enb-net-device.cc:993) and [:1025](ns-3-mmwave-oran/src/mmwave/model/mmwave-enb-net-device.cc:1025).

**Q1 — P6**

Recommendation: Rename every demonstrably nonconforming measurement to an accurately described `ns3.*` name, preserving order and measId. Keep the existing IPC source keys where appropriate. Treat “about 20 of 38” as a planning estimate until the complete registry exists.

Confidence: High on the MAC mismatch and rename; conditional on the supplied standards citations for each retained standard name.

Why: The value accumulates transport-block sizes, including retransmissions, at [mmwave-phy-trace.cc:250](ns-3-mmwave-oran/src/mmwave/helper/mmwave-phy-trace.cc:250), then is emitted under the PDCP name at [mmwave-indication-message-helper.cc:132](oran-interface/helper/mmwave-indication-message-helper.cc:132). Given the supplied split-only/DC-excluded definition, changing units or sourcing another PDCP statistic cannot rescue that name here. A recorded deviation also falls short of the locked “fixed” outcome.

Strongest counter-argument: Broad renaming changes advertised names and downstream Influx fields. Keeping familiar names with explicit deviations would reduce consumer disruption, but requires an approved departure from the contract.

Missed by both reports: A source-section rule cannot establish measurement ownership. `/cuUp` currently contains MN-hosted PDCP volume credited to the SN—the very P9 defect—at [mmwave-enb-net-device.cc:693](ns-3-mmwave-oran/src/mmwave/model/mmwave-enb-net-device.cc:693). The registry must distinguish layer from owning node, counting event and aggregation interval. Consequently, P6 cannot certify the whole map’s semantic correctness while P9 remains unfixed. Resolve that acceptance dependency before code; do not quietly exempt P9 or rename it into apparent correctness.

**Q2 — P9**

Recommendation: Choose **Option A**: retain own-PDCP DL/UL measurements with zero values for this topology, append X2 DL/UL measurements for the routed volume, and approve the precise T3 substitutions that make the predictor consume X2DL. Preserve its formula, window, thresholds and decision rule.

Confidence: High that the present attribution is wrong; medium-high that Option A is the correct replacement, conditional on the supplied 28.552/Annex A.25 interpretation.

Why: Both LTE and NR sends invoke the same MN PDCP trace, at [mc-enb-pdcp.cc:221](ns-3-mmwave-oran/src/lte/model/mc-enb-pdcp.cc:221) and [:238](ns-3-mmwave-oran/src/lte/model/mc-enb-pdcp.cc:238). The current en-gNB calculation cannot separate those legs. Option A preserves the meaning of the existing measurement IDs and makes the distinction between local PDCP activity and MN–SN transfer explicit. The predictor itself merely sums certified integers; changing its input key need not change its arithmetic ([r3p-predictor.py:44](scripts/gates/r3p-predictor.py:44)).

Strongest counter-argument: A′ is leaner: it avoids permanently zero fields and additional measurement rows. Its disadvantage is repurposing existing IDs and removing explicit own-PDCP evidence. B is cheaper operationally but retains the semantic defect under the supplied clause reading.

Missed by both reports: Once each audit event identifies its SN leg, overlapping UE contexts must not permit aggregation to conceal incorrect cell attribution. The current judge joins overlapping cells and compares their combined totals at [check-pdcp-volume-totals.py:160](scripts/gates/check-pdcp-volume-totals.py:160). Retaining that allowance could let volume move between cells while the sum passes. Require per-cell reconciliation and a negative fixture that swaps attribution while preserving the total.

Also define “first send” precisely. Forwarding can strip a PDU and re-enter MN PDCP at [lte-enb-rrc.cc:1231](ns-3-mmwave-oran/src/lte/model/lte-enb-rrc.cc:1231). Counting every subsequent X2 submission and counting each original SDU once are different measurements.

**Q3 — eNB clauses**

Recommendation: Accept the explicit interpretation that E-UTRAN measurements use TS 32.425, with applicable KPM conversions. Request manual addition of the selected 32.425 version to Zotero. If it remains unavailable, vendor-rename entries whose complete applicability cannot be established.

Confidence: High on the need for RAT-appropriate authority; individual 32.425 mappings remain unverified against Zotero.

Why: AC16 needs the specification governing the actual measurement. An eNB label alone is insufficient: the registry must also establish bearer applicability, counting point and per-UE conversion. The code already demonstrates why matching a name and unit is inadequate: the eNB’s apparent SDU volume comes from PDCP **PDU** bytes at [lte-enb-net-device.cc:1108](ns-3-mmwave-oran/src/lte/model/lte-enb-net-device.cc:1108).

Strongest counter-argument: KPM’s conversion table already supports some eNB names, types and units; retaining those with an “unverified against Zotero” disclosure reduces churn.

Missed by both reports: Their fallback is too permissive if presence in that conversion table alone authorizes retention. Type/unit evidence does not establish source semantics. AC20’s disclosure requirement does not itself waive AC16’s matching requirement. Retain a standard name without 32.425 only where the available authority establishes the complete relevant definition; otherwise use the vendor fallback or obtain an explicit exception.

**Q4 — P7**

Recommendation: Choose **12-bit SNs**, with an explicit NR header class and verified MC consumer paths. Fix the existing rollover defect in a separate prerequisite commit before P7, with its own attribution and regression slot.

Confidence: Medium on choosing 12 over 18; high that either width is permitted under the supplied citations and that the existing recovery logic mishandles rollover.

Why: The supplied clauses mandate NR PDCP here but permit either width. This workload does not establish a need for widening: DL packets are generated every 500 μs at [scenario-zero.cc:691](ns-3-mmwave-oran/scratch/scenario-zero.cc:691). Twelve bits minimizes changes to SN storage, status interfaces and packet sizes. A visible cp3 byte difference is useful diagnostically, but cannot establish NR provenance at either width. Bind the trace evidence to the verified MC implementation path and the 38.323 layout tests.

The rollover repair is independently meaningful at cp2: recovery indexes packets by raw SN at [lte-rlc-am.cc:1808](ns-3-mmwave-oran/src/lte/model/lte-rlc-am.cc:1808), and predecessor selection uses a non-modular inclusive interval at [lte-enb-rrc.cc:1105](ns-3-mmwave-oran/src/lte/model/lte-enb-rrc.cc:1105) and [lte-ue-rrc.cc:1774](ns-3-mmwave-oran/src/lte/model/lte-ue-rrc.cc:1774). Separating it respects the bisection purpose of “one fix per commit.”

Strongest counter-argument: Eighteen bits provides substantially more headroom and aligns with kongming’s stated deployment expectation. Grouping rollover with P7 is defensible because the accepted design expressly includes rollover. However, the deployment expectation is reported belief, and neither benefit makes 18 bits necessary here.

Missed by both reports: The proposed packet-tag discriminator conflicts with existing forwarding. The eNB calls `RemoveAllPacketTags()` before forwarding the still-header-bearing PDU to the target RLC ([lte-enb-rrc.cc:1190](ns-3-mmwave-oran/src/lte/model/lte-enb-rrc.cc:1190), [:1219](ns-3-mmwave-oran/src/lte/model/lte-enb-rrc.cc:1219)). A mandatory tag would disappear. Use reliable bearer context or deliberately preserve the discriminator, and test this exact path.

Findings that should change order or budget:

- Resolve the P6/P9 semantic-lint dependency before registering their final predicates.
- Add a separate rollover commit before P7 under my 12-bit recommendation. Its live effects need an additional bisection and regression slot.
- Expand UB boundary tests, P7 discriminator-survival coverage and P9 per-cell attribution fixtures before their code.
- Keep kongming’s additional V3 route and repeated agent/kpimon build costs. The 14–17 h estimate is provisional; it does not establish the cost of these additional checks and commit boundary. Preserve the measured disk guards and M5–M7 requirement after every ns-3 or agent change.

