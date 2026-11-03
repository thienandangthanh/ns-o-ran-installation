# kongming — P05 M5 red: stale agent image (Failure Protocol counsel)

Date 2026-11-04 (Asia/Seoul). Runtime: Claude Code, Opus 5.5 (caller routing). Advisory only; no project files edited besides this note.
Scope: M10 plan `plans/261103-0008-GH-1-post-m9-realism-m10/`, P05 chain `m10-p05-chain-1` (r3p-green, harness b39595a, Testbed pin d84068c). Reviewed the caller's uncommitted draft in `scripts/gates/agents.sh` and `scripts/gates/bringup.sh` (working tree on 2026-11-04).

## TL;DR
The diagnosis is right, and the evidence makes it stronger: M5 reused the exact image the P02-era M5 used. Both fixes are needed, but as drafted they are not quite sufficient. They need two small amendments:
- **A:** keep the e2sim path checkout unconditional, so ledger row 63's "patch at TESTBED_SHA" predicate is not weakened.
- **B:** `agents_install_image` must check by itself that `ns3_e2_agent/` matches the pin before it names an image after the pin. `check` never aborts a gate, so without B the new tag opens a way to cache a wrong image under the pin's name, and the old `-dirty` suffix used to block that.

Keep the tag keyed on the pin, not content-addressed. Re-run the full chain from a fresh revert of r3p-green. Add ledger rows 64 (the agent image predicate) and 65 (the kpm_sim tree rule).

## Diagnosis: confirmed, with evidence
- **The stale image is byte-identical to the c6d1434 build.** M5 `20261103T190346Z` records `ns3-e2-agent:c6d1434a793f`, image ID `sha256:75c327228a4d…`. That is the same ID as M5 `20261103T021740Z` (harness 73bbda6, when the pin was c6d1434). So the agent was not only missing the PPID 70 fix (d48c792). It also lacked all of P03's agent work (eb29f1a: KPM period/granularity admission). Had M5 passed, M6 and p12 would have judged the wrong agent.
- **How the tree got dirty.**
  - M2's `kpm_sim_image_ppid_patched` (bringup.sh:325 @b39595a) checked out the e2sim paths on a clean c6d1434 tree. M3's tree-dirty file lists exactly those two staged paths: `A …/SCTP/e2sim_sctp.cpp` and `M install_e2sim.sh`.
  - That sent M3 down the partial path (kpimon.sh:68-77). HEAD stayed at c6d1434, and `agents_tree_at_testbed_sha` (agents.sh:34-42) then put `ns3_e2_agent/` at d84068c by a path checkout.
  - `want` was keyed on HEAD (agents.sh:170 @b39595a), so `c6d1434a793f` matched the old `run/image.env` and its image. The map sha was unchanged, so the gate logged "not rebuilding".
- **Why P03 escaped.** P03's M3 found the same snapshot clean and did a full checkout (`already-at-sha` in M5 `20261103T051052Z`, which built `809fb2d32cc0`).
- **The guard design worked.** Row 62's wire check caught a stale binary that every tree and image check passed. The defect is in the image-reuse key, not in the judge.
- **The fixed image will differ only by PPID.** `git diff --stat 809fb2d d84068c` touches only `sctp-association.{cpp,hpp}`, `CMakeLists.txt`, the loopback test and the two e2sim files. The r3p "unchanged vs checkpoint 1" expectation holds.

## What to do (ordered)

### 1. Amend fix (1) in `bringup.sh` `kpm_sim_image_ppid_patched`
The draft runs the e2sim path checkout only in the dirty branch. On a tree already at the pin, the patch file is then never restored. `want` becomes the sha256 of whatever is in the working tree, not "the patch file at `TESTBED_SHA`" (row 63's predicate).

Restructure it like this. The path checkout is a no-op on a clean tree at the pin, so it never dirties a clean tree:
```bash
if [ "$(git -C "$RIC_DIR" rev-parse HEAD)" != "$TESTBED_SHA" ] &&
    [ -z "$(git -C "$RIC_DIR" status --porcelain --untracked-files=no)" ]; then
    git -C "$RIC_DIR" checkout -q --detach "$TESTBED_SHA" || return 1
    echo "clean tree: detached checkout of $TESTBED_SHA"
fi
git -C "$RIC_DIR" checkout "$TESTBED_SHA" -- install_scripts/install_e2sim.sh install_patch_files/e2-interface || return 1
```

### 2. Amend fix (2) in `agents.sh` `agents_install_image`
Keep `tag = short12($TESTBED_SHA)` and `NS3_E2_AGENT_TAG="$tag"`. I verified that `nist_run` (lib.sh:89-92) is a plain function and that bash exports a temporary assignment to its children (tested). The installer skips its HEAD/`-dirty` default when the tag is set (install_ns3_e2_agent.sh:35-40).

Add a local precondition before the reuse test:
```bash
git -C "$RIC_DIR" diff --quiet "$TESTBED_SHA" -- ns3_e2_agent &&
    [ -z "$(git -C "$RIC_DIR" ls-files --others --exclude-standard -- ns3_e2_agent)" ] || {
    log "bringup agents: ns3_e2_agent/ is not $TESTBED_SHA's; refusing to name an image after the pin"; return 1; }
```

Why it is needed:
- `check` (lib.sh:53-62) records a failure and carries on. If `*_nist_tree_at_testbed_sha_with_agent_dir` fails, the gate still calls `gate_bringup agents`.
- With the draft, the installer would then build and tag `ns3-e2-agent:<pin>` from non-pin sources and write that name to `run/image.env`. The next gate on that VM would reuse it silently: the same class of bug as this red.
- The old code could not do this. The installer appended `-dirty`, and line 180's `image = want` check failed.
- B keeps the same two conditions the installer uses for `-dirty` (changes to tracked files, plus untracked files that are not ignored), but measured against the pin instead of HEAD. `run/` is gitignored at d84068c.

It will not false-fail on this snapshot line. P03's M5 `051052Z` built with the installer's default tag `809fb2d32cc0` (no `-dirty`), so `status --porcelain` under `ns3_e2_agent/` was empty. If you want zero new failure surface in this one-shot run, drop the untracked conjunct and keep only the tracked diff. Record that choice in row 64.

### 3. Ledger (yes, this is a predicate change)
`agents_install_image`'s final `image = want` (agents.sh:180 @b39595a) is part of the pass condition of every agent bring-up check:
- `m5/m6/m7_bringup_agents_*`
- `p12_*_bringup_agents_connected_set_exact`
- `q8_*`, `s0_*`, `s1_*`, `n4_dump_*`
- `r0_*`, `r1_*`, `<rung>_*_agents_connected_set_exact` (ts-rung-lib.sh:53, r3p:138)
- probes

Add new rows, following the row 59→60 precedent; do not edit landed rows:

| Row | Check | Old | New | Why not weaker | Contract change |
|---|---|---|---|---|---|
| 64 | Every agent bring-up check above, through `agents_install_image` | Image named `ns3-e2-agent:<short12 of ~/nist HEAD>` (reused, or built with the installer's default tag) | Image named `ns3-e2-agent:<short12 of TESTBED_SHA>`, built with `NS3_E2_AGENT_TAG`, and only when `ns3_e2_agent/` equals the pin (tracked diff quiet, no untracked non-ignored files) | On a tree at the pin (every fresh-install run, every full checkout) the old and new names are the same string. On HEAD ≠ pin, the old predicate accepted the HEAD-named image: M5 `20261103T190346Z` ran image ID `75c32722…`, a pre-P03 agent sending PPID 0. A rebuild there would have been tagged `-dirty` and failed. Strictly stronger. | No |
| 65 | `m2/m3_kpm_sim_image_built_with_ppid70_patch` | Predicate unchanged | Side effect only: a clean tree with HEAD ≠ pin first moves to the pin as a whole, as `nist_tree_at_testbed_sha` does | The path checkout of the e2sim files still runs every time, so the label is still compared with the patch file at the pin | No |

Write both rows before the code commit. Use one harness commit for both fixes; the Testbed is unchanged, so there is no pin bump.

### 4. Re-run from a fresh revert of r3p-green, not a resume at M5
Run M2 → M3 → M5 → M6 → M7 → r3p `--mode single` at the new harness SHA. Reasons:
- **Fix (1) changes M2/M3.** Their b39595a evidence did not run the fixed code. A resume would leave fix (1) unproven, and the exit record would mix two harness SHAs.
- **The current VM tree is in a state no real run sees.** It is a c6d1434 HEAD with partial pin paths. Fresh-install end runs are always already at the pin (gate-m1-ric-up.sh:41 → `clone_pinned`), where both fixes are no-ops.
- **The cost is small.** It adds about 50 min (M2 14 min, M3 36 min). The agent image rebuild costs about 2.5 min (P03 M5 `051052Z`, whole gate 05:10:53→05:13:25), well inside the m5 budget. The revert also drops this run's 14 GiB of overlay growth.
- **Do not run a diagnostic M5 on the current dirty VM first.** Under the protocol, a red there is ambiguous and could count as the second red.

## What to avoid
- **Content-addressing on the `ns3_e2_agent/` tree id.** The image's inputs are more than that directory:
  - The Dockerfile builds libe2sim from the e2-interface tree (`COPY src/`), and that tree is patched by `install_e2sim.sh` from `install_patch_files/e2-interface`.
  - The agent links it (`ns3_e2_agent/CMakeLists.txt:49`: `asn1_objects e2sim rc_codec`).
  - A bump that touched only `install_patch_files/e2-interface` would then reuse an image with an old libe2sim.
  - The stubqp tree-id precedent (ts-lib.sh:70) works because `tools/rmr-peer` is self-contained.
- **Deleting the stale image, or "cleaning" the snapshot.** With the pin-keyed tag, the gate never selects `c6d1434a793f`.
- **Folding extra hardening into this one allowed fix:** an image label check, an in-image loopback check, refactoring the two tree rules into one helper. Each adds ledger rows and failure surface. Defer them.

## Alternatives and trade-offs
- **Content-addressed tag (rejected for now).** The honest key would be a hash of three things: the `ns3_e2_agent/` tree, the `install_patch_files/e2-interface` tree, and the e2-interface pin. The gain is skipping a roughly 2.5-minute rebuild on pin bumps that do not touch the agent. The costs: the tag stops naming a commit (`agent-image.env` provenance gets harder to read), the design surface grows, and you redesign a predicate in the middle of the Failure Protocol. If ever wanted, do it in the Testbed: label the image with the input tree ids, as `oransim` has `e2sim.sctp.sha256`, and verify the label on reuse. That needs a pin bump, so it belongs to a later phase.
- **Fix (2) only, no fix (1).** It would turn this chain green, because the agent would rebuild on the partial tree. But dev chains would keep running on mixed trees, where everything outside the kpimon/e2sim/agent paths stays at the snapshot's HEAD (see the hazard below). Fix (1) removes that from clean snapshots.
- **Fix (1) only, no fix (2).** It also turns this chain green, but leaves the stale-reuse hole open for any future snapshot taken from a dirty tree. Keep both.

## Other places keyed on ~/nist HEAD or a partial tree
| Site | Key | Stale on a dirty snapshot tree? | Action now |
|---|---|---|---|
| `agents_install_image` (agents.sh:170 @b39595a) | ~/nist HEAD | Yes (this red) | Fix (2) + amendment B |
| `install_ns3_e2_agent.sh:35-40` default tag | AGENT_DIR HEAD (+`-dirty`) | Bypassed once `NS3_E2_AGENT_TAG` is passed | None |
| Partial path of `nist_tree_at_testbed_sha` (kpimon.sh:68-77): everything except the kpimon installer and patches stays at the old HEAD | n/a | Latent | None for this pin |
| `rc_at_pin` (rc-lib.sh:131), `rc_install` (:44 NIST installer) | rc clone HEAD = RC_SHA | Latent: does not cover Testbed-side rc patch files | Follow-up |
| `ts_at_pin` (ts-rung-lib.sh:357), `ts_install` (ts-lib.sh:123, `TS_PATCH_DIR` :57) | TS clone HEAD = TS_SHA | Latent: does not cover Testbed-side TS patch files | Follow-up |
| kpimon image `kpimon-go:latest` (kpimon.sh:24) | none; rebuilt by every M3 | Safe in chains that include M3. M5 checks only the size-8 .so | None |
| `oransim:0.0.999` | label = patch sha256 (content) | Safe | None |
| stubqp (ts-lib.sh:70) | harness tree id of `tools/rmr-peer` | Safe | None |
| ns-3 build (agents-ns3-run.sh:35-36) | separate clones at NS3/ORAN_INTERFACE SHAs | Safe | None |
| M1 (gate-m1-ric-up.sh:41) | HEAD ≠ pin → `clone_pinned`, only on a fresh install | Safe | None |

Notes on the latent rows:
- **Why rc/TS are not stale now.** c6d1434..d84068c changes no rc, TS, `additional_scripts` (other than kpimon) or `run_e2sim` files; it touches only the kpimon-go patches, `install_e2sim.sh`, the e2sim patch file and `ns3_e2_agent/`. The chain also runs no i0/i2, and with fix (1) the tree is a full checkout from M2 on.
- **When it becomes real.** A pin bump that changes Testbed rc or TS patch files (P06/P07 likely), run from a dirty snapshot tree. `rc_at_pin`/`ts_at_pin` would then pass with old patches. Record this in the exit record for P06/P07.
- **Evidence gap (low, follow-up).** `nist-tree-dirty-before-checkout.txt` writes `git diff --stat`, which shows unstaged changes only. The dirty state here was staged, so that section is empty in both M3 and M5. `git diff --stat HEAD` would show it.

## Work checklist
1. Apply amendment A (bringup.sh) and amendment B (agents.sh) to the draft. Keep the comment wording free of plan IDs.
2. Run `bash -n` and `scripts/gates/lint.sh` on the host.
3. Add ledger rows 64 and 65. Commit the harness change with the rows (no Testbed change, `pins.conf` unchanged).
4. Phase-05 exit record: chain-1 red at M5, its cause, that this is the one kongming-guided fix, then chain-2.
5. Revert r3p-green fresh. Check that the old overlay is unlinked and nothing is orphaned (revertDisks leak landmine). Record `df`/`du` per S5.
6. Chain-2: M2 → M3 → M5 → M6 → M7 → r3p `--mode single` at the new harness SHA.

## Success metrics
- **M2:** the kpm_sim check detail shows `clean tree: detached checkout of d84068c…`, then the label rebuild. M3 and M5 `nist-tree-mode.txt` say `already-at-sha`.
- **M5 image:** `agent-image.env` names `ns3-e2-agent:d84068caf4af`, with an image ID ≠ `75c32722…`, and `install-agent-image.log` exists.
- **M5 wire checks:** `m5_e2ap_ppid70_every_node` passes (`{70: n>0}`, no other PPID; E2AP decoded by PPID equals forced on the port). The E2SetupRequest decodes, and the gNB-ID differs from the reference node.
- **M6/M7:** reuse the same image ID, and every PPID check is green.
- **r3p single:** green, with the ledger and traces unchanged vs checkpoint 1 apart from PPID.

## Assumptions
| Assumption | Confidence | What would change the answer |
|---|---|---|
| r3p-green's ~/nist tree has clean tracked files at c6d1434, so fix (1) takes the full-checkout path | High: P03's M3 did a full checkout from it; this chain's M3 dirty list holds only M2's two paths | A dirty list on revert → the partial path; fix (2)+B still cover it |
| The VM's bash (Ubuntu 24.04, 5.2, not posix mode) exports `VAR=x func` to the function's children, as 5.3 does locally | High | Posix mode → `export` inside a subshell instead |
| There are no untracked, non-ignored files under `ns3_e2_agent/` on the snapshot line | Medium-high (P03 default tag had no `-dirty`) | If B fails on that conjunct → drop it (tracked diff only) and note it in row 64 |
| `SCTP_DEFAULT_SNDINFO` or its per-message fallback works in the agent container on the VM kernel | High: host loopback passed on both paths | A red PPID check with the d84068c image ID → PAUSE T6 is genuine |
| The dev chain does not run M1/i0/i2 | High (exit record) | Running i0/i2 → re-check the rc/TS rows in the table above |

## Unresolved questions
- None blocking. For P06/P07: should the partial tree path also check out the Testbed rc/TS patch dirs (or fail) when a pin bump touches them? Decide when that bump is planned.

Status: DONE
Summary: The diagnosis is confirmed (M5 reused image `75c32722…`, the pre-P03 c6d1434 build). Apply fix (1) with the e2sim path checkout kept unconditional, and fix (2) with a local pin-equality precondition (because `check` never aborts). Keep the tag keyed on the pin, add ledger rows 64–65, and re-run the full chain from a fresh r3p-green revert.
