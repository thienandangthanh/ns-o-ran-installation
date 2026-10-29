# Evidence retention and .gitignore policy (kongming, 2026-10-29 KST)

Read-only counsel. Runtime: Opus 5.5 at xhigh effort. The user's CLAUDE.md routes kongming to opus, not fable. I verified every claim against the tree at `211dacf` and against the untracked files on disk.

## TL;DR

- Git should keep the **verdict layer** of each run: verdicts, check outputs, manifests, M1 versions and the M9 run record. The **raw layer** belongs in a host archive outside the worktree. A full `evidence-sha256.txt` per run directory ties the two together.
- Use a variant of option B: a fail-closed allowlist in a single `plans/.gitignore`. It covers today's three evidence roots and any future one.
- Commit now: about 1,118 small evidence files (0.8 MB) plus 29 new manifests, all with a plain `git add` and no `-f`.
- Do this before anything else: archive the 5.5 GB of raw evidence that git does not hold. It compresses to 0.70 GB as tar.zst. Right now it exists only inside this orca worktree.

## 1. Do we need evidence in git, and why?

Git needs the verdict layer. It does not need the raw layer. These are the concrete consumers, all verified:

| Consumer | What it reads | Needs git? |
|---|---|---|
| `scripts/m9-budget.py:24,45-48` | every `<gate>/*/verdict.json` under both roots (green, not dev) | **Yes, every verdict.** Today the host and a fresh clone see different sets. 11 verdicts from attempts 1–3 are untracked, and `m2/20261028T114909Z` (green, 908 s) exceeds the budget's m2 basis of 846 s (`scripts/m9-budget.json`). A re-run would give different budgets on the host and in a clone. |
| `scripts/m9-verdict.py:41-45,67-75` | `steps.tsv`, per-step `verdict.json`, and the watchdog files in `m9/<ts>/` | **Yes.** All of these are tracked for attempt 4. Portability caveat: `steps.tsv` holds absolute host paths (via `.last-*`, `run-to-m9.sh:195`), so a clone cannot re-judge without a path fix. That belongs to the second-machine goal, not to retention. |
| `scripts/compare-run-versions.py:18-23` | M1 `versions.txt` (+ supplement) | **Yes.** The dev baseline `m1/20261021T213103Z` is tracked. The green M9's `m1/20261028T170205Z/versions.txt` and `images.txt` are **untracked**, so no drift check of the green run is possible from git. |
| `tools/e2-evidence/replay-m7-analysis.sh:2-3,24` | `m7.pcap`, `ns3run/*.jsonl`, `agents.json`, `checks/` | **No.** Pcaps have always been gitignored, so replay has never worked from a clone. The host archive is the replay store. |
| `tools/rmr-peer/fixtures/README.txt:3` | cites `r1/20261023T084654Z/live1.pcap` | **No.** It is provenance only (the pcap is ignored), and the hex fixtures are self-contained. |
| `gate-s0-free-control.sh:6`, `compare-free-run.py:3` | `evidence/p1-free-run-reference/v1-rule.md` | **Yes.** It is a rule document at depth 2, which the allowlist leaves alone. |
| Run report, README, docs, counsels (63 dirs) | `verdict.json`, `gate.log`, `rt-readers-*`, `watchdog.log`, the m9 dir, `checks/*.out`, `facts.jsonl` | **Yes.** Every file the M9 run report cites is tracked. For example, `run-report-261029-0535…:51` cites `watchdog.log` and `rt-readers-*`. |
| `README.md:76`, `evidence/.gitignore:1-2` | claim that "each evidence dir carries a pcap-sha256 manifest" | This is **currently false in git for the green run.** The manifests exist on disk for all 15 attempt-4 dirs but are untracked. |

Nothing runnable from a clone breaks without the raw layer. The raw layer matters for:
- re-deriving results;
- baselines for the realism pass;
- the upstream bug report (handoff follow-up 4 needs the `m9/20261028T134954Z/m6-diagnosis/` raw logs);
- possible publication.

Those needs call for **retention**, not git.

**The real gap is retention, not `.gitignore`.** 4.92 GB of ignored files and 0.58 GB of untracked files live only in this orca worktree. That includes the raw data behind the M9 green. Any of these would delete it: `git worktree remove`, deleting the workspace, or `git clean -fdx`.

## 2. Policy

**Recommendation: B+ with an archive, for both the current files and future runs.**

Why not A (ignore by type):
- It is a fail-open blocklist. Every new artifact class gets committed by default, which is how 15k tracked files (2.2 GB) piled up and how `f2138f0` happened.
- It commits install logs and pod dumps (see §3).
- About 18 MB per cycle, mostly noise: `tshark-protocols.txt` is a static 0.59 MB protocol list, and the pod dumps are before/after duplicates.

Why not plain B:
- It drops small files that back claims:
  - full check outputs: verdict `detail` is truncated near 2 KB (`r3p_live3_agents_stopped.out` is 7,334 B, its detail 2,030 B);
  - M1 versions;
  - the manifests;
  - the m1 `refresh-ric-*` diagnostics behind `run-report:51`.
- Per-root rules also miss a new plan's evidence root.

### Exact rules: a new file `plans/.gitignore`

```gitignore
# Gate evidence lives in plans/<plan>/evidence/<gate>/<UTC ts>/.
# Git keeps each run directory's verdict layer. Raw output (traces, logs, pod
# dumps, captures) stays in the host evidence archive and is bound to git by
# the run directory's evidence-sha256.txt. To keep a raw file in git, promote it
# to plans/<plan>/reference/ or add a commented negation here; never git add -f.
/*/evidence/*/*/**
!/*/evidence/*/*/**/
!/*/evidence/*/*/**/verdict.json
!/*/evidence/*/*/**/gate.log
!/*/evidence/*/*/**/exit_code
!/*/evidence/*/*/**/watchdog.log
!/*/evidence/*/*/**/checks.jsonl
!/*/evidence/*/*/**/checks/*.out
!/*/evidence/*/*/**/facts.jsonl
!/*/evidence/*/*/**/rt-readers-*.txt
!/*/evidence/*/*/**/refresh-ric-*
!/*/evidence/*/*/**/*-sha256.txt
!/*/evidence/*/*/**/*.manifest.json
!/*/evidence/*/*/**/versions*.txt
!/*/evidence/*/*/**/images.txt
# The M9 run directory is the run-level record: keep its top-level files.
!/*/evidence/m9/*/*
# Host live state, rewritten by every run (steps.tsv and m9/<ts>/ keep the values).
/*/evidence/.last-*
/*/evidence/watchdog/
# Captures never go to git, whatever their name.
*.pcap
*.pcapng
*.pcap.gz
```

I verified these semantics in a scratch repo:
- allowlisted names are admitted at any depth in a run dir (for example `runs/live1/checks/*.out`), and so is a nested dev layout (`dev-p5/smoke/<ts>/`);
- `m9/<ts>/` top-level files are admitted, but `m9/<ts>/m6-diagnosis/*.log` is not;
- `refresh-ric-*.pcap` stays ignored;
- depth-2 files (`p1-free-run-reference/v1-rule.md`, `m9/runner-q-access.log`) are unaffected;
- a tracked `.last-*` stays tracked (`.gitignore` cannot untrack it).

The existing per-root `evidence/.gitignore` files stay as they are. They only add ignores and do not conflict.

When I simulated the rules on the current tree, they admitted **1,118 evidence files, 0.8 MB; the largest is 87.5 KB**. Excluded are all of `timing/`, `runs/` raw, `ns3run/`, the kpimon logs, `*-lines.txt`, install and launch logs, pod dumps and decodes.

### Future runs

After any gate, `git add plans/` is safe as is. If a dev run genuinely needs raw data in git, **promote it** rather than force-adding it:
- copy it to `plans/<plan>/reference/<name>/` with a `SHA256SUMS` file and a one-line README naming its consumer, the same route `reference/r3p/` already uses;
- or add a commented negation line to `plans/.gitignore` that names the claim it supports.

### Files to commit now (order matters; see the checklist)

1. **Commit 1:** `plans/.gitignore` itself.
   - Also `git rm --cached` the 30 tracked `.last-*` files and `plans/261023-0009-…/evidence/watchdog/min-host-free-gb.txt`. This also discards the pending `.last-m6` modification.
   - Reword `README.md:74` and `docs/deployment-guide-l-release.md:147` to say `.last-mN` is host-local.
2. **Commit 2:** `git add plans/*/evidence`, which stages:
   - the 11 `verdict.json` files from attempts 1–3 (m0 ×2, m0-host ×2, m1 ×2, m2 ×2, m3, m4, m5);
   - 959 `checks/*.out` and 26 `checks.jsonl`;
   - 25 `exit_code`;
   - 12 `gate.log`;
   - 6 `facts.jsonl`;
   - 25 `pcap-sha256.txt` and 25 `ns3run-sha256.txt`;
   - 11 kpimon `*.manifest.json`;
   - 3 `versions.txt` and 3 `images.txt` (M1 drift baselines, including the green run's);
   - 12 `refresh-ric-*` files (the m1 bring-up remedy);
   - 29 new `evidence-sha256.txt` manifests.
3. **Separately, not evidence:** commit `plans/handoffs/m8-m9-open-questions-before-goal-reissue-20261027-2120.md`. `decisions-261027-2155…` cites it, but it is untracked.

**I disagree with prior counsel here.** `kongming-261029-0550…:72` said to commit `.last-*` and `watchdog/min-host-free-gb.txt`. I now advise untracking them, for these reasons:
- `vm-exec.sh:92` rewrites `.last-*` on every gate.
- `run-to-m9.sh:133` wipes `watchdog/` at every start, and `:111-113` copies the values into `m9/<ts>/`.
- `steps.tsv` already records each step's directory.

Tracking them only buys a dirty tree after every run. The stakes are low. If the user prefers to keep them tracked, delete the two "Host live state" lines.

## 3. Risks

**Public exposure.** I grep-sampled all 3,318 untracked files.
- They contain the same classes of data that are already public in tracked evidence:
  - libvirt NAT IPs `192.168.122.x`, ClusterIPs `10.x` (405 distinct already tracked) and veth MACs (216 tracked);
  - the paths `/home/andang` and `/home/uc`, and the VM hostname;
  - a GitHub noreply email;
  - expired packagecloud CloudFront signed URLs, already in tracked m1/m3 logs.
- There is no Influx token, JWT, kube cert or key, private key, `ghp_` or `AKIA` string.
- Pod dumps reference the Influx password and admin token only through `secretKeyRef`. `scrub-evidence.sh:66` now also redacts the pod's admin token.
- **New gap:** the three untracked m1 `full_install.log` files hold a **kubeadm bootstrap token and the discovery CA hash**.
  - The same leak already exists in at least 10 tracked files: the m0–m7 m1 `full_install.log`/`gate.log`/`launch.log`, and m8–m9 `m1/20261028T092443Z`.
  - It is not exploitable. Every revert destroys the cluster, the API is on a private NAT, and the default token TTL is 24 h.
  - Still, the scrub (`scrub-evidence.sh:80-83`) knows only Influx-shaped tokens. The allowlist keeps install and launch logs out of git. Add a context-anchored regex anyway (`(Using token: |--token )[a-z0-9]{6}\.[a-z0-9]{16}`).
- Note: the `REDACTED-LONG-TOKEN` strings in the install logs come from `scripts/gates/kpimon.sh:35`. That filter also erases image digests from those logs.

**Bloat.**
- Tracked evidence is 2.2 GB apparent, which packs to 69 MiB.
- Committing the whole untracked set would add about 77 MB gzip (timing 56, runs 12, ns3run 2.5, rest 6) **per M9-scale cycle**.
- It would be permanent, because there is no history rewrite (`decisions-261027-2155…:10`).
- Five to ten realism-pass runs would push the pack toward GitHub's recommended 1 GB.
- Option A adds about 6 MB gzip per cycle. B+ adds about 1.3 MB raw per cycle.

**Reproducibility.**
- B+ keeps:
  - every verdict and full check output;
  - the M9 run record;
  - the M1 versions;
  - a digest of every raw file.
- Re-derivation needs the archive, which is already true for pcaps.
- The manifest also makes absence claims checkable from git. For example, the run report (Bring-up remedies table, row 2) says "no `agents-ready-remedy.txt` anywhere".

**Repo rules.**
- No conflicts. The evidence and this report are under `plans/` (Markdown rule, `brainstorm-261022-2105…:213`), and the allowlist removes any reason to force-add.
- One inconsistency to fix: `handoff-261029-0540…:25` says the `f2138f0` history rewrite "is pending the user's approval", but the ruling is "Keep it public. No history rewrite." (`decisions-261027-2155…:10`).

## Alternatives and trade-offs

- **git-lfs.** Rejected. It brings LFS quota and bandwidth limits on a public repo, LFS tooling in every clone, and the same permanence. Nobody consumes raw evidence from a clone.
- **GitHub release asset or Zenodo for publication.** Right when a paper or artifact evaluation needs raw data.
  - Release assets: each file must be under 2 GiB, there is no total cap, they can be deleted, and they are not in clones.
  - Zenodo: 50 GB per record, 100 files, and a DOI.
  - The green M9's raw data is about 0.92 GiB uncompressed, so it fits either. Do this at publication time, not now.
- **Stop committing evidence.** Rejected. It breaks `m9-budget.py`, `m9-verdict.py`, `compare-run-versions.py` and 63 document citations.

## Work checklist (the caller executes; I staged nothing)

1. **Manifests.** For every run dir with untracked files:
   ```bash
   git ls-files -o --exclude-standard -z plans/ | tr '\0' '\n' | grep '/evidence/' | grep -v '/evidence/watchdog/' | cut -d/ -f1-5 | sort -u |
     while read -r d; do (cd "$d" && find . -type f ! -name evidence-sha256.txt -print0 | LC_ALL=C sort -z | xargs -0 sha256sum >evidence-sha256.txt); done
   ```
   This covers 29 dirs and about 4,067 files.
2. **Archive before changing any ignore rule.**
   - `A=~/evidence-archive/ns-o-ran-installation; mkdir -p "$A"; git ls-files -o -z plans/ | tar --null -T - --zstd -cf "$A/plans-evidence-raw-20261029.tar.zst"`
   - Check that `tar --zstd -tf … | wc -l` equals `git ls-files -o plans/ | wc -l`.
   - Run `sha256sum` on the tarball and append the result to `"$A/SHA256SUMS"`.
   - Expect about 0.70 GB.
   - Optionally keep a second copy off `/home`.
3. **Commit 1.**
   - Write `plans/.gitignore` from §2.
   - `git rm --cached -- 'plans/*/evidence/.last-*' plans/261023-0009-GH-1-m8-m9-paced-rungs-and-m9/evidence/watchdog/min-host-free-gb.txt`
   - Reword README:74 and deployment-guide:147.
4. **Commit 2.** `git add plans/*/evidence`, then gate the stage:
   - `git diff --cached --name-only | wc -l` should be about 1,147;
   - `git diff --cached --name-only -z | du -cb --files0-from=- | tail -1` should be under 2 MB;
   - `git diff --cached --name-only | grep -E 'full_install|launch\.log|pods-(before|after)|/timing/|/runs/.*\.(log|csv|jsonl)|/ns3run/'` must print nothing;
   - `git diff --cached | grep -cE 'Using token:|kubeadm join|[A-Za-z0-9_-]{80,}=='` must print 0.
5. **The handoff file.** Commit `plans/handoffs/m8-m9-open-questions-…-2120.md` separately.
6. **Later code commit, reviewed, run through lint and selftests.**
   - `vm-exec.sh`: after the copy, write `evidence-sha256.txt` over `$dest`. Keep `pcap-`/`ns3run-sha256.txt` so the docs contract holds.
   - `gate-m0-host.sh`: the same for `<ts>-host`.
   - `scrub-evidence.sh`: add the kubeadm regex.
7. **Docs** (an operational route, so this is docs impact). In deployment-guide §5 "Evidence layout" and README "Where evidence lands", state:
   - what git keeps;
   - the archive path;
   - the manifest;
   - the promotion route.
   Fix the handoff :25 contradiction.

## Success metrics

- After the next gate run, `git add plans/` (without `-f`) stages less than 2 MB, and `git status --porcelain plans/` is empty afterwards.
- `find plans -path '*/evidence/*/*/verdict.json' | wc -l` equals `git ls-files 'plans/*/evidence/*/*/verdict.json' | wc -l`. That means `m9-budget.py` gets the same inputs on the host and in a clone.
- Every evidence path cited in tracked Markdown is either tracked or listed in its dir's `evidence-sha256.txt`. An extracted sample from the archive passes `sha256sum -c` against that manifest.
- Pack growth per M9 cycle stays under 1 MiB (`git count-objects -vH` before and after).

## Assumptions

- **High:** deleting the orca workspace or worktree deletes ignored and untracked files. If raw evidence were already mirrored elsewhere, step 2 would be a duplicate, not a rescue.
- **High:** no CI or external tool reads raw evidence from git (there is no `.github/`). If one appears, promote the class it needs to `reference/`.
- **High:** the kubeadm tokens are harmless, because every revert destroys the cluster and the API is on a private NAT. If the VM or cluster were reachable or persisted, rotate them and prioritize the scrub fix.
- **Medium:** the user wants a public audit trail, not raw-data publication, right now. If a paper or artifact evaluation needs raw data, use Zenodo or a release asset (C2).
- **Medium:** a 0.70 GB archive on `/home` is acceptable. `/home` has 59 GB free. The larger disk risk for the next M9 is the overlay leak (handoff follow-up 2), not this archive.

## What would change my mind

- **The user will not keep a host archive.** Then git is the only durable store. I would commit A's small rest as well, but still exclude install and launch logs and pod dumps.
- **A consumer must run on raw data from a clone** (CI replay, comparing traces on a second machine). Then promote that class to `reference/` with `SHA256SUMS`.
- **Publication needs raw data.** Then use C2. Git still stays verdict-only.

## Unresolved questions (user)

1. Archive location and a second copy: `/home`, `/mnt/data` (21 GB free) or external?
2. Do you accept untracking `.last-*` and `watchdog/`? This reverses the 0550 counsel's step 5.
3. Out of scope here: should the untracked `.claude/agent-memory/` and `.remember/` go into a public repo at all?

Sources: [GitHub: About releases](https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases), [GitHub: About large files](https://docs.github.com/en/repositories/working-with-files/managing-large-files/about-large-files-on-github), [Zenodo size limits](https://support.zenodo.org/help/en-gb/1-upload-deposit/80-what-are-the-size-limitations-of-zenodo), [Zenodo policies](https://about.zenodo.org/policies).
