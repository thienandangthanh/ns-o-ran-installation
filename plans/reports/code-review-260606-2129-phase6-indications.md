# Code Review — Phase 6 (E2SM-KPM v3.00 RIC indication) port

Date: 2026-06-06
Reviewer: code-reviewer
Scope: 5 changed files (indication builder + wiring + offline test + harness + sub-handler out-params)
Focus: memory safety (raw C ASN.1 + malloc/free), v3 ASN.1 assembly correctness, Phase-5 pattern consistency.

## Verdict

PASS. No critical or high issues. The memory-ownership model is correct and, in two
places, strictly safer than the OSC reference it mirrors. Findings are all low/informational.

## Struct-layout verification (basis for the memory verdict)

Checked the vendored asn1c headers (`oran-e2sim/e2sim/asn1c/`) to confirm by-value vs pointer members:

| Field touched by builder | Declared as | Shallow-copy + free-wrapper correct? |
|---|---|---|
| `MeasurementDataItem.measRecord` | `MeasurementRecord_t` (by value, holds `A_SEQUENCE_OF` → heap `list.array`) | YES |
| `E2SM_KPM_IndicationMessage_Format1.measData` | `MeasurementData_t` (by value) | YES |
| `MeasurementInfoItem.labelInfoList` | `LabelInfoList_t` (by value) | YES |
| `LabelInfoItem.measLabel` | `MeasurementLabel_t` (by value) | YES |
| `MeasurementLabel.plmnID / .sliceID` | pointers (assigned once) | YES (single owner) |
| `IndicationHeader_Format1.colletStartTime` | `TimeStamp_t`=OCTET_STRING (by value) | YES (written in place) |

Because each wrapper struct is embedded by value in its parent, `parent.member = *wrapper;
free(wrapper)` copies the small struct (including the `list.array` pointer that
`ASN_SEQUENCE_ADD` heap-allocated) into the parent and frees only the now-redundant wrapper
shell. The deep heap (`list.array`, `.buf` blobs, `incompleteFlag`, `measID`) is preserved with
exactly one owner. No use-after-free, no double-free, no leak.

## SendIndication ASN_STRUCT_FREE safety (the deliberate divergence from encode_kpm.cpp)

`SendIndication` deep-frees `ihead`/`imsg` via `ASN_STRUCT_FREE` after encoding
(kpm-indication-builder.h:284-285). This DIFFERS from encode_kpm.cpp, which leaks. Verified safe:
the free walk descends Format1 → measData items (frees `incompleteFlag`) → measInfoList items →
`labelInfoList.measLabel.plmnID`(→`.buf`) + `.sliceID`(→`sST.buf`, `sD`→`.buf`) →
`measType.measID`. Every leaf has a single owner (confirmed above), so the recursive free is a
clean teardown — no aliased pointer is freed twice. The encode buffers (`hdr_buf`/`msg_buf`) are
produced by `asn_encode_to_new_buffer` (independent malloc) and freed separately. Correct.

This means the live loop (e2-setup-minimal.cc:109-113) sends N indications with NO per-report leak
— an improvement over the reference, and important since it runs in a bounded but repeated loop.

## E2AP_PDU no-free consistency with Phase 5

`generate_e2apv1_indication_request_parameterized` builds the proc-5 PDU using shallow copies of
the passed header/message bytes; the PDU is intentionally not freed
(kpm-indication-builder.h:271-275, documented at :242-244). This matches the Phase-5
`BuildSubscriptionResponse` rationale (kpm-subscription-handler.h:54-58). Consistent.

## Correctness checks (all pass)

- 8-byte timestamp: `KPM_TIMESTAMP_8B = "20200613"` (strlen 8); width matches OSC reference and the
  v3 TimeStamp OCTET STRING. Offline test asserts `.size == 8`. Correct.
- S-NSSAI / PLMN / SST / SD label assembly: field-for-field identical to
  encode_kpm.cpp:cell_meas...style_1 (plmn "747", sst "1", sd "100"). Correct.
- `asn_check_constraints` call: `err_len` is initialized to `sizeof(err_buf)` (300) before the call
  (kpm-indication-builder.h:208). Verified against constraints.c:86 — the function reads `*errlen`
  as input capacity. This is actually MORE correct than encode_kpm.cpp, which passes `errlen = 0`
  (zero capacity for the error formatter). No issue.
- `MeasurementRecordItem.choice.integer` is `unsigned long`; assigned `1`. No signedness problem.
- Sub-handler out-params (`out_requestorId`/`out_instanceId`): default `nullptr`, null-guarded
  before write (kpm-subscription-handler.h:147-148); offline test passes neither. Backwards
  compatible — pure additive change. Correct.

## Findings

### Low

L1. kpm-indication-test.cc:91-94 — `colletStartTime.size` is `size_t` (unsigned) but compared/
printed via `%d`. Format-string type mismatch (`%d` vs `%zu`). Test-only, failure-path diagnostic;
value 8 fits an int so no real misbehavior. Fix: `%zu` and cast or change the message.
(Note: the comparison `!= 8` itself is fine.)

L2. kpm-indication-builder.h:90 / 96 / 102 / 107 (and the OSC reference does the same) —
`calloc(1, strlen(sender))` allocates exactly `strlen` bytes with no NUL terminator. This is
CORRECT for OCTET_STRING/PrintableString (length-prefixed via `.size`, never NUL-read), but worth a
one-line comment so a future reader does not "fix" it into a buffer over-read. Informational.

### Informational

I1. `BuildDummyIndicationMessage` calls `exit(1)` on constraint failure (kpm-indication-builder.h:
212), mirroring OSC. Acceptable for the M5 dummy/offline path. When real ns-3 metric mapping lands
(M6/Phase 7) and values become dynamic/attacker-influenceable, prefer returning an error code over
`exit()` so the live node does not terminate on a single malformed report. Flag for Phase 7, not now.

I2. e2-setup-minimal.cc:98-103 — `KPM_IND_COUNT`/`KPM_IND_INTERVAL_MS` parsed with `strtol` and no
errno/endptr check; a non-numeric env yields 0 and is then clamped to the default (count) or 1000
(interval<0). Behavior is safe (clamps), just silently ignores garbage. Fine for a test harness env.

I3. The indication loop runs synchronously on the SCTP-read thread inside the subscription callback
(e2-setup-minimal.cc:109-113), blocking via `usleep` for count*interval (default 15s). For M5 this is
fine (single subscriber, dummy data), but it means no further SCTP input is serviced during the burst.
Acceptable per current scope; note for when multiple subscriptions or control messages are added.

## Behavioral checklist

- Concurrency: single-threaded callback; blocking loop noted (I3), acceptable for scope.
- Error boundaries: encode failures handled (returns -1, nothing sent); constraint failure exits (I1).
- API contracts: sub-handler out-params null-guarded, additive, backwards compatible.
- Memory: verified against struct layouts — no UAF / double-free / leak. Deep-free is correct.
- Input validation: env parse clamps garbage (I2); no external untrusted input on the build path (M5 dummy).
- Data leaks: static dummy values only; no PII/secrets.
- N+1 / queries: n/a.

## Unresolved questions

- None blocking. Confirm I1 (exit-on-constraint-failure → error-return) is tracked for Phase 7 when
  indication values become dynamic.
