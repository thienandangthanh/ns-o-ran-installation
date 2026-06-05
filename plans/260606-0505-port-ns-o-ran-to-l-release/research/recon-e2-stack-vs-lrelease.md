# Recon: ns-O-RAN E2 stack vs L-release testbed (technical reference)

Consolidated from 4 parallel Explore agents. Source-of-truth file paths for /ck:cook. Do not re-run recon.

## Versions
| | Source (Bronze, current) | Target (L-release) |
|---|---|---|
| E2AP | v01.00 (asn1c-0.9.29, gen-PER) | **v03.01** (APER) |
| E2SM-KPM | v02.00.03 | **v03.00** |
| E2SM-RC | combined `e2sm-kpm-rc.asn` (dummy OID) | v2.0 (out of scope) |
| e2sim | wineslab fork v1.0 (`2209995`) | OSC `e2-interface` `da6f82f2` |
| e2term | Docker `10.0.2.10:36422` | k8s `ric-plt-e2:3.0.1`, NodePort SCTP **32222** (targetPort 36422), ns `ricplt`, kubeadm+Flannel |
| KPM RAN func ID | 200 (RC=300) | bundled e2sim hardcodes **2**; verify kpimon-go |
| TimeStamp | 4 bytes | **8 bytes** |

## Target ASN.1 (gold reference)
`O-RAN-Testbed-Automation/RAN_Intelligent_Controllers/Near-Real-Time-RIC/e2-interface/e2sim/asn1c/asn/v03/`:
`e2ap-pdu-v03.01.asn`, `e2sm-kpm-v03.00.asn`, `e2ap-ied-v03.01.asn`, `e2ap-common/constant/container-v03.01.asn`.
Working reference E2 node: `…/e2-interface/e2sim/e2sm_examples/kpm_e2sm/` (KPM func ID=2 in `src/kpm/kpm_callbacks.cpp`).
Launcher: `…/Near-Real-Time-RIC/install_scripts/run_e2sim_and_connect_to_ric.sh`.
E2Term SCTP svc: `…/ric-dep/helm/e2term/templates/service-sctp.yaml`.
KPM v3 OID: `…53148 e2(1) version3(3) e2sm(2) e2sm-KPMMON-IEs(2)`.

## Source files to port (adapter boundary = `oran-interface/model/`)
- `oran-interface/model/oran-interface.cc`/`.h` — E2Termination: SCTP params, RAN func register, send. **API kept stable.**
- `oran-interface/model/kpm-function-description.cc` — RAN func desc (dummy `OID123` → real v3 OID; `ric_ReportStyle_Type`→`ric_Style_Type`; drop `ric_KPM_Node_List`).
- `oran-interface/model/kpm-indication.cc`/`.h` — header/message (8-byte TimeStamp, 24-field MeasurementLabel, QosFlowIdentifier, S-NSSAI).
- `oran-interface/model/asn1c-types.*` — include style `<>`→`""`, `SNSSAI.h`→`S-NSSAI.h`, `QFI`→`QosFlowIdentifier`.
- `oran-interface/CMakeLists.txt` — `find_external_library(e2sim)` paths.
- `oran-e2sim/e2sim/src/encoding/encode_e2apv1.*` — replace `generate_e2apv1_*` with v3 generators.
- `oran-e2sim/e2sim/src/messagerouting/e2ap_message_handler.cpp` — PDU dispatch, RIC subscription decode.
- `oran-e2sim/e2sim/src/SCTP/e2sim_sctp.cpp` — SCTP client (connect target → node-IP:32222).
- ns-3 metric mapping: `oran-interface/helper/mmwave-indication-message-helper.cc`, `lte-indication-message-helper.cc`; sources `ns3-mmwave-oran/src/{mmwave,lte}/model/*-enb-net-device.cc` (`BuildAndSendReportMessage`).
- Build: `ns3-mmwave-oran/e2term-ns3-build.sh`, `oran-e2sim/e2sim/build_e2sim.sh`.

## Breaking ASN.1 deltas (compile + wire)
`ProtocolIE-Container` template `87P11`→`85P21` (linker break); `ric_ReportStyle_Type`→`ric_Style_Type`;
ActionDefinition `Format1`→`Formats 1–5` (CHOICE expansion); `MeasurementLabel` 17→24 fields;
`ric_KPM_Node_List` removed from RANfunction-Description; `QFI`→`QosFlowIdentifier`; `SNSSAI`→`S-NSSAI`;
TimeStamp 4→8 bytes; APER vs PER wire format; include `<asn_*.h>`→`"asn_*.h"`. Generated C: 50k→83k lines.

## Networking
ns-3 co-located on `oran-kvm-2` (Ubuntu 20.04.6) → connect to node-IP:32222 (same path as bundled sim). No cross-VM routing. `oran-kvm` retained as Bronze regression reference only.

## Key rules
- Regenerate ASN.1 from v03 `.asn` with **pinned asn1c**; never hand-edit generated `.c/.h`.
- Golden-pcap diff at every milestone (Bronze pcap = semantic baseline; L-release sim pcap = wire reference).
- Forks: `origin`=our fork, `upstream`=original; work on `dev/l-release`; no upstream PRs.
