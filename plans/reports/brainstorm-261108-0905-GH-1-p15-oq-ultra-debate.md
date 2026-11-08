# P15 per-action KPM format: ultra + debate result (2026-11-08 09:07 KST)

This was a read-only advisory run; no code changed. It rules the 19 open questions (OQ-1 to OQ-19) of the P15 design counsel `kongming-261108-0750-GH-1-p15-per-action-kpm-format-design.md` §6 under the user's standing rule of 2026-11-07 02:21: unanimous answers are applied, hard calls go to the user.

**Method (same as the P6, SN-wrap, row 149 and P9 rulings).**
- One evidence packet went to five independent candidates: four kongming runs on Opus 5.5 (k1–k4) and one read-only Codex run (c5).
- A blind kongming verifier on Opus 5.5 scored them, anonymized as A–E. It re-checked the load-bearing claims in source at harness 9b001f03 and Testbed 03180a5, in the spec text (E2SM-KPM v03.00 `F82PYZVK`, E2AP v03.00 `WEE5IEXF`), and in the local pcaps.
- All five then got a debate round on the verifier's ten proposed resolutions of the contested points.
- The controller settled OQ-15 directly on the VM before the verdict (TShark 4.4.19; `e2ap.RICactionID` holds the action ID in indications, `e2ap.ricActionID` is empty).

## Contract
- **Outcome.**
  - The agent answers each admitted KPM action in the format it asked for: Format 1 gets Indication Format 1 for its cell, and Format 3 gets Indication Format 2.
  - kpimon subscribes one Format 1 action per served cell (IDs 1..C), plus the Format 3 action (ID C+1).
  - The harness judges rows 153–155 as registered and amended.
- **Constraints.**
  - Fix to spec, with no compat mode.
  - One fix per commit.
  - The pin bump lands with the predicate that needs it (phase-10 `:145`).
  - Ledger text goes in before code.
  - No M10 scope expansion without the user.
- **Non-goals.**
  - Honouring the measurement list (OQ-4).
  - A CGI on Format 3 (OQ-5).
  - The TS xApp N1 parser on the shared codec (OQ-7).
  - r0, r1, r2 and s10 runs at P15 (they run at P11).
- **Acceptance.**
  - At every P15 chain site, `…_kpimon_subscription_format1_per_cell_and_format3` passes with C = 1 per node, all C+1 admitted.
  - `…_kpm_indication_format_equals_its_action_format` passes.
  - p12 a holds every old conjunct plus the action conjuncts.
  - The agent image builds only with `kpm-action-routing-test` passing, and the T/T golden is unchanged.
  - R3′ single gives at least 1 predictor-driven handover.
- **Trade-offs.**
  - C per association assumes each request is judged against its own association's setup. It fails first if a node subscribed on an association other than the one it set up on, which no capture shows.
  - The counsel's per-node reading assumes cells never change across setups. It fails first on a re-setup with other cells.
- **Better approaches:** the verifier-adopted resolutions below improve on the counsel in five places, each verified in source:
  - kpimon's C = 0 for nodes with no X2 component;
  - the pin bump in H1;
  - p12 last;
  - the codec pinned in `KPIMON_TESTBED_PATHS`;
  - the routing helper in `ns3_e2_agent_core`.

## Final answers

| Q | Answer | Vote | Confidence |
|---|---|---|---|
| OQ-1 | The agent refuses a Format 1 action without a CGI, on both node kinds, with action-not-supported. On the gNB the basis is KPM §7.4.2.2 "shall be included", because NRCellCU types are in the list. On the eNB it is a capability limit, since its cell rows are `ns3.*` and the agent ignores the measurement list. In `kpm-report-period-test`'s "mixed" case (`:671-681`), action 6 gets gNB 2's own NR CGI, so its expectations ({1,6}; `check-report-period.py:100`'s 4 not-admitted) stay. The CGI-less case moves into the gated routing test. | 5–0 | high |
| OQ-2 | action-not-supported is final. The counsel's "extension value 52" is a PDF line number: requested-information-unavailable is 18, and E2AP §9.2.1's "not available" class means a resource shortage, not a missing capability. | 5–0 | high |
| OQ-3 | Admit only (style 1, Format 1) and (style 3, Format 3), as advertised (`kpm-ran-function-description.cpp:60-62`). Everything else is not admitted with action-not-supported. A Format 3 action whose present CGI is not the node's own cell is refused (KPM §8.2.1.2.3); Format 3 without a CGI stays admitted. | 5–0 after the debate | high |
| OQ-4 | Record only; disclose at Stop B. | 5–0 | high |
| OQ-5 | Record only. A later metric-map lint guard gets its own row. | 5–0 | high |
| OQ-6 | Remove kpimon's `localhost:8090` call (patched `control.go:1282-1301`), leave the idle upstream process, and record it. | 5–0 | high |
| OQ-7 | Not in P15, and not bundled into the TS serving-cell commit. If done, it gets its own commit and row. Stop B decides M10 or later; phase-05 `:62`'s aim stays unmet until then. | 5–0 after the debate | high |
| OQ-8 | C per association, with an identity check on every X2 request part and agreement across parts. Fail closed, never C = 0, never read a response part. Additive "stricter only" amendment to row 153. | 5–0 after the debate | medium-high |
| OQ-9 | Fix the known location columns in the rulings docs commit before code. Each harness commit refreshes its own row's locations. | 5–0 after the debate | high |
| OQ-10 | Extract `kpimon-decode-harness` inside the row-154 helper: reuse `$SODIR` when set, otherwise once per gate run into the gate's work dir, not the evidence dir. A failed extraction fails the same check. | 5–0 | high |
| OQ-11 | A factored `image-tag.sh` with the same inputs (tag `09aeabb8b0f99b0c` recomputed). Load the image inside the checks. The driver pre-flight triggers for {m6, m7, p12, e2i, r0, r1, r2, r3p, s10}. Hand-off: the M10 runner stages the tarball before the first m6. | 5–0 | high |
| OQ-12 | Chain M2, M3, M4, M5, M6, M7, I0, I2, e2i, r3p single, then p12, appended as driver index 15. Check /home ≥ 34 GiB before p12. r0, r1, r2 and s10 meet rows 153 and 154 first at P11 (recorded risk). | 5–0 after the debate | high |
| OQ-13 | No p12 reference artefact exists. The re-baseline is the judge plus its inline fixtures; say so in H3 and in row 155's status. | 5–0 | high |
| OQ-14 | Write P15's null prediction for kpm-headers and collet-start-time at C = 1 into P11's attribution table before the bisection; it supersedes phase-10 `:136`. P15's bisection entry is the harness commit that moves the pin. | 5–0 | medium-high |
| OQ-15 | Settled on the VM: use `e2ap.RICactionID`, `e2ap.ricRequestorID`, `e2ap.ricInstanceID` and `e2ap.RANfunctionID`. Commit the VM output with the row-154 code. The helper prints the tshark version and its `-G fields` lines on every run. | 5–0 | high |
| OQ-16 | A new `kpm-action-routing-test` in `add_executable`, `install` and the Dockerfile test RUN, so M5 enforces it. The routing helper goes in `ns3_e2_agent_core` (`CMakeLists.txt:49-73`). Also update `kpm-report-period-test` `:203`, the `decode_kpm_granularity` callers (`:561-567`) and the mixed case. | 5–0 | high |
| OQ-17 | An `x2ap-codec.sha256` lockfile in the patch dir, in the manifest and the installer list, checked with `sha256sum -c`. `ns3_e2_agent/x2ap_codec` joins `KPIMON_TESTBED_PATHS`, and the guard self-test gains a codec-edit case. Additive amendment to row 74. | 5–0 after the debate | high |
| OQ-18 | Every measData item's `ns3.nodeId` (order 1 in both cell lists) equals the association's node, never identified by IP. Fixture: another node in item k > 0. | 5–0 | high |
| OQ-19 | Join on (association by 4-tuple and time, requestor, instance, RAN function ID), taking the latest successful response before the indication. Only its admitted IDs count. | 5–0 | high |

## Design errors outside the 19 OQs (verified, adopted 5–0 in the debate)
1. **kpm_sim at M3.**
   - The counsel's fail-closed served-cell rule would stop kpimon subscribing NIST's kpm_sim. kpm_sim registers only an NG component (m3-patched.pcap frame 5) and is subscribed today with one Format 3 action (frame 11).
   - Rule: a node with zero X2 components gets C = 0, Format 3 only, with a log line. An X2 component that is present but undecodable, has the wrong identity, disagrees with the others, or gives C > 15 fails closed.
   - Every agent node has at least one X2 component (`agent-config.cpp:98-102`, `e2-node-identity.cpp:149`), and row 153 derives C from the wire, so this rule cannot mask an agent fault.
2. **Pin placement.**
   - H1 = row 153 + the TESTBED_SHA bump + the driver changes (the pre-flight trigger and the p12 step). Then H2 (row 154) and H3 (row 155), each green at the new pin.
   - Precedents: 32232b8d and 3dac03b8.
3. **The "mixed" test case** must change with OQ-1 (see OQ-1).
4. **`KPIMON_TESTBED_PATHS` lacks the codec** (see OQ-17).
5. **p12 runs last** (see OQ-12).
6. **Row 100 drift.** Row 100 was never implemented with asn1-indep; row 153's pycrate decode restores it (ledger note).
7. **Pcaps are untracked** (`plans/.gitignore:53`). The "must fail today" checks are local runs on worktree files or the archive, and self-tests stay inline.
8. **Measurements to take at T3:**
   - Disk headroom: the projection is about 36–40 GiB at p12. Record M3's delta.
   - M3 time: about 2,300 s against a 3,600 s timeout. Measure the cold codec builder stage on the host.
9. **Smaller items:**
   - Extend the existing `e2sm_encode_ric_action_definition_format1_by_id` (`wrapper.c:589`) rather than add a parallel encoder.
   - Build the agent's own CGI from one helper shared with `build_x2_components`.
   - kpimon's KPM library comes from `kpm2_0.asn`, not v03.00. Its Format 1 still has `cellGlobalID CGI OPTIONAL` with both CGI choices.

## Ranking (verifier, blind)

| Rank | Candidate | Total /100 | Note |
|---|---|---|---|
| 1 | E (k3) | 87 | every OQ ruling holds; the most precise OQ-8; pins the codec under row 74; missed the kpm_sim blocker |
| 2 | A (k2) | 84 | found the kpm_sim blocker, the untracked pcaps and the core-library point; endorsed the trailing pin bump |
| 3 | C (k4) | 83 | caught both blockers and the M3 timeout; missed `KPIMON_TESTBED_PATHS` |
| 3 | D (k1) | 83 | best evidence (VM decode files, row 100 drift); missed kpm_sim and p12's position |
| 5 | B (c5) | 68 | fixed the pin order; escalated OQ-8 without need and would have bundled OQ-7 |

ultra: picked=3/5 margin=low unanimous=no rejected_all=no

The debate round then made every contested point 5–0.

## Unresolved questions
- Stop B: whether to fix the measurement list (OQ-4) in M10, and when to do the TS xApp N1 parser move (OQ-7).
- Measured at T3: the kpimon cold-build time and the disk delta. If the projection breaks the 34 GiB guard before p12, revert first, under the standing rule.
- Unverified and moot under action-not-supported: whether SubMgr decodes the CauseRICrequest extension values.
