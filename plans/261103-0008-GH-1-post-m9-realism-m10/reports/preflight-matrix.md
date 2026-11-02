# Preflight matrix (ak:goal-warmup), 2026-11-03 01:55 KST

Every check below was non-mutating. The VM stayed shut off: no snapshot revert, no boot, no cluster access. Checks that need the live RIC are, by design, the plan's own P00/P01 gates (AC6, AC6a, AC6b).

| Phase | Requirement | Check method | Status | Owner / unblock action | Blocking? |
|---|---|---|---|---|---|
| all | VM `ubuntu24.04` defined, shut off | `virsh list --all` | available | — | no |
| all | Snapshots `fresh-install`, `f7-rerun-green` (never deleted), `r3p-green` | `virsh snapshot-list` | available | — | no |
| all | Host tools: virsh, ssh, git, gh, jq, python3, tshark, node, zotero-cli, systemd-run | `command -v` | available | — | no |
| all | GitHub auth for pushes to the forks | `gh auth status` (logged in, keyring; token not shown) | available | — | no |
| all | Fork branches `dev/l-release-nist180` reachable; heads equal the `pins.conf` SHAs (Testbed c6d1434a, ns-3 ba954440, oran-interface 96efc40e, e2sim 2209995a) | `git ls-remote` | available | — | no |
| all | Codex companion ready (read-only reviews, no cap per R3) | `codex-companion setup --json` → ready | available | — | no |
| all | Zotero: OAD v18, E2GAP v08, KPM v03.00, E2SM-RC v03.00 + v01.03 (PDF), E2SM v07, E2AP v03.00, 3GPP TS 37.340, 38.300, 38.323, 36.423, 28.552 | `zotero-cli get metadata <key>` ×12 | available | — | no |
| P00–P12 | /home ≥ 20 GiB free in dev | `df -BG /home` → 54 GiB | available | — | no |
| P01/P03 | /mnt/data headroom for new images + evidence archive (proposed floor 5 GiB) | `df -BG /mnt/data` → 20 GiB free | available (tight) | user confirms the 5 GiB floor (plan Q2) | no |
| P01 | Live e2mgr/e2term accept eNB and en-gNB setups (AC6a) | plan gate P01 (needs VM) | pending | P01; refusal → Decision required (T3) | no (gated in-run) |
| P01 | 10-gNB wall rate and disk growth (AC6b) | plan gate P01 | pending | P01; feeds AC15 simTime and T′ | no (gated in-run) |
| P01 | rc outcome-less-ACK panic and 2 s timer at the deployed SHA (AC6) | plan gate P01 | pending | P01 | no |
| P06/P07 | protoc toolchain reproduces committed `rc.pb.*` byte for byte | plan step (P06/P07) | pending | in-run; failure → T6 | no |
| P13 | /home ≥ T′ at Stop B (T′ ≈ 100–107 GiB method; 87–94 measured; reachable ≈ 96 GiB = 54 free + ~43 GiB active post-M9 overlay once replaced) | `df` + budget at Stop B | missing (projected shortfall) | **user frees space at Stop B**; base (method vs measured) ruled at Stop B | yes, at Stop B only (the plan pauses there by design) |

## Groups

**Must provide before the long run starts:** none. Everything needed to start P00 is available.

**Should decide before the long run (drift risks):**
1. The /mnt/data floor of 5 GiB is the planner's proposal.
2. The T′ base, method sum or measured M9 consumption. The plan defers this to Stop B and flags it at Stop A.

**Can be deferred (the contract or plan allows it):**
- disk freeing at Stop B (contract §5 Stop B);
- the AC6/AC6a/AC6b probe outcomes, which are in-run gates with defined Decision-required exits.
