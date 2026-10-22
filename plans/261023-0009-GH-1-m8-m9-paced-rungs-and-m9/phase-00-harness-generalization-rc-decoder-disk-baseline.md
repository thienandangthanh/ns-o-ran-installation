# P0: Harness generalization, RC wire decoder, disk baseline

**Start state:** VM running at `f7-rerun-green`. **Snapshot at exit:** none.

## Context
The M0–M7 harness cannot run R-rungs or M9 as it stands (verifier-2105 §7, verified):
- `scripts/vm/vm-exec.sh:29` derives the gate id with `^gate-(m[0-9]+)`, so an `r0` gate gets its whole file name as id, and several `gate-m8-*` scripts would share `.last-m8`.
- `scripts/vm/vm-common.sh:14` defaults `EVIDENCE_HOST_ROOT` to the M0–M7 plan dir (env override exists).
- `scripts/run-to-m7.sh:44-45` forces `f7-rerun-green` for prefix `f` even with `--no-snapshots`, and that snapshot exists, so `vm-snapshot.sh:33` would die.
- Host free space is checked only at `gate-m0-host.sh:33` and in `vm-snapshot.sh create` (`:34-36`). A no-snapshot M9 would never re-check it.
- The RC gates need an independent E2SM-RC v2.0 wire decoder. The probe pcap (`plans/261022-1026-GH-1-pre-m8-pacing-planning-gate/evidence/rc-control-latency/…`) is gitignored (`evidence/.gitignore:2`), so the test fixture must be committed hex.

## Requirements (contract)
In scope 3 (scripted gates, M9 runner groundwork); constraints (disk ≥ 20 GB, scripted gates, never on rc's log).

## Files
- Modify: `scripts/vm/vm-exec.sh` (gate-id regex `^gate-([a-z][0-9]+)`), `scripts/vm/vm-common.sh` (comment only; keep the default), `scripts/gates/lint.sh` (cover new files).
- Create: `scripts/run-to-m9.sh` (skeleton: gates M0–M7 then R0–R3, `--run-prefix` must not be `f` or `l`, default `n`; sets `EVIDENCE_HOST_ROOT` to this plan's `evidence/`; starts the host disk watchdog), `scripts/vm/host-disk-watchdog.sh` (polls `df --output=avail -BG /home` every 60 s; below `HOST_MIN_FREE_GB` it writes `watchdog-tripped.json` and signals the runner, which stops the chain), `tools/rc-decode/` (Dockerfile + build script: asn1c mouse07410@584d86e on rc@a2282ee `e2sm/e2sm-rc-2.0.asn`, prints XER of header, message and outcome), `tools/rc-decode/fixtures/rc-control-requests.hex` (RICcontrolRequest PDUs extracted from the probe pcap, scrubbed), `tools/rc-decode/test-rc-decode.sh`.
- Evidence: `evidence/p0-disk-baseline/<UTC-ts>/` (image chain sizes, `df`, snapshot list).

## Steps
1. Update the resume card. Verify the VM: `virsh -c qemu:///system domstate ubuntu24.04` = `running`; `scripts/vm/vm-snapshot.sh list` shows `fresh-install` and `f7-rerun-green`; current = `f7-rerun-green`.
2. Verify the pins: `git ls-remote` of each fork's `dev/l-release-nist180` equals `scripts/pins.conf`; QP fork `master` = `47a35ca`.
3. Disk baseline: record `df -h /home`, `du -b` of each file in the image chain (`virsh domblklist`, `dumpxml`; images are `libvirt-qemu`-owned, so use `du`, not `qemu-img`), and the first M9 projection table (host free − dev overlays − M9 overlay ≈ 40 GB inferred ≥ 20 GB). A negative projection is noted for Stop A (not a pause yet).
4. Fix the gate-id regex; add a self-test in `lint.sh` that maps `gate-m5-agent-setup.sh→m5`, `gate-r0-rc-scripted.sh→r0`, `gate-s1-pacer.sh→s1`.
5. Write `run-to-m9.sh` and `host-disk-watchdog.sh`. The runner refuses prefix `f` and `l` and any prefix whose snapshot names exist; with `--no-snapshots` it never creates a snapshot, including at M7.
6. Build `tools/rc-decode`; extract the RICcontrolRequest PDUs from the probe pcap into hex; run the scrubber over the fixture; commit it.
7. Commit and push the harness; run the phase-exit checklist.

## Verify (comparison only)
- V1: `scripts/gates/lint.sh` exits 0; the regex self-test prints `m5 r0 s1`.
- V2: `scripts/run-to-m9.sh --harness-sha HEAD --run-prefix f` exits non-zero with `prefix f is reserved`.
- V3: `HOST_MIN_FREE_GB=100000 scripts/vm/host-disk-watchdog.sh --once` exits non-zero and writes `watchdog-tripped.json`; with the default it exits 0.
- V4: `tools/rc-decode/test-rc-decode.sh` exits 0 and, for every fixture PDU, prints a header with `ric-Style-Type 3`, `ric-ControlAction-ID 1` and a message with the NR CGI; the count equals the fixture line count.
- V5: `grep -c` of the Influx token pattern used by `scrub-evidence.sh` over `tools/rc-decode/fixtures/` = 0.
- V6: `evidence/p0-disk-baseline/<ts>/` contains `df.txt`, `chain-sizes.txt`, `snapshots.txt`, `m9-projection.md`.

## Standards ledger
| Decision | Document, version, section | Zotero | Read |
|---|---|---|---|
| Decoder schema = rc's E2SM-RC v2.0 ASN.1; control-path types equal v03.00 | E2SM-RC v03.00 (control header/message/outcome Format 1); version gap: rc's file lacks the RIC Query types | `XRWZU3SS` | 2026-10-22 (decision record 22:30) |

## Failure Protocol
If any Verify step does not meet its stated pass condition, STOP this phase.
Do not improvise a fix, retry blindly, or reason around the failure.
Spawn the `kongming` subagent (`model: opus`) for next-step counsel and pass:
- the phase and task id,
- what you attempted (the steps you ran),
- the exact command and its full output (scrubbed),
- the pass condition it failed to meet.
Apply kongming's guidance, then re-run the Verify step. If it fails again, or the guidance would change the locked outcome, print `PAUSE T6 evidence=<path> journal=<path>` and call no further tool.
If `kongming` cannot be spawned, STOP and print the same PAUSE line with the failure evidence. Never continue by self-reasoning. kongming's counsel is never user approval.

## Phase exit
Run the plan's phase-exit checklist, then spawn kongming (`model: opus`) for a go/no-go on P1.

## Risk and rollback
Risk: the pinned asn1c does not build rc's ASN.1 cleanly (constraint-check landmine, memory `rc-asn1c-base-phase3`). Rollback: revert the harness commits; nothing on the VM changes in this phase.

## Review amendments (binding; they override any conflicting text above)
Source: `plans/reports/kongming-261023-0020-GH-1-m8-m9-plan-collect-only-review.md`, classified in `plans/reports/review-261023-0009-GH-1-m8-m9-contract-preserving-review-and-preflight-matrix.md`.
- **K1 (step 5, V2).** `run-to-m9.sh` runs `gate-m0-host.sh`, which creates `m0-probe-<prefix>` and creates then deletes `m0-branch-<prefix>` (`:40-49`). The 01:03 KST snapshot rule allows this. Apart from that pair, `--no-snapshots` creates no snapshot.
- **Protected snapshots.** `vm-snapshot.sh delete` refuses `fresh-install`, `f7-rerun-green` and `r3-green` before any virsh call. Add `vm-snapshot.sh check-protected <name>` and test it: V7: `check-protected f7-rerun-green` prints `protected` and exits 0; `check-protected r0-green` prints `deletable`.
- **K2 (step 3).** Projection = host free now − expected further dev growth (rebuilds, images, per-run VM evidence) − M9 need (M0–M7 measured 39.7 GB + R-rung installs and evidence) − 20 GB. Overlays already on disk are already inside "host free now". A negative projection is reported, not paused (user, 01:30 KST): the user frees the measured shortfall at Stop B. T2 fires only when actual free space would cross 20 GB plus the next growth.
- **K15 (watchdog).** It takes `--min-gb N` (no env prefix) and trips at 20 GB + margin (default 25 GB). On a trip it stops the VM-side unit (`systemctl stop gate-*` over ssh), shuts the VM down gracefully, and records `minHostFreeGb`. V3 becomes: `host-disk-watchdog.sh --once --min-gb 100000` exits non-zero and writes `watchdog-tripped.json`; a dummy VM unit started for the test is stopped by the trip.
- **K16.** Create `evidence/.gitignore` in this plan dir (pcaps, large ns-3 traces, raw Influx dumps). Gates delete large VM-side traces after writing their sha256 manifest. The projection counts per-run VM evidence. V8: `git check-ignore evidence/x/y.pcap` exits 0.
- **K23 (decoder).** Compile both `e2sm/e2sm-rc-2.0.asn` and `e2sm/e2sm-common.asn` from rc@a2282ee. The fixture is tshark-extracted `RICcontrolHeader`/`RICcontrolMessage` octets. Add a synthesized `E2SM-RC-ControlOutcome-Format1` (empty `ranP-List`) round-trip. The build works with podman (host `docker` is a podman shim). The gates also build the decoder VM-side, so M9 builds it on a fresh VM.
- **K24 (regex).** Use `^gate-([a-z]+[0-9]+)`. The self-test maps `gate-m5-agent-setup.sh→m5`, `gate-r0-rc-scripted.sh→r0`, `gate-s1-pacer-lockstep.sh→s1`, `gate-q7-qp-token-check.sh→q7`; V1 prints `m5 r0 s1 q7`.
- **K13 (config).** Commit `scripts/gates/rung-config.json` (values plus provenance: T_ctl, W, substitution states, A1 threshold, UL rate, scenario and schedule paths). Every gate and `run-to-m9.sh` read it, and gates take `--mode single|c1`. `run-to-m9.sh` install order: decoder build and `rc-install` before r0; `ts-xapp-install` plus the stub before r2; stub down and `qp-install` before r3.
- **K3.** There is no rules file; the run uses auto mode as in M0–M7 (user, 01:30 KST). Step 1 runs each command form the plan uses once in a harmless mode (`list`, `--once`, `--help`). Any classifier refusal is T8.
