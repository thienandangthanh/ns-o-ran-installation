# Codex: 28.552 version for the strict lint, and sub-counters in names

Date: 2026-11-06 19:59 KST. Codex task, read-only, effort high, fresh thread. Spec texts were given as pdftotext extracts of 28.552 V20.2.0 and V17.17.0, 32.425 V19.0.0 and KPM v03.00 (page numbers are PDF pages). Verbatim answer:

Pin **28.552 V20.2.0** for this lint revision, but accept successor names only after checking the actual source semantics. Reject a blanket suffix-removal rule: KPM distinguishes subcounters from filters, and the present implementation cannot preserve meaningful labels through to Influx.

All specification references below use **PDF pages**, counted from the supplied texts. No files or state were changed.

**Question 1. Recommendation.** Use a fixed baseline of 28.552 V20.2.0 for NR measurements, 32.425 V19.0.0 for eNB measurements, and KPM v03.00’s adaptations. Record exact versions rather than making lint depend on whichever document is newest in Zotero later. Apply canonical successor renaming before the final semantic check; every remaining failure becomes `ns3.*`, preserving order and measId.

**Confidence.** High on the reference/version interpretation and PRB measurement continuity. High that the current TB-error source fails either version. The current DL PRB implementation still needs a separate semantic verdict.

**Why.** KPM v03.00 §2.1, p.4, references 28.552 without a version or release and says the latest version applies to nonspecific references. It therefore does **not** pin Release 17. Its 28.552 reference is independent of 3GPP’s own convention for references within a particular release.

The bare PRB measurements are successors with the same aggregate meaning:

- V17.17.0 §5.1.1.2.1–.2, pp.33–34, defines `RRU.PrbTotDl/Ul`: usage of PRBs for any purpose, percentage averaged over the measurement period, integer 0–100, object `NRCellDU`.
- V20.2.0 §5.1.1.2.1–.2, pp.44–45, retains those properties under `RRU.PrbDl/Ul`. It adds optional PLMN, slice and resource-type breakdowns and UE-type filtering.

Thus the **unpartitioned measurements are equivalent for this naming decision**, although their complete definition text is no longer identical. Neither name means a number of PRBs.

That equivalence does not validate today’s values. The current source uses a fixed 139-PRB denominator and leaves UL usage as an unimplemented zero ([mmwave-enb-net-device.cc:1371](ns-3-mmwave-oran/src/mmwave/model/mmwave-enb-net-device.cc:1371)). UL should fail the strict source check and receive a vendor name. DL derives from symbol occupancy with intermediate integer accumulation, so it needs justification against the period-wide PRB definition before receiving `RRU.PrbDl` ([same file:1190](ns-3-mmwave-oran/src/mmwave/model/mmwave-enb-net-device.cc:1190)).

The TB spelling correction is also insufficient. V17.17.0 §5.1.1.7.4, p.78, spells the name `TB.ErrToltalNbrDl.X`; V20.2.0 §5.1.1.7.4, pp.112–113, uses `TB.ErrTotNbrDl.X`. Both count faulty receptions indicated by **NACK or DTX**, including initial and retransmitted TBs. The map’s `ErrTotal` spelling matches neither. More seriously, its source increments whenever the redundancy version is nonzero, counting retransmissions regardless of whether that attempt failed ([mmwave-phy-trace.cc:250](ns-3-mmwave-oran/src/mmwave/helper/mmwave-phy-trace.cc:250)), then exports that count under the error name ([helper:131](oran-interface/helper/mmwave-indication-message-helper.cc:131)). Under the user’s rule, this becomes a vendor retransmission-count name.

kpimon does not require these particular spellings: it obtains names from the advertised lists and assigns values by position. The patched UE path writes `values[tmpUeKpi[i]]` ([control.go.patch:283](O-RAN-Testbed-Automation/RAN_Intelligent_Controllers/Near-Real-Time-RIC/install_patch_files/xApps/kpimon-go/control/control.go.patch:283)). However, **ad-cell explicitly expects the old PRB names**, so renaming has a consumer impact ([InfluxDBManager.py.patch:44](O-RAN-Testbed-Automation/RAN_Intelligent_Controllers/Near-Real-Time-RIC/install_patch_files/xApps/ad-cell/src/manager/InfluxDBManager.py.patch:44)). I found no corresponding TB-error-name dependency in the inspected xApp patches.

**Strongest counter-argument.** A Release-17 baseline better matches the inherited implementation’s history and reduces migration work. That is a defensible explicit project baseline, but KPM v03.00 does not require it, and it would not repair the source/counting-point mismatches above.

**What the proposal misses.** “Successor exists” and “this row implements the successor” are separate checks. Also, the present lint is structural: it checks neither clauses nor source semantics, and its required fields contain no standards reference ([lint-metric-map.py:37](O-RAN-Testbed-Automation/RAN_Intelligent_Controllers/Near-Real-Time-RIC/ns3_e2_agent/tests/lint-metric-map.py:37)). I ran it read-only with the eNB configuration: **118 rows, zero findings**. That is not AC16 validation. Canonicalization also needs recording as an explicit refinement of the earlier blanket “failure → vendor name” ruling.

**Question 2. Recommendation.** Flag genuine standard subcounter suffixes when their dimensions are missing from KPM labels. For P6, preserve unsupported breakdowns under descriptive `ns3.*` names unless a correctly defined aggregate already exists. Treat `_Filter` separately. “Drop the suffix and report the total” is honest only when both the measurement definition permits that aggregate and the source actually computes it.

**Confidence.** High on the specification distinction and current implementation limitations. Medium on implementation effort: the affected paths are identifiable, but no prototype or runtime experiment was performed.

**Why.** KPM v03.00 §8.3.9, p.30, assigns subcounters to Measurement Labels. §8.3.11, pp.30–32, provides actual **5QI, QCI, MU-MIMO layer and distribution-bin values**. Thus `.1` can represent a layer dimension only with the appropriate layer value; literal `.5QI` or `.QCI` is not an actual classification. `.Qos` requires establishing which QoS dimension the source really measures.

28.552 V20.2.0 §3.3, p.32, establishes measurement families; the operational naming rules are in §4.1–4.4, pp.33–35. They distinguish dotted subcounters from filters and allow omission only when the particular measurement definition permits it.

Crucially, **`_Filter` is not categorically forbidden by KPM**. KPM §7.9.1, p.14, explicitly lists `_Filter` names. §8.3.11, pp.30–31, says QCI bounds, ARP bounds and bitrate-range labels apply only when the associated name ends in `_Filter`. Meanwhile §8.3.9 specifies PrintableString, and the current lint excludes underscores. That is a specification/representation tension to record explicitly; silently deleting `_Filter` does not resolve it.

Label support currently stops at ASN.1 capability:

- `MetricRow` has no label representation ([metric-map.hpp:23](O-RAN-Testbed-Automation/RAN_Intelligent_Controllers/Near-Real-Time-RIC/ns3_e2_agent/src/metric-map.hpp:23)).
- The agent emits `noLabel` for both cell and UE measurements ([encoder:141](O-RAN-Testbed-Automation/RAN_Intelligent_Controllers/Near-Real-Time-RIC/ns3_e2_agent/src/kpm-indication-message.cpp:141), [encoder:192](O-RAN-Testbed-Automation/RAN_Intelligent_Controllers/Near-Real-Time-RIC/ns3_e2_agent/src/kpm-indication-message.cpp:192)).
- kpimon’s subscription encoder likewise requests `noLabel` ([wrapper.c.patch:1213](O-RAN-Testbed-Automation/RAN_Intelligent_Controllers/Near-Real-Time-RIC/install_patch_files/xApps/kpimon-go/e2sm/wrapper.c.patch:1213)).
- Its storage path keys values by measurement name, without preserving measurement-label dimensions.

Supporting labels therefore requires map/schema, subscription, indication, decoding and storage changes. Existing ASN.1 structures help, but this is more than an encoder adjustment. Stripping several names to the same base also violates today’s unique-name lint and would overwrite values in kpimon’s name-keyed map ([lint:82](O-RAN-Testbed-Automation/RAN_Intelligent_Controllers/Near-Real-Time-RIC/ns3_e2_agent/tests/lint-metric-map.py:82)).

An aggregate alternative can work. For example, 28.552 §5.1.1.7.1, pp.111–112, explicitly supplies `TB.TotNbrDlInitial` alongside modulation breakdowns. But renaming an existing modulation-specific count to that total would be false. The current modulation counters also increment independently of the initial-transmission branch, so labels alone would not correct those rows ([mmwave-phy-trace.cc:264](ns-3-mmwave-oran/src/mmwave/helper/mmwave-phy-trace.cc:264)).

**Strongest counter-argument.** Implementing labels now preserves standard identities and useful dimensions while avoiding a growing vendor namespace. That is technically stronger if those dimensions are required, but it expands P6 into a consumer/storage contract change.

**What the proposal misses.** Labels cannot repair the wrong source, object or counting point. KPM v03.00’s label table also lacks a direct modulation-order label, so not every suffix has an obvious destination. Finally, `noLabel` means no subcounter; it does not prove that the value is a valid total. The `Sum` label is not a shortcut either: §8.3.11, p.31, defines it as cumulative from measurement start.

Effects on P6’s scope, order and budget:

- Register the fixed standards baseline, successor-name rule and label/filter policy before implementation. Expand P6 from its current single-volume design into the requested full-map semantic audit; update the eNB fallback list and affected consumers together.
- Keep the approved zero-valued en-gNB `DRB.PdcpSduVolumeDL/UL` rows and append the X2 rows. Measure actual X2 traffic at PDCP-SDU level: 28.552 §5.1.2.1.1.2, pp.183–184, and §5.1.2.1.2.2, pp.185–186. KPM §7.9.1, p.14, changes their wire unit to **Kbit, INTEGER**; the plan’s Mbit proposal needs correction.
- Preserve the P7-before-P9 dependency. Migrate R3′’s configured field, N6 reconciliation and related fixtures to X2 before judging predictor behavior; the field is presently fixed in [r3p-scenario.json:8](scripts/gates/r3p-scenario.json:8).
- Vendor renaming is the smaller implementation path. Full label preservation overlaps P15’s subscription work and requires a revised budget; the existing overall **11–13-hour estimate** does not explicitly size it ([phase plan:142](plans/261103-0008-GH-1-post-m9-realism-m10/phase-10-tc-counter-pdcp-realism-ideal-rrc.md:142)).

