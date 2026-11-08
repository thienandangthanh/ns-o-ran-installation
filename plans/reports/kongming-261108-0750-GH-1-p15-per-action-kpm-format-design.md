# Kongming counsel: P15 design, each KPM action answered in the format it asked for (2026-11-08 07:50 KST)

Advisory only. Model: Opus 5.5, per the caller's override of the Fable routing; this did not run on Fable. Pins read: harness 9b001f03, Testbed 03180a5 (`scripts/pins.conf:7`). kpimon was read as the upstream clone 8bbbbbb with this fork's patch stack applied in a scratch copy, so `control.go:N` below means the patched file. Every `file:line` was read at these pins.

Specs were read from the Zotero PDFs with pdftotext:
- E2SM-KPM v03.00 (`F82PYZVK`).
- E2AP v03.00 (`WEE5IEXF`).
- The L-release SubMgr `E2AP_if.h` (GitHub master): `cMaxofRICactionID = 16`, and `OctetString_t data[1024]` per action definition.

Wire facts were read with host tshark 4.7.4 from these committed pcaps:
- `evidence/m6/20261107T192911Z/m6.pcap`
- `evidence/m7/20261107T193119Z/m7.pcap`
- `evidence/p12/20261105T172146Z/p12-{a,c}.pcap`
- `evidence/e2i/20261106T171917Z/e2i.pcap`

I ran no VM step and no gate, and edited no repository file other than this report.

## TL;DR

- **Agent.** One decoder per action yields its format, its style and its CGI. The admission rule:
  - Format 1 needs style 1, plus a CGI that names one of the node's own cells: an NR CGI on an en-gNB, an E-UTRA CGI on the eNB.
  - Format 3 needs style 3.
  - G must equal T, as today.
  - Everything else is not admitted with ricRequest action-not-supported. That covers a foreign or absent CGI, Formats 2, 4 and 5, and a style that does not match its format.
- **Agent routing.** `Subscription` keeps each admitted action with its format.
  - `send_report` sends the cell message once under each Format 1 action, and the UE messages under each Format 3 action.
  - Nothing is lost. The UE data was always Format 2 and stays under Format 3. P9's X2DL and X2UL are cell rows 36 and 37, so they ride in the Format 1 message.
  - The indication count, the headers and the SN sequence are unchanged at C = 1.
- **kpimon.** It reads the node's own X2 request part from e2mgr and decodes it through cgo with the Testbed's asn1c X2AP codec, which gains a new "every served cell" export. This is the P05 route.
  - For the eNB, the e2mgr record already carries `enb.nodeConfigs`, verified in `evidence/e2i/20261106T171917Z/e2mgr-node-1.json`. Only kpimon's `types.go` lacks the field.
  - The NR-only byte-splice Format 1 encoder is replaced by a real Format 1 encoder that takes the CGI, encoding the measurements by ID.
  - The upstream action loop already numbers the actions 1..C then C+1 (`control.go:488-540`). Only its cell source and encoder change.
- **Harness, row 153.** C and the CGIs cannot come from the VM's tshark, whose dissection of the gNB E2 Setup stops in the RC RAN function definition (`e2i-wire-checks.py:162-165`). They come from the asn1-indep image, as e2i already does.
  - A new decoded-subscription sidecar holds the X2 served cells and every action's format and CGI, plus the admitted list.
  - The image tag stays `09aeabb8b0f99b0c`: no file under `tools/asn1-indep/` changes.
  - Nine sites now need the image loaded. That is infrastructure, not a new check.
- **Harness, rows 154 and 155.** The indication's action ID field is **`e2ap.RICactionID`**, not `e2ap.ricActionID`. Verified on host 4.7.4: `ricActionID` is empty in indications.
  - The request ID fields are `e2ap.ricRequestorID` and `e2ap.ricInstanceID`, and the function ID field is `e2ap.RANfunctionID`.
  - The VM's tshark must be checked with the two commands in section 4.1 before any code is written.
- **Commits.** Three Testbed commits (codec, agent, kpimon), then three harness commits (rows 153, 154, 155), then the pin and driver commit. One chain runs from revert point 3: M2–M7, I0, I2, p12 (new driver step), R3′ single, and I recommend e2i as well.
- **No row needs an amendment.** Nineteen open questions follow in section 6. None blocks the start of work. OQ-1 to OQ-3 fix agent behaviour, so they should be ruled before the agent commit.

## Reframed problem

Today the agent admits whatever REPORT action arrives in Formats 1–5 with G = T (`kpm-subscription-admission.cpp:118-139`). It then sends every message under the lowest admitted ID (`e2-session.cpp:180`, `:213-232`).

kpimon asks for Format 3 at ID 1, and the agent answers it with a cell Format 1 plus UE Format 2s. E2SM-KPM v03.00 §7.4.4.4 answers a Format 3 action with indication Format 2 only, so the Format 1 messages ride under an action that never asked for them. That breach is what is being fixed.

- **Decision:** how the request side (kpimon), the answer side (agent) and the judges change so that each indication's format equals its action's format. It must be checked from the decoded wire, with ID layout 1..C (Format 1, one per served cell) then C+1 (Format 3).
- **Requirements:**
  - rows 153–155 exactly as registered;
  - the P05 read: cells from the X2AP asn1c codec, and the eNB in the Format 1 set with an E-UTRA CGI;
  - SubMgr limits: at most 16 actions, and at most 1024 octets per definition;
  - fix to spec, with no compatibility mode.
- **Goals:** M5–M7, p12 and R3′ single stay green, with Influx, the TS xApp, r3p and s10 consumers unchanged in content.
- **Non-goals:**
  - honouring the measInfoList subset (OQ-4);
  - TS xApp's N1 parser on x2c (OQ-7);
  - a node tag in Influx (row 137, later commit);
  - D-06b-1.
- **Constraints:** one fix per commit; no plan or row IDs in code or commit messages; revert to `f7-rerun-green` before the builds; 34 GiB free on /home before kpimon, agent or p12 work.

## 1. The spec basis (read, with pages)

| Point | Text | Use |
|---|---|---|
| Style 1 → Action Format 1 → Indication Format 1 | E2SM-KPM v03.00 §7.4.2.2 (p.9), §7.4.2.4 (pp.9–10) | F1 action gets indication F1 |
| Style 3 → Action Format 3 → Indication Format 2 | §7.4.4.2 (p.10), §7.4.4.4 (p.11) | F3 action gets indication F2 only |
| CGI in Format 1 | §7.4.2.2: "shall be included" for measurement types confined in a single cell (e.g. NRCellCU); "may not be included" only if all are cell agnostic | en-gNB style-1 list holds DRB.PdcpSduVolume{UL,DL,X2UL,X2DL} (NRCellCU), so the CGI is mandatory there |
| Format 3 inherits the subscription rules | §7.4.4.2: "The rest of the subscription information follows the same as described in 7.4.2.2" | F3 would need a CGI once UE rows carry 3GPP cell-confined types; today all 58/17 UE rows are `ns3.*` (OQ-5) |
| CGI type | §8.2.1.2.1/§8.2.1.2.3 (p.22), §8.3.20: CGI CHOICE {nR-CGI (PLMN, 36-bit NCI), eUTRA-CGI (PLMN, 28-bit ECI)} | compare (PLMN octets, bit value, bit length) |
| X2 component parts | E2AP v03.00 §9.2.27 (pp.68–69): X2 Request Part = EN-DC X2 SETUP REQUEST (TS 36.423 clause 9.1.2.31); Response Part = EN-DC X2 SETUP RESPONSE (clause 9.1.2.32) | the node's own cells are in the request part; the response part holds the neighbour's cells and must never be read as the node's |
| Action cap | E2AP v03.00 maxofRICactionID = 16; SubMgr `cMaxofRICactionID = 16` | C + 1 ≤ 16, so C ≤ 15 |
| Not-admitted causes | E2AP v03.00 §9.2.1 (pp.62–63): "Action not supported: Requested Action not supported by RAN function"; "Requested Information Unavailable: Information requested by Near-RT RIC is not available at E2 Node" | OQ-2 |
| Indication SN | E2AP §9.2.14: "the Indication Sequence Number", 0..65535, no per-action scope | keep the per-subscription SN |

## 2. Agent (question 1)

### 2.1 Where to parse

Replace `decode_kpm_granularity` (`kpm-subscription-admission.cpp:42-83`) with `decode_kpm_action(const std::vector<uint8_t>&, KpmActionDef&, std::string&)`.

`KpmActionDef` holds:
- `format` (1..5);
- `style`, from the top-level `ric-Style-Type` of E2SM-KPM-ActionDefinition;
- `granulMs`;
- `std::optional<Cgi>`, read from `actionDefinition_Format1->cellGlobalID` (and `Format3->cellGlobalID` for logging only).

`Cgi` is `{bool nr; std::array<uint8_t,3> plmn; uint64_t cellIdentity; int bits;}`. Decode it in the same `aper_decode_clean` pass that exists today. The inbound PDU already carries each action's definition octets (`e2ap-inbound.hpp:13-43`), so nothing changes in E2AP decoding.

### 2.2 Admission rule

`admit_kpm_subscription` gains a parameter: the node's own cells, `const std::vector<Cgi>& own`. Build it from `e2-node-identity.cpp:53-78`:
- en-gNB: NR CGI with PLMN `cfg.plmnBcd` and NCI `(gnbId << 4) | kNrCellPart`;
- eNB: E-UTRA CGI with ECI `(nodeId << 8) | kEutraCellPart`.

The call sites are `e2-session.cpp:163` and the tests. The event-trigger checks (`:89-115`) stay first and unchanged, so p12 b still gets eventTriggerNotSupported for the whole subscription.

Per action, in this order:

| Condition | Result |
|---|---|
| not REPORT; no definition; undecodable | not admitted (as today) |
| format 2, 4 or 5 | not admitted: the node advertises only styles 1 and 3 (`kpm-ran-function-description.cpp:60-62`) (OQ-3) |
| format 1 with style ≠ 1, or format 3 with style ≠ 3 | not admitted (OQ-3) |
| G ≠ T | not admitted (as today) |
| format 1 without CGI | not admitted (§7.4.2.2 "shall") (OQ-1) |
| format 1 with a CGI not in `own` (other cell, other PLMN, or the wrong RAT for the node kind) | not admitted, the row 153 agent case (OQ-2) |
| otherwise | admitted, with its format recorded |

Every refusal uses ricRequest action-not-supported (OQ-2). When nothing is admitted, the answer is RIC SUBSCRIPTION FAILURE with the same cause, as today.

Extend the header comment (`kpm-subscription-admission.hpp:1-26`) with the §7.4.2.2 and §9.2.27 basis. Leave plan and row IDs out of it.

`KpmAdmission` gains `std::vector<std::pair<long,int>> admittedFormats`. `admitted` stays as the ID list for `build_subscription_response`.

### 2.3 Subscription and routing

- `subscription-table.hpp:22-23`: replace `actionIds` and `actionId` with `std::vector<AdmittedAction> actions` (where `AdmittedAction` is `{long id; int format;}`), sorted by ID. `e2-session.cpp:179-180` fills it from `admittedFormats`. The log line at `:186-190` prints the per-format IDs.
- Add a pure helper next to the table, e.g. `report-routing.hpp/.cpp`, so routing is unit-testable without SCTP:

  ```text
  route_report(actions, rep) -> [(actionId, &msg, isCell)]
    every format-1 action, ascending ID: (id, rep.cellMsg, true)
    then every format-3 action, ascending ID: (id, rep.ueMsgs[k], false) for each k
  ```

- `send_report` (`e2-session.cpp:210-235`) iterates that list and passes the entry's action ID to `build_indication` instead of `sub.actionId`.
  - SN stays per subscription (`sub.nextSn`, `:226`), incremented per indication sent.
  - The stop-on-first-failure semantics stay.
- Cell first, then UE keeps today's wire order, so `wire-c1-extract.py`'s per-node header sequence and the SN sequence are byte-identical at C = 1 (section 6, cp3).
- `SampleEncoder::encode` (`sample-forwarder.cpp:193-213`) is unchanged. It still builds both message kinds; routing decides what is sent. A subscription whose only admitted action is Format 3 therefore gets no cell message, which is the spec-correct answer.

### 2.4 Per-UE data and P9's rows under Format 1

- The UE lists are Format 2 under the Format 3 action, exactly as today. Format 1 never carried UE data.
- P9's DRB.PdcpSduVolumeX2UL and X2DL are gNB cell rows 36 and 37 (`schema/metric-map.v1.json`). They travel in the Format 1 cell message under the Format 1 action, with no change to the encoding or to kpimon's `cellMetrics` write.
- The agent ignores the measurement list of both formats and sends every row in map order. That deviation predates P15 and is OQ-4.

### 2.5 Unit cases, and where they must run

`kpm-report-period-test` is not run by any gate (ledger row 164, "not run by a gate"; the agent `Dockerfile:94-98` runs only codec-probe, rc-control-test and ue-context-per-seq-test). Put the new cases in a new binary, `kpm-action-routing-test`, added to `CMakeLists.txt:82-91` and to the Dockerfile test `RUN` at `:95-98`. Then M5's image build enforces them (OQ-16).

Build the definitions in the test with the agent's own asn1c types: E2SM_KPM_ActionDefinition with a Format 1 cellGlobalID. Reuse the subscription-request builder pattern of `kpm-report-period-test.cpp:160-195` and the `expect_response` pattern of `:252-296`.

Cases:
1. gNB 2 (NCI 0x21, PLMN 00F110): F1 with its own NR CGI at ID 1 plus F3 at ID 2. The response admits [1, 2] and has no not-admitted list.
2. **Row 153 agent case:** F1 naming gNB 3's NR CGI (NCI 0x31) at ID 1, plus F3. Admitted [2]; not-admitted [(1, action-not-supported)].
3. F1 with its own NCI but PLMN 00F120: not admitted.
4. F1 without CGI: not admitted (OQ-1).
5. F1 with an E-UTRA CGI on a gNB: not admitted.
6. eNB 1 (ECI 0x101): F1 with its own E-UTRA CGI is admitted; F1 with an NR CGI is not.
7. F1 with style 3, and F3 with style 1: not admitted. F2, F4 and F5: not admitted.
8. Only a foreign F1 and nothing else: RIC SUBSCRIPTION FAILURE, action-not-supported.
9. Routing:
   - {1:F1, 2:F3} with a report of one cell message and two UE messages gives [(1, cell), (2, ue0), (2, ue1)].
   - {2:F3} gives the UE messages only; {1:F1} gives the cell message only.
   - {1:F1, 2:F1, 3:F3} gives the cell message twice, under 1 and under 2.
   - SN advances by one per indication.

`kpm-report-period-test.cpp:203` takes the new parameter (it is the only test caller today). The T/T golden must stay byte-identical: encoding is untouched. A golden diff at P15 is a red flag, not a regeneration.

## 3. kpimon (question 2)

### 3.1 How kpimon gets the cells

Use cgo into the Testbed's X2AP asn1c codec (`ns3_e2_agent/x2ap_codec/`, asn1c mouse07410 30d7a84e, `x2ap-v19.1.0.asn`). Read only the X2 component request part from the e2mgr nodeb record.

This is the registered P05 route, and E2AP §9.2.27 places the node's own served cells there. It also meets the P05 exit review's point (`kongming-261104-0600…:90-115`): one decoder for one set of bytes.

The rejected routes are in "Alternatives" below:
- KPM-native `ric-KPM-Node-List` cell discovery;
- a pure-Go APER decoder;
- tshark-style hex matching like the TS xApp's N1 parser.

Verified e2mgr shape (`evidence/e2i/20261106T171917Z/e2mgr-node-{1,2}.json`):
- **eNB (`nodeType` ENB):** `enb: {enbType, nodeConfigs: [...]}` with one X2 component per en-gNB peer. Every component has the same request part (the `.x2-parts.hex` sidecar shows the same request hex per peer), and no `ranFunctions`.
- **en-gNB:** `gnb: {ranFunctions, gnbType, nodeConfigs: [one X2 component, peer = eNB]}`.
- **Part encoding:** each part is base64 of upper-case hex text of the APER X2AP-PDU. For example, the en-gNB part decodes to `00 24 …`, an initiatingMessage for id-endcX2Setup.
- **Node ID:** `globalNbId.nbId` is a bit string: 20 bits for the macro eNB, 32 for the gNB.

### 3.2 Codec change (Testbed, first commit)

- **New export** in `x2ap-codec.h` (with the code in `x2ap-codec-endc-setup.c`/`-cells.c`):

  ```c
  typedef struct { uint8_t plmn[3]; uint64_t cell_identity; int bits; /* 36 NR, 28 E-UTRA */ } x2c_cgi;
  X2C_EXPORT int x2c_decode_endc_setup_cells(const uint8_t *buf, size_t len, x2c_setup_summary *s,
                                             x2c_cgi *cells, size_t cap, size_t *n, char *err, size_t err_len);
  ```

  - It fills the existing summary: response flag, node kind, PLMN, node ID and bits.
  - It writes every served cell's own CGI, using the cell's own `pLMN-Identity`, not the node's.
  - It reuses `x2c_read_nr_cells` and `x2c_read_eutra_cells` (`x2ap-codec-cells.c:178-198`).
  - It fails on `n > cap`, as the existing decoder does on trailing octets.
  - `x2c_decode_endc_setup` keeps its first-cell summary.
- **codec-probe:** add a round trip at 1 and 2 cells for both node kinds, so M5's image build checks it.
- **Standalone build:** move the library target (`CMakeLists.txt:32-44`) into `x2ap_codec/CMakeLists.txt`, with the agent calling `add_subdirectory`. Move the asn1c command line (`Dockerfile:79-83`) into `x2ap_codec/generate.sh`. Then kpimon builds the same library with the same flags and hidden visibility, and the two builds cannot drift.

### 3.3 kpimon code (Testbed, third commit)

- **`types.go`**, via a new patch, not an edit of `types.go.patch`: `Enb` gains `NodeConfigs []NodeConfigs \`json:"nodeConfigs"\``. The `NodeConfigs` type already exists for the gNB.
- **New `servedCells(resp *E2mgrResponse) ([]cgi, error)`** in the control.go patch:
  - Pick `Gnb.NodeConfigs` or `Enb.NodeConfigs` with `isEnbNode` (`control.go:113`).
  - Keep `E2nodeComponentInterfaceType == "x2"` only, and decode base64, then hex, then `C.x2c_decode_endc_setup_cells`.
  - Require all of these:
    - `!s.response`;
    - `s.en_gnb == !isEnbNode`;
    - the summary's PLMN and node ID with its bit length equal `resp.GlobalNbId`.
  - Merge the components. Identical cell sets are deduplicated; differing sets are an error.
  - Require 1 ≤ C ≤ 15.
  - Never read `E2nodeComponentResponsePart`.
- **`initializeNode`** (`control.go:1182-1305`):
  - The eNB branch (`:1209-1217`) keeps its measurement lists from `enb-kpm-measurements.json` and sets `Glob_Ran_cell[meid]` from `servedCells`.
  - The gNB path replaces the f1apServer GET (`:1282-1301`) with `servedCells`.
  - On any error, log it and `return false`. `monitorE2Nodes` (`:1331-1375`) retries every 5 s and never subscribes, which fails closed. Row 153's "each node ≥ 1 request" then reports it at the gate.
- **Format 1 encoder.** Replace `encode_action_format1(plmn, cellid, meid)` (`control.go:297-343`, the 8-octet splice of PLMN and NR cell bytes) with `encodeActionFormat1ByID(ids []kpmMeasurement or []int64, c cgi)`.
  - It calls a new C function in `wrapper.c`:

    ```c
    long e2sm_encode_ric_action_definition_format1_by_id_cgi(unsigned char *buf, size_t *size, const long *ids,
        size_t n, long style /* 1 */, unsigned long granul_ms, int nr, const unsigned char plmn[3],
        unsigned long long cell_identity);
    ```

    It sets `cellGlobalID` as `CGI_PR_nR_CGI` (36-bit NRCellIdentity) or `CGI_PR_eUTRA_CGI` (28-bit EUTRACellIdentity).
  - Measurement IDs:
    - gNB: the style-1 IDs of the RAN function definition, read the way determine 3 reads the style-3 IDs. Extend `buildRanCellUeKpi` or add a sibling that returns IDs.
    - eNB: `enbKpmMeasurements.Cell` (each row has `MeasID`, checked at `control.go:100-103`).
  - Encode by ID, not by name. By name, the 37 gNB names alone are 731 octets, about 935 with the item overhead, too close to SubMgr's 1024-octet `OctetString_t`. By ID it is about 250 octets.
- **`encode_actionsToBeSetup`** (`control.go:408-543`) keeps its structure: IDs 1..C over `tempCells`, then the Format 3 action at C+1 (`:527-538`). Each cell's CGI is passed instead of `plmnByCell` strings. `Glob_cell_Plmn` stays only if something else reads it; otherwise drop it with the splice.
- **`handleIndication`** (`control.go:811-1057`) still dispatches on the indication message type, which E2SM-KPM makes self-describing. It writes `cellMetrics` and `UeMetrics` as before. The check that the action matches the format belongs in the harness (row 154), not kpimon.
- The f1apServer sidecar becomes unused: remove the call; keeping or dropping the process is OQ-6.

### 3.4 Patch layering and regeneration

New files in `install_patch_files/xApps/kpimon-go/` (names are suggestions), in `patches.manifest` order:

| After | New entry |
|---|---|
| `wrapper.c.ue-id-tag.patch` | `e2sm/wrapper.c.format1-cgi.patch` |
| `wrapper.h.ue-id-tag.patch` | `e2sm/wrapper.h.format1-cgi.patch` |
| `control/control.go.ue-id-tag.patch` | `control/control.go.format1-per-cell.patch` |
| `control/types.go.patch` | `control/types.go.enb-node-configs.patch` |
| end | `Dockerfile.x2ap-codec.patch`, `x2ap-codec.sha256` (lockfile, see below) |

- Each new patch needs both a manifest line and a hardcoded `git apply` line in `additional_scripts/install_xapp_kpi_monitor.sh` (`:140-198`; control.go lines at `:185-197`). The installer applies by its own list, and the label digest is computed from the manifest (`:200-207`). Missing either one breaks only one of the two, silently.
- Generate each P15 patch against the tree with every earlier patch applied. D-06b-1's kpimon formatter change and the node-tag patch (`control.go.e2-node-tag.patch`, listed after `control.go.ue-id-tag.patch` per phase-10) are generated afterwards on top of P15's control.go. If P15 is amended later, regenerate them.
- **The label must cover the codec sources.** The codec lives outside the patch dir. `patchset_digest_at_pin` (`bringup.sh:377-390`) and `patchset_safe_relpath` (`:374`) reject `..`, so the manifest cannot list it.
  - Recommended: commit `x2ap-codec.sha256`, a `sha256sum` list of every file under `ns3_e2_agent/x2ap_codec/` plus `generate.sh`. List it in the manifest.
  - The installer runs `sha256sum -c` on it before copying the codec into the kpimon tree, and exits non-zero on a mismatch.
  - A codec change then forces a lockfile change, a label change and a kpimon rebuild. The digest rule in both `install_xapp_kpi_monitor.sh:200-207` and `bringup.sh:377-390` stays as it is (OQ-17).

### 3.5 Image build

kpimon's Dockerfile is single-stage on `bldr-ubuntu20-c-go:1.0.0` (glibc 2.31). The agent's `libx2ap_codec.so` comes from ubuntu22 (glibc 2.35), so it must not be copied across.

- Add a builder stage `FROM bldr-ubuntu20-c-go:1.0.0 AS x2ap` that:
  - installs autoconf, automake, libtool, bison and flex;
  - builds asn1c at `ASN1C_SHA=30d7a84e…` with `--disable-test-asan`, carrying over the agent's comment about the gcc 11 ASan loop;
  - runs `generate.sh`, then `cmake -S x2ap_codec -DX2AP_GEN_DIR=…`.
- The final stage copies only `libx2ap_codec.so` and `x2ap-codec.h`, then runs `ldconfig`. Go's cgo links with `-lx2ap_codec`.
- Hidden visibility (`x2ap-codec.h:6`) keeps the codec's asn1c runtime from clashing with `libe2smwrapper`'s.
- Expect the cold kpimon build to grow by several minutes for asn1c, the X2AP generation and its compile. M3's step timeout is 3600 s (`p10-gate-chain.sh:84`). Record the measured cold time and the VM disk delta for P11's budget.

### 3.6 Format 1 indications into InfluxDB, and who reads them

- At C = 1 per node, each report is still one Format 1 cell message and N Format 2 UE messages. Only the RIC action ID differs: 1 and 2 instead of 1 and 1. kpimon ignores the action ID.
  - `cellMetrics` is written by `writeCellMetrics_db` (`control.go:1162-1180`, no tags) behind the `no_of_cell_metrics == len(ranCellKpi[meid])` guard. The guard is unchanged, because `ranCellKpi` still comes from the RAN function definition or the eNB JSON.
  - `UeMetrics` is written by `writeUeMetrics_db` (`:1138-1160`, ueId tag).
  - Both keep their exact shape.
- Downstream readers, all content-unchanged:
  - `influx-vs-trace.py` (m6, m7, p12, s10 "Influx = IPC");
  - the TS xApp, which reads `UeMetrics`;
  - the r3p predictor, which reads X2DL from the cell data;
  - s10's `NBR` and `kpm-records`, which read `msg_format` and records and ignore the action;
  - `kpm-ue-list-moves.py`, which attributes by association;
  - `wire-c1-extract.py`, which emits kpm-headers and collet-start-time.

## 4. Harness (question 3)

### 4.1 tshark fields (verified on the host; to be checked on the VM before code)

Host 4.7.4, `m6.pcap`, RIC INDICATION frames:

| Field | In RIC INDICATION | Notes |
|---|---|---|
| `e2ap.RICactionID` | 1 | the action ID of an indication (type-named IE field) |
| `e2ap.ricActionID` | empty | the component of RICaction-ToBeSetup-Item and RICaction-Admitted-Item; frame 17, the subscription response, gives the admitted ID 1 |
| `e2ap.ricRequestorID`, `e2ap.ricInstanceID` | 123, 6 | |
| `e2ap.RANfunctionID` | 2 | `e2ap.ranFunctionID` is empty in indications |
| `e2ap.indicationMessage_formats` | 0 = Format 1, 1 = Format 2 | also present: `e2ap.actionDefinition_formats`, `e2ap.ric_Style_Type`, `e2ap.cellGlobalID`, `e2ap.nRCellIdentity` |

A frame can bundle several DATA chunks of one fragmented message. Frame 22 has two TSNs and one PDU, and `pcap-to-lines.py:60-63` already handles that case. Every new per-PDU column must have one value per header, or the row is skipped and counted.

The VM's version is unclear. The n4 evidence says 4.2.2; `kpm-ue-list-moves.py`'s comment says 4.4.19. On the VM, before writing code:

```text
tshark --version | head -1
tshark -G fields | awk -F'\t' '$1=="F" && $3 ~ /^e2ap\.(RICactionID|ricActionID|ricRequestorID|ricInstanceID|RANfunctionID|indicationMessage_formats)$/ {print $3, $4}'
tshark -r <a green M6 pcap> -Y 'e2ap.procedureCode == 5 && e2ap.initiatingMessage_element' -T fields \
  -E occurrence=a -E aggregator=, -e frame.number -e e2ap.RICactionID -e e2ap.ricActionID \
  -e e2ap.ricRequestorID -e e2ap.ricInstanceID -e e2ap.RANfunctionID | head
```

Expected result: `RICactionID` = 1 and `ricActionID` empty, as on the host. Record the output in the row-154 commit's evidence. The design fails closed regardless: an unknown `-e` field makes tshark exit non-zero, and `pcap-to-lines.py:39-41` exits "tshark failed".

### 4.2 The decoded-subscription sidecar (rows 153 and 154 share it)

**New file: `tools/e2-evidence/e2-sub-setup-decode.py`.**

- **Host half: `collect <pcap>`.** Runs `tshark -T json -x -j "frame e2ap"` over `e2ap.procedureCode == 1 && e2ap.initiatingMessage_element` and over `e2ap.procedureCode == 8`. It reads the raw `e2ap_raw` layer bytes the way `e2i-wire-checks.py:162-176` does, and writes `{frame: [hex, …]}`.
- **Image half: `decode`.** Reads that JSON on stdin inside `localhost/asn1-indep:<tag>` and prints per frame and PDU:
  - **E2SetupRequest:** `globalId`, plus, for every x2 component, the request part's `node` (init-en-gNB or init-eNB) and the cells read from it:
    - `id-ServedNRcellsENDCX2ManagementList[*].servedNRCellInfo.nrCellID{pLMN-Identity, nRcellIdentifier}`, or
    - `id-ServedEUTRAcellsENDCX2ManagementList[*].servedEUTRACellInfo.cellId{pLMN-Identity, eUTRANcellIdentifier}`.

    These come from `e2indep.x2ap.decode_endc_x2_setup_request` (`tools/asn1-indep/e2indep/x2ap.py:106`).
  - **RICsubscriptionRequest:** requestor, instance, RAN function ID, and for every item: ID, type, whether a definition is present, and the decoded definition. The definition is `e2indep_gen.E2SM_KPM_v0300.E2SM_KPM_IEs.E2SM_KPM_ActionDefinition`, giving format, `ric-Style-Type`, granulPeriod and CGI (kind, PLMN hex, value, bits), or an `error`.
  - **RICsubscriptionResponse:** request ID, function ID, admitted IDs, and not-admitted (ID, cause).
  - **RICsubscriptionFailure:** request ID and cause.
- **Keep `e2indep/` untouched.** The tag is a hash over `e2indep/*.py` (`tools/asn1-indep/build.sh:5-8`), so any edit means a new tarball and a new tag for e2i. The script is mounted read-only, as `e2i-wire-checks.py` is (`gate-e2i-interop.sh:71-72`, `:262-264`). The duplication with e2i's `decode_setup` is about 20 lines. That is accepted rather than refactoring a green e2i judge.
- **Plumbing, in a new `scripts/gates/asn1-indep-lib.sh`:**
  - `asn1_indep_ready` derives the tag with a new `tools/asn1-indep/image-tag.sh`, the hash factored out of `build.sh:14-18`. `build.sh` itself is not a hash input, so the tag stays `09aeabb8b0f99b0c`.
  - It runs `dk image inspect`. Only when the image is absent, it runs `sha256sum -c` in `~/asn1-indep` and loads `asn1-indep-$tag.tar`.
  - It fails closed with a reason.
  - It runs inside the check functions, so no check name is added.
  - e2i keeps its own `--image-tag` loader check.
- **Chain driver** (`evidence/p10-chain/p10-gate-chain.sh:100-116`): run `preflight_asn1_indep` when any step in the range has an id in {m6, m7, p12, e2i, r0, r1, r2, r3p, s10}, not only on `--image-tag`. The tag comes from `image-tag.sh` in the frozen checkout. If an `--image-tag` argument is present, it must be equal, else exit 2. This is infrastructure (memory: the pre-flight needs no ledger row) (OQ-11).

### 4.3 Row 153: functions, sites, fixtures

- **Helper.** `kpm_sub_actions_check <facts> <node-ips>` (`agents-ns3-run.sh:220-225`, doc `:15`) keeps its arguments, so all nine call sites only rename their check.
  - It takes the pcap from `facts["pcap"]`, an absolute VM path verified in `e2i-facts.json`.
  - It runs `asn1_indep_ready` and `collect | dk run … decode` into `${facts%-facts.json}-sub-decoded.json`, reusing the file if it exists, since the evidence dir is per run.
  - Then it calls `e2-facts-query.py <facts> sub-actions --node-ips <f> --decoded <sidecar>`.
- **Rewrite `q_sub_actions`** (`e2-facts-query.py:393-440`, doc `:18-25`).
  - Ownership and window come from `build_assocs`, as today. The conjuncts for "no association", "no E2 Setup" and "another node" stay.
  - The new conjuncts follow the row:
    - **C per node:** decode every E2SetupRequest frame of that node's associations in the capture. C is the distinct served CGIs of the node's x2 request parts.
      - If no setup is in the capture, or no x2 part decodes, fail with "no E2 Setup X2 request part for node N in the capture"; never C = 0.
      - If the parts disagree, fail with "ambiguous served cells" (OQ-8).
    - **Request shape:** each request has exactly C+1 items, with IDs exactly {1..C+1}.
      - IDs 1..C: type report (index 0), definition Format 1, CGI present, CGI of the node's RAT (NR on an en-gNB, E-UTRA on the eNB), CGI in the served set, each served CGI exactly once.
      - ID C+1: type report (index 0), Format 3.
    - **Admission:** the RIC SUBSCRIPTION RESPONSE on the same association with the same (requestor, instance, RAN function ID), the first after the request, admits exactly {1..C+1} with no not-admitted item. A missing response or a FAILURE is a problem. The sub-response 4-tuple attribution mirrors the indication one in `build_assocs`.
    - Each node has at least one request, as today.
  - Format 3 is now judged by the pycrate decode rather than tshark's `definition_format` label (`e2ap-pcap-facts.py:187-212`). That is what row 100's text already says, and it is stricter: the definition must decode.
- **Renames** to `…_kpimon_subscription_format1_per_cell_and_format3`:
  - `gate-m6-kpm.sh:100`;
  - `gate-m7-multignb.sh:224` (the row says `:204`, OQ-9);
  - `gate-r0-rc-scripted.sh:206`;
  - `gate-r1-rc-multi-control.sh:174`;
  - `gate-p12-kpm-period.sh:138` and `:212`;
  - `gate-e2i-interop.sh:278`;
  - `ts-rung-lib.sh:85`.
- **Self-test** (`e2-facts-query.py:443-499`). Keep the 12 existing cases, adapted, and add these. The ones the row requires are marked with a star.
  - Good forms: C = 1 for an en-gNB with an NR CGI and for the eNB with an E-UTRA CGI; and a synthetic C = 2 node, with F1 at IDs 1 and 2 and F3 at 3.
  - Must fail:
    - the old single F3 at ID 1 (*);
    - F1 without CGI (*);
    - a foreign CGI (*);
    - two F3 (*);
    - a not-admitted action (*);
    - no setup in the capture, with the reason checked;
    - an NR CGI on the eNB;
    - one cell named twice;
    - IDs {0..C} or with a gap;
    - a missing response;
    - an undecodable definition.
  - `lint.sh:87` already runs the self-test.

### 4.4 Row 154: `<site>_kpm_indication_format_equals_its_action_format`

- **`pcap-to-lines.py`.** Add an `--actions OUT.jsonl` mode with the same filter and dedup. Its extra fields are `e2ap.RICactionID`, `e2ap.ricRequestorID`, `e2ap.ricInstanceID`, `e2ap.RANfunctionID`, `ip.src`, `sctp.srcport` and `frame.time_epoch`. It writes one record per kept line with the same `id` (`f<frame>[.i]`).
  - The `<id> <hdr> <msg>` line format is unchanged. `kpimon-decode-harness.c:108-111` reads three tokens, and p12's lines stay identical.
  - A column whose count differs from the header count makes the row count as skipped.
- **New `agents-ns3-run.sh` helper: `kpm_ind_actions_check <facts> <node-ips>`.** It:
  - reuses the gate's `$SODIR`, or runs `kpimon_extract_so` into `$e/kpimon-so` (needed at r0, r1, ts-rung-lib and e2i, which do not extract today: see the `kpimon_extract_so` grep);
  - runs `pcap-to-lines.py` (lines and `--actions`);
  - runs `kpimon-decode-harness --records`;
  - calls `e2-facts-query.py <facts> ind-actions --node-ips … --decoded <sidecar> --records R --ind-actions A --map metric-map.v1.json`.
- **The `q_ind_actions` predicate**, as the row states it:
  - Every indication after the window start lies on an expected node's association (owner by 4-tuple and time, `build_assocs`).
  - Its subscription is the last RIC SUBSCRIPTION RESPONSE on that association with the same (requestor, instance, RAN function ID) before it (OQ-19). An unknown subscription, or an action ID outside the admitted set, is a problem.
  - Under a Format 1 action, the record must have `msg_format == 1`. The `ns3.nodeId` of every measData item must equal the association's node, with the position taken from the metric map's cell list for the node kind (OQ-18).
  - Under the Format 3 action, `msg_format == 2`.
  - Every admitted action of every in-window subscription gets at least one indication.
  - Fail closed when the lines, the records and the `--actions` rows differ in count, when a record is not RC_OK, or when `rows_skipped` > 0.
- **Sites:**
  - m6, after `:100`;
  - m7, after `:224`;
  - p12 a, after `:138` (not c: `p12-c.pcap` holds 0 indications, verified);
  - e2i, after `:278`;
  - r0 `:206`, r1 `:174` and `ts-rung-lib.sh:85`, each per label.
- **Live feasibility, verified on the committed pcaps:**
  - e2i: every node sends at least 99 Format 1 and 99 Format 2 indications.
  - m7: both the pre-delete and the post-re-setup associations carry 100–882 indications of each format.
  - p12 a: 10 and 10.
  - So "≥ 1 per action" holds at every site.
- **Self-test.** The row's must-fail cases are marked with a star.
  - Good: two nodes, F1 under 1 and F2 under 2.
  - Must fail:
    - F1 under the F3 action, today's wire (*);
    - F2 under F1 (*);
    - an unknown ID (*);
    - a silent action (*);
    - another node's `ns3.nodeId` under F1;
    - an unknown request ID;
    - a record that does not decode;
    - a skipped row.

### 4.5 Row 155: p12 records bound to their action

- `records_a` (`gate-p12-kpm-period.sh:140-148`) also writes `p12-a-ind-actions.jsonl` with `pcap-to-lines.py --actions`. It passes `--ind-actions` and `--decoded p12-a-sub-decoded.json` to `p12-records-check.py`, after `kpm_sub_actions_check` has made the sidecar at `:138`.
- `p12-records-check.py` joins each record to its action by `id`. Every old conjunct stays, and these are added:
  - Check 2 (`check()` at `:190-207`, doc `:24-34`): each Format 1 record's `actionId` is the subscription's Format 1 action whose CGI is the served cell of the node named by the record's `ns3.nodeId`.
  - Check 4: each Format 2 record's `actionId` is that subscription's Format 3 action.
  - A record without an action is a problem.
  - The subscription table comes from the sidecar, with the same join as row 154. IDs are never hardcoded as 1 and 2.
- **Self-test additions:**
  - the good fixture with actions 1 and 2 passes;
  - F1 under the F3 action fails check 2;
  - F2 under the F1 action fails check 4;
  - F1 under another node's F1 action fails;
  - a missing `actionId` fails;
  - and every existing case still behaves as before.
- **"p12 references re-baselined"** reduces to the judge and its fixtures. No p12 reference artefact is committed: `reference/` holds the identity map, `r3p-d*`, `m9-r3p-raw` and `n4-sn-wrap` (OQ-13).

## 5. Commit plan and gates (question 4)

Rows 153–155 are already in `check-diff-ledger.md:159-161`, committed. Rule on OQ-1 to OQ-3 and OQ-8 before T2 and H1. Any ruling that changes a predicate goes into a docs commit first.

| # | Repo | Commit (message style) | Gate at the commit |
|---|---|---|---|
| T1 | Testbed | `feat(x2ap-codec): decode every served cell of an EN-DC X2 setup and build the codec on its own` | host podman build of the agent image (codec-probe round trip) |
| T2 | Testbed | `fix(ns3-e2-agent): answer each KPM action in the format it asked for` | host agent image build with `kpm-action-routing-test` in its test RUN; `kpm-report-period-test` run by hand, golden byte-identical |
| T3 | Testbed | `fix(kpimon): subscribe one Format 1 action per served cell next to the Format 3 action` | host build of the patched kpimon image (cgo link, `go vet`); patch stack applies cleanly in installer order |
| H1 | harness | `feat(gates): judge the per-cell Format 1 and Format 3 KPM subscription on the decoded wire` (row 153, sidecar, asn1-indep lib, image-tag.sh, renames) | `lint.sh` (self-tests); the decode run against the committed m6/m7/e2i pcaps in the image on the host must fail on today's wire for the right reason ("1 item, want C+1 = 2") |
| H2 | harness | `feat(gates): check that every KPM indication carries its action's format` (row 154) | lint; on today's pcaps it must fail with "Format 1 under the Format 3 action" |
| H3 | harness | `fix(gates): bind the p12 records check to each indication's action` (row 155) | lint; p12 a's committed pcap fails check 2 today |
| H4 | harness | `docs(plans): pin the Testbed fork for the per-action KPM formats and add p12 to the chain` (pins.conf TESTBED_SHA; driver steps and pre-flight; ledger location fixes per OQ-9) | driver `--check-dir` self-check; `P10_PREFLIGHT_ONLY=1` dry run |

T1–T3 are one fix (P15) spread over repo-local commits. They are not squashed with D-06b-1 or the node tag, and the chain judges them as one unit. No intermediate state is green: T2 alone serves old kpimon UE-only, and T3 alone gets F2 under F1. P11's bisection therefore treats the P15 endpoint as one entry (OQ-14).

**VM sequence:**
1. Revert point 3 to `f7-rerun-green`.
2. Confirm at least 34 GiB free on /home.
3. Make the frozen checkout at H4.
4. The pre-flight copies and checks the asn1-indep tarball.
5. Run the chain:
   - M2, M3 (kpimon reinstall: the label changes and it rebuilds; record the cold time), M4 (ns-3 at the current pins, needed after the revert), M5 (agent rebuild with the new unit test), M6, M7, I0, I2;
   - p12 (new step);
   - r3p `--mode single` (R3′ single);
   - e2i (recommended, OQ-12).

Use `P10_SKIP_STEPS` for r2, s10 and n4. Put the 34 GiB check again before p12. An M7 red that matches the route record gets the single re-run allowed by ruling ii.

## 6. Risks, downstream effects, open questions (question 5)

**Downstream, predicted:**
- **TS xApp:** reads `UeMetrics`; no change. Its heuristic N1 cell map (`ts_xapp.cpp.nr_cell_map.patch`) does not touch kpimon. The P05 aim of a shared decoder is not met yet (OQ-7).
- **r3p predictor:** reads X2DL from cell data with identical content; R3′ single must still give at least 1 predictor-driven handover, as P9's did.
- **s10:** 11 subscriptions of 2 actions each. Rows 153 and 154 run inside `rung_live`, but s10 is not in P15's gate list, so its first run of them is at P11's rehearsal. Record this as a risk rather than adding s10, which takes about 1,900 s.
- **P11 cp3 diff:** P15's predicted effect on every r3p reference component is **null**.
  - kpm-headers and collet-start-time list the header octets per node in order.
  - Every message of a report carries the same header (`sample-forwarder.cpp:193-213`).
  - `rung_live`'s `all_subscribed` (`ts-rung-lib.sh:12-20`) puts the subscription before the paced start, so period alignment cannot shift.
  - kpm-headers and collet-start-time may change at cp3 because of other commits. A change at P15's bisection step is a finding (OQ-14).
- **SubMgr limits:** C ≤ 15 is enforced in kpimon. Definitions are about 250 octets.
- **Disk:** the kpimon builder stage adds several GB of layers on the VM, and host podman storage is on /mnt/data (20 GiB free per plan.md:145). Check before the host builds.

**Open questions:**
1. **OQ-1. F1 without CGI at the agent.** Recommended: refuse with action-not-supported on both node kinds. The en-gNB list contains NRCellCU types, so §7.4.2.2 says "shall". The eNB's `ns3.*` cell rows all measure its one cell, so the same rule applies. This matches row 153's harness fixture. Alternative: admit and answer for the node's only cell.
2. **OQ-2. Cause for a foreign CGI.** Recommended: action-not-supported, the agent's only per-action cause today. "Requested Information Unavailable" (§9.2.1) fits a foreign cell better semantically, but it is extension value 52, and SubMgr's decoding of it is unproven. Adopt it only after a live decode proves it.
3. **OQ-3. Formats 2, 4 and 5, and style/format mismatches.** Recommended: not admitted. An admitted action must get its format, and the node advertises only styles 1 and 3. This is agent behaviour, not a harness predicate, so it needs no ledger row, but record it in the phase.
4. **OQ-4. The measurement list is not honoured** (both formats send every row). Recommended: record-only now, as a separate later item. Not P15.
5. **OQ-5. The CGI on Format 3 (§7.4.4.2)** once a 3GPP cell-confined UE metric joins the map. Recommended: record-only. Add a lint guard in the metric map later.
6. **OQ-6. f1apServer.** Recommended: remove the call in P15. Leave the upstream process, now idle, and record it.
7. **OQ-7. TS xApp N1 parser on x2c.** Recommended: not in P15. Do it in the TS serving-cell commit if that commit touches the cell map; otherwise make it a follow-up with its own row.
8. **OQ-8. Node setups or components that disagree on cells.** Recommended: fail closed with a reason. The row presupposes one request part, and today's parts are identical (`.x2-parts.hex`). Brainstorm should confirm this is not a narrowing.
9. **OQ-9. Ledger location drift.** Row 153 cites m7 `:204`; the actual line is `:224`. The doc range `:18-24` is now `:18-25`. Recommended: correct the location column in H4. It is not a predicate change.
10. **OQ-10. kpimon-decode-harness at r0, r1, ts-rung-lib and e2i.** Recommended: extract inside the row-154 check, so no new check name is added. The pycrate decode is the alternative, but it is too slow for s10's indication volume.
11. **OQ-11. asn1-indep at nine sites.** Recommended: the tag computed from the harness sources, plus the driver pre-flight. Confirm that no row is needed (infrastructure only).
12. **OQ-12. P15 gate list.** Recommended: add e2i and the p12 driver step. r0, r1, r2 and s10 run first at P11's rehearsals.
13. **OQ-13. No p12 reference artefact exists.** Recommended: say so in H3 and in row 155's status. The re-baseline is the judge and its fixtures.
14. **OQ-14. cp3 attribution.** Recommended: write P15's null prediction into P11's attribution table before the bisection, and treat T1–T3 as one P15 entry.
15. **OQ-15. VM tshark version.** Recommended: run section 4.1 on the VM before H2. If the field is not `e2ap.RICactionID` there, use the VM's name. The row allows it ("checked with `tshark -G fields` before code").
16. **OQ-16. Where the agent unit cases run.** Recommended: the new binary in the Dockerfile test RUN, enforced at M5.
17. **OQ-17. The kpimon label must cover the codec.** Recommended: the lockfile in the patch dir. The alternative is to widen the digest rule in two places.
18. **OQ-18. Which items row 154's `ns3.nodeId` covers.** Recommended: every measData item of the message, the literal reading of "its ns3.nodeId". If the brainstorm reads it as item 0 only, nothing else changes.
19. **OQ-19. Row 154's subscription join key.** Recommended: (association, requestor, instance, RAN function ID), taking the latest response before the indication. The m7 data shows new instance IDs after the re-setup (7–11, then 12–16).

## What to avoid

- Keeping the old single-action path or "lowest ID carries everything" behind a flag. The goal and the user's rule forbid it.
- Reading `E2nodeComponentResponsePart`, or the en-gNB's peer cells, as the node's own cells (E2AP §9.2.27).
- Format 1 by name. It sits about 90 octets under SubMgr's 1024-octet buffer, and the by-name F3 has already been corrupted there (`kpimon-subscription-octets.txt` "kpimon-f3-byname-wire").
- Any edit under `tools/asn1-indep/e2indep/` or `asn/`. It forces a new tag, a new tarball and an e2i re-pin.
- Hardcoding action IDs 1 and 2, or cell `0x21`, in any judge. Take them from the decoded capture, as the row says.
- Using tshark's KPM v2 dissector, which version-mismatches on v3, for the CGI or C.
- Adding a separate `*_kpimon_so_extracted` or `*_asn1_indep_loaded` check at new sites. Keep the work inside the registered check.
- Regenerating the T/T golden at P15. Its octets must not move.
- Editing a script under a running chain (memory); use the frozen checkout.

## Alternatives and trade-offs

- **KPM-native cell discovery** (`ric-KPM-Node-List` in the RAN function definition, §8.2.2.1). Spec-clean, with no X2 decoder in kpimon. Rejected: e2mgr 6.0.6 stores no `ranFunctions` for an eNB (`enb-kpm-measurements.json` doc; the e2mgr eNB record), and P05 and row 153 define C from the X2 request part.
- **Pure-Go APER X2AP decoder in kpimon.** No cgo or asn1c stage, so the build is faster. Rejected: it is a second decoder of the same bytes, the exact divergence the P05 review warned about, and the route is not the registered one.
- **asn1-indep for row 154's formats as well.** One decoder for both rows, and fully independent. Rejected for volume: pycrate over s10's or r3p's thousands of Format 2 messages costs minutes to hours. The kpimon library (C) is already the decoder at m6, p12 and s10.

## Work checklist

1. Rule OQ-1 to OQ-3 and OQ-8 (brainstorm standing rule). Put any predicate-affecting ruling into a docs commit.
2. Run section 4.1 on the VM (it needs only a shell, no gate). Record the field names.
3. T1: the codec export, the standalone CMake and `generate.sh`, and the codec-probe round trips. Host agent image build.
4. T2: `decode_kpm_action`, the admission rule, `AdmittedAction`, `route_report`, `send_report`, and `kpm-action-routing-test` in the Dockerfile RUN. Host image build, plus a hand run of `kpm-report-period-test` (golden identical).
5. T3: the wrapper.c/h Format 1 CGI encoder, the control.go per-cell patch, types.go `Enb.NodeConfigs`, the Dockerfile builder stage, and the codec lockfile. Add manifest and installer lines. Host kpimon build.
6. H1: `e2-sub-setup-decode.py`, `asn1-indep-lib.sh`, `image-tag.sh` (tag unchanged; assert it), `q_sub_actions` and its self-tests, the helper and the nine renames.
7. H2: `pcap-to-lines.py --actions`, `q_ind_actions` and its self-tests, the helper and the seven sites.
8. H3: p12 `records_a` and `p12-records-check.py` with its self-tests.
9. H4: the pin, the driver (pre-flight trigger, p12 step, optional e2i), and the ledger location fixes.
10. Revert, check free disk, freeze, run the chain (section 5), and record the evidence and the kpimon cold-build time.

## Success metrics

- At every chain site, `…_kpimon_subscription_format1_per_cell_and_format3` passes with C = 1 per node:
  - gNB NR CGI `00F110` + NCI `0x<gnbId>1`;
  - eNB E-UTRA CGI ECI `0x101`;
  - all C+1 admitted.
- `…_kpm_indication_format_equals_its_action_format` passes: only Format 1 under ID 1, only Format 2 under ID 2, both at least once per subscription.
- p12 a: every old conjunct holds (`recordsPerIndication` 10, `indicationsPerTenSeqs` 1.0, 10 F1 + 10 F2), plus the actionId conjuncts.
- Influx equals the IPC trace at M6, M7 and p12. kpimon logs every wire indication with zero RC_WMORE. R3′ single is green with at least 1 predictor-driven handover.
- The agent image builds only with `kpm-action-routing-test` passing. The T/T golden is unchanged.
- The kpimon cold-build time and the disk delta are recorded. /home stays at or above 34 GiB at every guard.

## Assumptions

- The ns-3 nodes each serve exactly one cell (`kNrCellPart`, `kEutraCellPart` = 1). Confidence: high. Several cells per node would exercise C > 1, which the design and its fixtures already cover.
- The VM's tshark keeps the host's E2AP field names. Confidence: medium. The check in section 4.1 settles it.
- NIST's E2SM-KPM v3 asn1c in the agent and kpimon's patched KPM library both carry the Format 1 `cellGlobalID` with both CGI alternatives. Confidence: high, since both are generated from the v03.00 ASN.1. Confirm when T2 and T3 compile.
- `bldr-ubuntu20-c-go:1.0.0` can build asn1c 30d7a84e with apt-installed autotools. Confidence: medium. If it cannot, build the codec stage from a pinned ubuntu20 image with the same glibc.
- SubMgr forwards definitions of about 250 octets and 2 actions unchanged. Confidence: high: 16 and 1024 are the limits.
- P11's attribution accepts P15 as one entry across three Testbed commits. Confidence: medium (OQ-14).

## Unresolved questions

OQ-1 to OQ-19 above, in priority order:
- **before T2:** OQ-1, OQ-2, OQ-3, OQ-16;
- **before H1 and H2:** OQ-8, OQ-15, OQ-18, OQ-19;
- **before H4:** OQ-9, OQ-11, OQ-12, OQ-13;
- **record-only or follow-up:** OQ-4, OQ-5, OQ-6, OQ-7, OQ-10, OQ-14, OQ-17.
