# P15 per-action KPM format: consensus rulings (2026-11-08 09:07 KST)

These rulings came from a unanimous brainstorm consensus under the user's standing rule of 2026-11-07 02:21. They are **not user rulings**. They are shown at the next user session, where the user can reopen any of them. None of them needs the user for P15. Two items are listed for Stop B.

Source: `brainstorm-261108-0905-GH-1-p15-oq-ultra-debate.md`. The design counsel is `kongming-261108-0750-GH-1-p15-per-action-kpm-format-design.md`. It is adopted as corrected by the rulings below.

## Agent (Testbed commit T2)
- **Admission.** Admit only (style 1, Format 1) with a CGI naming the node's own cell (an NR CGI on the en-gNB, an E-UTRA CGI on the eNB), and (style 3, Format 3) with G = T as today. A Format 3 action may carry no CGI; if it carries one, the CGI must be the node's own cell. Every other action is not admitted with ricRequest action-not-supported. That covers a missing or foreign CGI on Format 1, a foreign CGI on Format 3, Formats 2, 4 and 5, and a style that does not match its format. (OQ-1, OQ-2, OQ-3)
- **Routing.** Each admitted action keeps its format. A pure routing helper in `ns3_e2_agent_core` sends the cell message under each Format 1 action, then the UE messages under each Format 3 action. With one cell per node, the indication count, the headers and the sequence numbers are unchanged.
- **Tests.** A new `kpm-action-routing-test` binary covers own-CGI F1, F3, foreign-CGI F1, CGI-less F1, F3 with a foreign CGI, Formats 2/4/5 and style mismatch. It is added to CMake `add_executable` and `install` and to the Dockerfile test RUN, so M5 enforces it. In `kpm-report-period-test`, update `:203` and the `decode_kpm_granularity` callers; give the "mixed" case's action 6 gNB 2's own NR CGI. The T/T golden stays byte-identical. (OQ-16)
- The agent's own CGI comes from one helper shared with `build_x2_components`.

## kpimon (Testbed commits T1 codec, T3 kpimon)
- **Cells.** Cells come from each node's own X2 request part in e2mgr's stored node configs, decoded with the Testbed asn1c X2AP codec via cgo. The decoded part must carry the node's own identity. A node with **zero X2 components gets C = 0 (Format 3 only, as today, with a log line)**; this keeps M3's kpm_sim subscribed. An X2 part that is present but undecodable, has the wrong identity, disagrees, or gives C > 15 fails closed.
- **Encoder and actions.** Extend `e2sm_encode_ric_action_definition_format1_by_id` with the E-UTRA CGI branch. kpimon's `E2mgrResponse` gains the eNB's node configs. Remove the `localhost:8090` sidecar call and leave the idle process (recorded). (OQ-6)
- **Pinning and build.** The codec directory joins `KPIMON_TESTBED_PATHS`. The `x2ap-codec.sha256` lockfile goes in the manifest and the installer, checked with `sha256sum -c`. The guard self-test gains a codec-edit case (row 74 amendment). The D-06b-1 and node-tag patches are regenerated on top later. (OQ-17)

## Harness (H1, H2, H3)
- **H1.** Row 153 as amended (C per association, identity and agreement, pycrate via asn1-indep), together with the TESTBED_SHA bump and the driver changes:
  - the asn1-indep pre-flight triggers for {m6, m7, p12, e2i, r0, r1, r2, r3p, s10};
  - p12 is appended as step 15;
  - a factored `image-tag.sh` keeps the tag `09aeabb8b0f99b0c`. (OQ-8, OQ-11, pin rule)
- **H2.** Row 154:
  - `e2ap.RICactionID` and the request-ID fields;
  - `kpimon-decode-harness --records`, extracted inside the check;
  - every item's `ns3.nodeId`;
  - the 4-tuple join;
  - the VM tshark output committed as evidence. (OQ-10, OQ-15, OQ-18, OQ-19)
- **H3.** Row 155. The re-baseline is the judge and its inline fixtures; no p12 reference artefact exists. (OQ-13)

## Gates and records
- **Chain:** revert to `f7-rerun-green`, check /home ≥ 34 GiB, freeze the checkout, then M2, M3, M4, M5, M6, M7, I0, I2, e2i, r3p single, then p12, with a /home ≥ 34 GiB check before p12. (OQ-12)
- **Measure at T3:** the kpimon cold-build time and the disk delta.
- **Record only:**
  - the measurement list is not honoured (OQ-4, Stop B);
  - the CGI on Format 3 later (OQ-5);
  - the TS N1 parser move is not in P15 and not bundled (OQ-7, Stop B);
  - the f1apServer process is idle (OQ-6).
- **Hand-offs to P11:**
  - P15's null prediction for kpm-headers and collet-start-time at C = 1, which supersedes phase-10 `:136` (OQ-14);
  - the M10 runner stages the asn1-indep tarball before the first m6 (OQ-11).

## Ledger text applied in the docs commit before P15 code
- Row 153 amendment (stricter only) and location fixes.
- Row 154 location and detail.
- Row 155 location and status.
- Row 100 note.
- Row 74 amendment (stronger).

## Unresolved questions
- Stop B: OQ-4 (fix the measurement list in M10, or list it) and OQ-7 (when to move the TS N1 parser).
