#!/usr/bin/env bash
# Gate M1 (VM side): Near-RT RIC up on the OSC L-release pins.
# Installs via NIST full_install.sh (unless ricplt already exists), then proves
# pinned SHAs, pod readiness, 10-minute stability, image tags and versions.
#
# Hang risks in NIST scripts (not edited here; fixes would be .patch files on the fork):
#  - install_scripts/wait_for_ricplt_pods.sh:49 `while` has no bound. If e2term never
#    registers with e2mgr, the branch at :88-103 only re-checks forever; the "r"
#    keypress remedy (:139-153) can never arrive on never-EOF stdin, so the gate
#    watchdog (bringup.sh) performs NIST's remedy instead. The :139 `read -t 5` returns
#    after 5 s on a never-EOF pipe (no busy-loop); on EOF it would return instantly.
#  - install_scripts/run_e2sim_and_connect_to_ric.sh:104 `while true` runs until
#    kpm_sim's E2SetupResponse shows in the log; every 3rd wrap (:141-153) it does
#    `systemctl restart kubelet`. Only the outer timeout (nist_run) bounds it.
#  - full_install.sh:319 RIC `./install -f` retry loop and :498 hw-go wait loop are
#    unbounded too. timeout signals the whole process group, so sudo'd children die.
#  - run_e2sim_and_connect_to_ric.sh:90 `docker run -d -it` has no TTY here: unverified,
#    first run will show whether docker tolerates it when detached.
# nist_run (stdin never EOF + outer timeout) is therefore sufficient to avoid a
# CPU-burning busy loop, but not to avoid burning the whole budget on a stuck RIC.
source "$(dirname "$0")/lib.sh"
gate_init m1
source "$(dirname "$0")/bringup.sh"

RICDEP_SHA=ee47a347314aa0749881de367e8fedc4a1bba13a
APPMGR_SHA=4c05932dce72e98db23eaff2b72b58816e1f2d55
INSTALL_BUDGET_S=7000
STABLE_SAMPLES=11            # t=0..600 s, one per 60 s
NIST_DIR="$HOME/nist"
RIC_DIR="$NIST_DIR/RAN_Intelligent_Controllers/Near-Real-Time-RIC"
# full_install.sh clones ric-dep via git_clone.sh into $RIC_DIR/ric-dep (full_install.sh:145/284)
# and appmgr into $RIC_DIR/appmgr (full_install.sh:444; git_clone.sh cds to its parent dir).

################################################################################
# 1. install (skipped when the RIC is already there)
################################################################################
if kc -n ricplt get pods --no-headers 2>/dev/null | grep -q ricplt-e2term; then
    log "ricplt pods already exist: skipping clone and install, going straight to checks"
    record full_install_exit_0 true "skipped: ricplt already installed on this VM"
else
    if [ "$(git -C "$NIST_DIR" rev-parse HEAD 2>/dev/null)" != "$TESTBED_SHA" ]; then
        check testbed_clone clone_pinned "$TESTBED_URL" "$TESTBED_SHA" "$NIST_DIR"
    else
        log "$NIST_DIR already at $TESTBED_SHA: reusing"
    fi
    ric_watchdog_bg
    { cd "$RIC_DIR" && nist_run "$INSTALL_BUDGET_S" ./full_install.sh; } 2>&1 | tee "$EVIDENCE_DIR/full_install.log"
    rc=${PIPESTATUS[0]}
    ric_watchdog_stop
    if [ "$rc" -eq 0 ]; then
        record full_install_exit_0 true "exit 0"
    else
        record full_install_exit_0 false "exit $rc (124/137 = outer ${INSTALL_BUDGET_S}s timeout); tail: $(tail -n 5 "$EVIDENCE_DIR/full_install.log" | tr '\n' '|')"
    fi
fi

################################################################################
# 2. pinned SHAs
################################################################################
sha_is() { local got; got=$(git -C "$1" rev-parse HEAD) || return 1; echo "$got"; [ "$got" = "$2" ]; }
check ricdep_sha sha_is "$RIC_DIR/ric-dep" "$RICDEP_SHA"
check appmgr_sha sha_is "$RIC_DIR/appmgr" "$APPMGR_SHA"

################################################################################
# 3. pods Ready
################################################################################
check ric_bringup gate_bringup ric

################################################################################
# 4. versions (resolved package versions, pod images and digests)
################################################################################
write_versions() {
    local f="$EVIDENCE_DIR/versions.txt"
    {
        echo "--- dpkg (kube*, containerd*, docker*, helm)"
        dpkg -l 'kube*' 'containerd*' 'docker*' 'helm*' 2>/dev/null | grep '^ii'
        echo "--- uname -r"; uname -r
        echo "--- kubectl version"; kc version
        echo "--- containerd --version"; containerd --version
        echo "--- helm version"; helm version
        echo "--- ricplt/ricinfra pod images (pod container image imageID)"
        local ns
        for ns in ricplt ricinfra; do
            kc -n "$ns" get pods -o json 2>/dev/null | python3 -c '
import json, sys
for p in json.load(sys.stdin)["items"]:
    cs = {c["name"]: c.get("imageID", "") for c in p["status"].get("containerStatuses", [])}
    for c in p["spec"]["containers"]:
        print(p["metadata"]["name"], c["name"], c["image"], cs.get(c["name"], ""))
'
        done
    } >"$f" 2>&1
    grep -q 'sha256:' "$f" && grep -q 'Server Version' "$f" && grep -q '^ii' "$f"
}
check versions_recorded write_versions

################################################################################
# 5. image tags
################################################################################
# Expected L recipe tags.
EXPECT_E2TERM=6.0.6; EXPECT_E2MGR=6.0.6; EXPECT_APPMGR=0.5.8; EXPECT_RTMGR=0.9.6; EXPECT_SUBMGR=0.10.2
record_images() {
    kc -n ricplt get pods -o json | python3 -c '
import json, sys
want = ["e2term", "e2mgr", "rtmgr", "submgr", "appmgr"]
found = {}
for p in json.load(sys.stdin)["items"]:
    n = p["metadata"]["name"]
    for w in want:
        if "ricplt-" + w in n and w not in found:
            imgs = [c["image"] for c in p["spec"]["containers"]]
            img = next((i for i in imgs if w in i), imgs[0])
            found[w] = img
for w in want:
    img = found.get(w, "")
    last = img.rsplit("/", 1)[-1]
    tag = last.split(":", 1)[1] if ":" in last else ""
    print(w, tag or "-", img or "-")
' >"$EVIDENCE_DIR/images.txt" || return 1
    cat "$EVIDENCE_DIR/images.txt"
    ! awk '$2 == "-" {bad=1} END {exit !bad}' "$EVIDENCE_DIR/images.txt"
}
check image_tags_recorded record_images

compare_images() {
    local mism="" c want got
    for c in e2term:$EXPECT_E2TERM e2mgr:$EXPECT_E2MGR appmgr:$EXPECT_APPMGR rtmgr:$EXPECT_RTMGR submgr:$EXPECT_SUBMGR; do
        want="${c#*:}"; got=$(awk -v k="${c%%:*}" '$1 == k {print $2}' "$EVIDENCE_DIR/images.txt" 2>/dev/null)
        [ "$got" = "$want" ] || mism="$mism ${c%%:*}: got '${got:-none}' want $want;"
    done
    if [ -z "$mism" ]; then echo "all five tags match the L recipe"; return 0; fi
    echo "mismatch:$mism"; return 1
}
check image_tags_match_l_recipe compare_images

################################################################################
# 6. stability: 11 samples, 60 s apart; all Ready, restart sum never increases
################################################################################
ricplt_sample() {
    kc -n ricplt get pods -o json | python3 -c '
import json, sys
tot, bad = 0, []
for p in json.load(sys.stdin)["items"]:
    n, st = p["metadata"]["name"], p["status"]
    cs = st.get("containerStatuses") or []
    r = sum(c.get("restartCount", 0) for c in cs)
    tot += r
    phase = "Terminating" if p["metadata"].get("deletionTimestamp") else st.get("phase")
    ready = phase == "Succeeded" or (phase == "Running" and cs and all(c.get("ready") for c in cs))
    if not ready:
        bad.append(n)
    print(f"POD {n} {phase} ready={bool(ready)} restarts={r}")
print(f"TOTAL_RESTARTS={tot}")
print("UNREADY=" + ",".join(bad))
'
}
ricplt_stability() {
    mkdir -p "$EVIDENCE_DIR/stability"
    local i base="" tot unready ok=0 f
    for ((i = 0; i < STABLE_SAMPLES; i++)); do
        f="$EVIDENCE_DIR/stability/sample-$(printf %02d "$i").txt"
        { date -u +%FT%TZ; ricplt_sample; } >"$f" 2>&1
        tot=$(sed -n 's/^TOTAL_RESTARTS=//p' "$f"); unready=$(sed -n 's/^UNREADY=//p' "$f")
        [ -n "$base" ] || base="${tot:-0}"
        echo "sample $i: restarts=${tot:-?} (baseline $base) unready='${unready}'"
        if [ -z "$tot" ] || [ -n "$unready" ] || [ "$tot" -gt "$base" ]; then ok=1; fi
        [ "$tot" -le "$base" ] 2>/dev/null && base="$tot"   # a drop (pod replaced) lowers the bar
        ((i < STABLE_SAMPLES - 1)) && sleep 60
    done
    return $ok
}
check ricplt_stable_10min ricplt_stability

################################################################################
# 7. informational: watchdog count, kpm_sim connection
################################################################################
wd=0; [ ! -d "$EVIDENCE_DIR/.watchdog.fired" ] || wd=1
record watchdog_interventions_informational true "e2term deletions by the gate watchdog: $wd"

e2_states() {
    kc get --raw "/api/v1/namespaces/ricplt/services/http:service-ricplt-e2mgr-http:3800/proxy/v1/nodeb/states" 2>/dev/null ||
        { [ -x "$RIC_DIR/additional_scripts/fetch_connected_e2_nodes.sh" ] &&
            nist_run 60 "$RIC_DIR/additional_scripts/fetch_connected_e2_nodes.sh" 2>/dev/null; }
}
states=$(e2_states)
detail=$(echo "$states" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
    print("; ".join(str(n.get("inventoryName", "?")) + "=" + str(n.get("connectionStatus", "?")) for n in d) or "no E2 nodes")
except Exception as e:
    print("e2mgr states unavailable:", e)
' 2>&1)
record kpm_sim_connected_informational true "$detail"

gate_finish
