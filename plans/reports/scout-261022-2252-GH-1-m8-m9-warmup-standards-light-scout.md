# M8–M9 goal-warmup light scout: UE ID, UL measName, reject causes (2026-10-22 22:52 KST)

This is the pre-contract light scout of the `/ak:goal-warmup` brief (`kongming-261022-2105…` §4, items 1–3). The spec versions follow the decision record's 22:30 and 22:50 KST amendments. Every spec was read from its Zotero PDF (path from zotero-mcp, text from `pdftotext -layout`). The scout was read-only; it wrote nothing except this report.

**Outcome.** Item 1 confirms a new deviation (P4): the UE ID that rc and the TS xApp put on the wire is the 5GC form, but our UEs are EN-DC UEs on EPC. Item 1 also turned up a related, pre-existing deviation (P5): every agent, the eNB included, registers as a `gNB`-type E2 node. Item 2 finds no new deviation in the planned UL metric if it is sent as `DRB.PdcpSduVolumeUL`, INTEGER, in kbit. It does find a pre-existing unit and type deviation (P6) in the DL volume row that M6 already ships. Item 3 is confirmed. P4–P6 need the user's ruling inside the contract.

## 1. UE ID for an EN-DC UE (E2SM common v07.00, `QW6VJ83M`)

- **E2SM-RC v03.00** (`XRWZU3SS`) defines the Control Header's UE ID as "defined in [4] clause 6.2.2.6", where [4] is the E2SM common spec.
- **E2SM common v07.00 §6.2.2.6** (pp. 12–13) makes the CHOICE depend on the E2 node type:
  - `gNB`: "E2 Node of type gNB **when connected to 5GC**". Mandatory: AMF UE NGAP ID and GUAMI.
  - `en-gNB`: "E2 Node of type en-gNB **when connected to EPC and EN-DC is established**". Mandatory: MeNB UE X2AP ID (§6.2.3.23) and Global eNB ID (§6.2.3.9).
  - `eNB`: "E2 Node of type eNB when connected to EPC". Mandatory: MME UE S1AP ID (§6.2.3.26) and GUMMEI.
  - The ASN.1 (p. 30) has the same split: `gNB-UEID UEID-GNB`, `en-gNB-UEID UEID-EN-GNB`, `eNB-UEID UEID-ENB`.
- **§6.2.3.16 AMF UE NGAP ID**: "uniquely identifies a UE over the NG interface within a NG-RAN node", per 3GPP TS 38.413 §9.3.3.1. It is a context ID assigned by the AMF, not a subscriber identity.
- **What the wire carries.** rc builds Control Header Format 1 with `UEID-GNB` (AMF-UE-NGAP-ID, GUAMI, F1AP and E1AP lists; `scout-261022-1026…` §5). The TS xApp `stoi`s the UE id, and the agent maps AMF-UE-NGAP-ID to the decimal IMSI (journal 2026-10-22 G6).
- **Verdict: deviation P4 (new).** The scenario is EN-DC on EPC (ns-3 mmWave, LTE master eNB). For a control addressed to a gNB agent, the faithful choice is `en-gNB-UEID` (MeNB UE X2AP ID + Global eNB ID). For a control addressed to the eNB agent, it is `eNB-UEID` (MME UE S1AP ID + GUMMEI). The wire instead uses `gNB-UEID` and puts the IMSI in a field that 3GPP TS 38.413 defines as an AMF context ID.
- **Related, pre-existing: deviation P5.** **E2AP v03.00 §9.2.6** (`WEE5IEXF`) says the `en-gNB` choice is used "when E2 Node supports en-gNB mode only" and the `eNB` choice "when E2 Node supports eNB mode only". The `gNB` choice is for gNB mode, where Global en-gNB ID is optional. The agent emits `GlobalE2node_ID_PR_gNB` with only a Global gNB ID for both kinds, the eNB agent included (`ns3_e2_agent/src/e2ap-builders.cpp:83-93` @725b167). That has been the case since M5. Seen from the RIC, the nodes are 5GC gNBs, so `gNB-UEID` is at least self-consistent with how the nodes present themselves. Changing the node type would touch e2mgr naming (`gnb_…`) and the TS xApp's cell-key search (N5).

## 2. UL measName and unit (3GPP TS 28.552 V20.2.0 `5SZUBP6M`; E2SM-KPM v03.00 `F82PYZVK`)

- **3GPP TS 28.552 §5.1.2.1.2.1** "UL Cell PDCP SDU Data Volume": the bits delivered from PDCP to higher layers, at the PDCP SDU level, measured on NRCellCU, unit Mbit. Item e): "The measurement name has the form DRB.PdcpSduVolumeUL_Filter, where filter is a combination of PLMN and QoS level and S-NSSAI …". So `_Filter` is a placeholder for a filter value, not a literal suffix. The DL counterpart is §5.1.2.1.1.1 `DRB.PdcpSduVolumeDL_Filter`.
- **E2SM-KPM v03.00 §8.3.9**: the Measurement Name is `PrintableString(SIZE(1..150,...))`, "one of the measurement names specified in TS 28.552 …"; "the subcounters are represented by the Measurement Labels defined in 8.3.11". PrintableString has no `_`. That is why the agent's lint rejects `_` (`tests/lint-metric-map.py:10`).
- **E2SM-KPM v03.00 §7.9.1** changes the unit to **kbit**, data type **INTEGER**. Note: the KPM table cites the older 3GPP TS 28.552 clause numbers (UL = 5.1.2.1.2.2), whereas V20.2.0 numbers it 5.1.2.1.2.1. Record that version gap.
- **Pick (no deviation):** wire name `DRB.PdcpSduVolumeUL` with no label, which is the unfiltered whole-cell total, plus `legacyName` `DRB.PdcpSduVolumeUL_Filter`, type INTEGER, unit kbit. The name rule copies the DL precedent (`schema/metric-map.v1.json`, measId 11).
- **Pre-existing: deviation P6.** The shipped DL volume row sends `QosFlow.PdcpPduVolumeDL` as **REAL in bytes per period** (measId 11), whereas E2SM-KPM v03.00 §7.9.1 says INTEGER in kbit (3GPP TS 28.552 §5.1.3.6.1.1). M6 proved the Influx values equal the ns-3 trace bit for bit with that encoding. Changing it would change the M6 and M7 evidence.
- **Planning risk (no decision needed now).** A counter in whole kbit per 100 ms period could stay constant at a low UL rate, and then `adfuller` raises. P6 of the plan picks a UL rate that keeps the series varying.

## 3. Agent-local reject causes (E2AP v03.00 §9.2.1)

- The enumerated values `ran-function-id-invalid`, `action-not-supported`, `control-message-invalid` and `control-failed-to-execute` are all in E2AP v03.00 (`WEE5IEXF`, CauseRICrequest ASN.1). They match the decision record's 21:45 KST erratum. There is no change and no deviation.

## Standards-ledger rows (carry into the plan)

| Decision | Document, version, section | Zotero | Read |
|---|---|---|---|
| UE ID choice on the control path | E2SM common v07.00 §6.2.2.6, §6.2.3.16/.23/.26; E2SM-RC v03.00 (UE ID → [4] 6.2.2.6) | `QW6VJ83M`, `XRWZU3SS` | 2026-10-22 |
| E2 node type in E2 Setup | E2AP v03.00 §9.2.6 | `WEE5IEXF` | 2026-10-22 |
| UL measName, type, unit | 3GPP TS 28.552 V20.2.0 §5.1.2.1.2.1; E2SM-KPM v03.00 §8.3.9, §7.9.1 | `5SZUBP6M`, `F82PYZVK` | 2026-10-22 |
| Agent-local reject causes | E2AP v03.00 §9.2.1 (CauseRICrequest) | `WEE5IEXF` | 2026-10-22 |

## Unresolved questions

1. P4: record it as an accepted deviation (fixed in the post-M9 realism pass), or fix it inside M8–M9? Fixing it needs an rc change plus ns-3 X2AP/S1AP IDs, which is an outcome change.
2. P5 and P6 (pre-existing since M5/M6): record them for the post-M9 pass, or fix them now? Fixing them changes M5–M7 evidence and the TS xApp cell-key path.
