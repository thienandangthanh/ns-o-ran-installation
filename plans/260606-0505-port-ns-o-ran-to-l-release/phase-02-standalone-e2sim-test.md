# Phase 2 — Standalone L-release e2sim test (M1–M5, no ns-3)

## Context Links
- Overview: [plan.md](plan.md); golden ref from [phase-01](phase-01-confirm-lrelease-e2term.md)
- New base: OSC `e2-interface` `da6f82f2` (= testbed's `e2-interface`)
- Current submodule: `oran-e2sim` (wineslab v1.0, `origin`=our fork, `upstream`=wineslab)

## Overview
- **Priority:** P0. **Status:** planned.
- Prove the rebased e2sim base + toolchain + NodePort path independent of ns-3. Build the **versioned validation harness** here.

## Key Insights
- Validating transport+E2AP+KPM standalone removes ns-3 as a variable; failures here are pure E2-stack/networking.
- Reuse the testbed `e2-interface` build recipe (known to compile on Ubuntu 20.04) for our rebased base.
- Repo is **already virtiofs-mounted on `oran-kvm-2`** — only build deps remain to install there.

## Requirements
- Rebased `oran-e2sim` builds on `oran-kvm-2`; standalone KPM sim passes **M1 SCTP / M2 E2 Setup / M3 RAN func / M4 subscription / M5 dummy KPM** against live E2Term.
- Harness scaffolding asserts M1–M5 automatically with pinned versions.

## Related Code Files
- Modify (`oran-e2sim` fork, branch `dev/l-release`): integrate `e2-interface` `da6f82f2`; keep `build_e2sim.sh` recipe.
- Create: `scripts/l-release-validation/` (`m1-sctp.sh`…`m5-dummy-kpm.sh`, `assert-pcap.sh`, `manifest.txt`), `implementation-notes.html` updates.

## Implementation Steps
1. Install build deps on `oran-kvm-2` (`build-essential g++ cmake libsctp-dev autoconf automake libtool bison flex libboost-all-dev python3`) via SSH+sudo. (Repo already virtiofs-mounted there.)
2. In `oran-e2sim` fork: `git remote add e2interface <OSC e2-interface url>` (origin/upstream already set); fetch; on `dev/l-release` integrate `da6f82f2`. Decide integration shape in notes: **(a)** vendor the L-release e2sim tree wholesale, or **(b)** merge/rebase — pick (a) wholesale-replace if histories diverge too far; document choice.
3. Build on `oran-kvm-2` (`build_e2sim.sh` / CMake); install `libe2sim` + headers; `ldconfig`.
4. Build the bundled KPM example app (`e2sm_examples/kpm_e2sm`); run against node-IP:32222.
5. Author `scripts/l-release-validation/`: pcap capture + `tshark` assertions — M1 SCTP INIT/INIT-ACK; M2 E2setupResponse proc code; M3 RANfunction in setup response (no reject); M4 RICsubscriptionResponse; M5 RICindication w/ E2SM-KPM v3 OID. `manifest.txt` pins e2sim commit, `asn1c` version, e2term image tag (from Phase 1).
6. Run harness M1–M5; compare to `golden-lrelease-e2.pcap`. Record results in notes.

## Todo List
- [x] build deps installed on `oran-kvm-2` (repo already mounted) — libtool reinstalled; asn1c NOT needed (generated C committed)
- [x] `e2-interface` remote added; `da6f82f2` integrated on `dev/l-release` — wholesale-vendored (tree-SHA exact match); **staged, uncommitted**
- [x] `libe2sim` builds + installs on `oran-kvm-2` — `.deb` build + `dpkg -i`; self-built fresh
- [x] bundled KPM app runs against live E2Term — `kpm_sim` (static-linked) → `192.168.122.78:32222` connects
- [x] `scripts/l-release-validation/` M1–M5 + manifest — full harness authored (byte-fallback + retry)
- [x] M1–M3 green vs golden pcap — **byte-identical structural diff**; M4/M5 subscriber-gated (Q4, escalated)

## Success Criteria
Rebased e2sim base, built on `oran-kvm-2`, passes M1–M5 against the live L-release RIC; harness automates the assertions.

## Risk Assessment
- e2sim build fails on 20.04 toolchain → align with testbed's working build flags (it already builds there). Capture diffs in notes.
- Wholesale-replace loses wineslab ns-3 extensions → those are re-applied as adapter in Phases 4/6, not needed for standalone test. Note explicitly.

## Security Considerations
- None beyond lab networking. Pin versions to avoid supply-chain drift on rebuild.

## Next Steps
→ Phase 3: build ns-3's `oran-interface` against this new e2sim base; port E2 Setup (areas A SCTP + B E2AP).
