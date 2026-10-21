#!/usr/bin/env bash
# Gate M0 (VM side): environment facts, egress, package availability on noble,
# pinned-fork fetchability and `git apply --check` dry runs of NIST patches.
# Read-only with respect to the system: no apt sources touched, nothing installed
# except git when missing. Host-side checks (df, virsh, gh, snapshot probe) live elsewhere.
source "$(dirname "$0")/lib.sh"
gate_init m0

WORK=/tmp/m0
rm -rf "$WORK"; mkdir -p "$WORK"
NIST_RIC=$WORK/testbed/RAN_Intelligent_Controllers/Near-Real-Time-RIC
RICDEP_URL=https://gerrit.o-ran-sc.org/r/ric-plt/ric-dep.git
RICDEP_SHA=ee47a347314aa0749881de367e8fedc4a1bba13a
KPIMON_URL=https://gerrit.o-ran-sc.org/r/ric-app/kpimon-go.git
KPIMON_SHA=8bbbbbb90093db01f88820de755bce0ee2189c88
APPMGR_SHA=4c05932dce72e98db23eaff2b72b58816e1f2d55

# git is the only package this gate may install.
command -v git >/dev/null 2>&1 || sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y git

################################################################################
# 1. facts
################################################################################
{
    echo "hostname: $(hostname)"
    echo "primary_ipv4: $(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}')"
    echo "--- lsb_release -a"; lsb_release -a 2>&1
    echo "--- uname -r"; uname -r
    echo "--- df -h /"; df -h /
    echo "--- free -g"; free -g
    echo "--- nproc"; nproc
    echo "--- stat -fc %T /sys/fs/cgroup"; stat -fc %T /sys/fs/cgroup
    echo "--- swapon --show"; swapon --show
} >"$EVIDENCE_DIR/facts.txt" 2>&1
log "facts written to $EVIDENCE_DIR/facts.txt"

check os_is_24_04 bash -c '[ "$(lsb_release -rs)" = 24.04 ] && lsb_release -rs'
check cgroup_v2 bash -c '[ "$(stat -fc %T /sys/fs/cgroup)" = cgroup2fs ] && echo cgroup2fs'
# 14 GiB threshold on MemTotal (a "16 GB" VM reports ~15.x GiB).
check ram_ge_14g bash -c 'kb=$(awk "/MemTotal/{print \$2}" /proc/meminfo); echo "MemTotal_kB=$kb"; [ "$kb" -ge $((14*1024*1024)) ]'
check cpus_ge_8 bash -c 'n=$(nproc); echo "nproc=$n"; [ "$n" -ge 8 ]'
check root_free_ge_60g bash -c 'g=$(df -BG --output=avail / | tail -1 | tr -dc 0-9); echo "root_avail_G=$g"; [ "$g" -ge 60 ]'
# Swap is expected ON: NIST's installer disables it later. Informational pass.
swap_detail=$(swapon --show 2>&1 | tr '\n' ';')
record swap_state_informational true "swap expected on at M0, NIST disables it later: ${swap_detail:-none}"

################################################################################
# 2. sctp
################################################################################
check sctp_module bash -c 'sudo modprobe sctp && lsmod | grep "^sctp"'

################################################################################
# 3. egress: pass on any HTTP status (401/403/404 are fine), fail on 000
################################################################################
egress() {
    local url="$1" code
    code=$(curl -sS -o /dev/null -m 15 -w '%{http_code}' "$url") || code=000
    echo "$url -> HTTP $code"
    [ "$code" != 000 ]
}
for u in https://github.com https://registry-1.docker.io/v2/ https://pkgs.k8s.io \
    https://gerrit.o-ran-sc.org https://nexus3.o-ran-sc.org:10002/v2/ https://packagecloud.io \
    https://dl.google.com https://proxy.golang.org https://ppa.launchpadcontent.net \
    https://download.docker.com https://packages.buildkite.com https://nexus3.o-ran-sc.org; do
    check "egress_$(echo "${u#https://}" | tr '/:' '__')" egress "$u"
done

################################################################################
# 5. testbed fork (cloned early: package checks read versions from its script)
################################################################################
check testbed_clone clone_pinned "$TESTBED_URL" "$TESTBED_SHA" "$WORK/testbed"
check testbed_commit_hashes python3 -I - "$NIST_RIC/commit_hashes.json" "$RICDEP_SHA" "$APPMGR_SHA" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
want = {"https://gerrit.o-ran-sc.org/r/ric-plt/ric-dep.git": sys.argv[2],
        "https://gerrit.o-ran-sc.org/r/ric-plt/appmgr.git": sys.argv[3]}
ok = True
for url, sha in want.items():
    got = d.get(url, [None, None])[1]
    print(url, "pinned", got, "OK" if got == sha else f"MISMATCH want {sha}")
    ok &= got == sha
sys.exit(0 if ok else 1)
PY

################################################################################
# 4. package availability on noble, from repo indexes (apt untouched)
################################################################################
INSTALLER=$NIST_RIC/install_patch_files/ric-dep/bin/install_k8s_and_helm.sh
KUBEV=$(sed -n 's/^KUBEV="\([^"]*\)".*/\1/p' "$INSTALLER" | head -1)
HELMV=$(sed -n 's/^HELMV="\([^"]*\)".*/\1/p' "$INSTALLER" | head -1)
# docker-ce branch: the DOCKERV after the "# Use docker-ce" marker (non-20.* default)
DOCKERV=$(sed -n '/# Use docker-ce/,/DOCKERV=/s/^ *DOCKERV="\([^"]*\)".*/\1/p' "$INSTALLER" | head -1)
echo "from $INSTALLER: KUBEV=$KUBEV HELMV=$HELMV DOCKERV(docker-ce)=$DOCKERV" | tee "$EVIDENCE_DIR/package-prefixes.txt"

IDX=$WORK/idx; mkdir -p "$IDX"
fetch_index() { curl -fsSL -m 60 --retry 2 -o "$1" "$2"; }
check index_k8s fetch_index "$IDX/k8s" "https://pkgs.k8s.io/core:/stable:/v${KUBEV:-1.33}/deb/Packages"
check index_docker fetch_index "$IDX/docker" "https://download.docker.com/linux/ubuntu/dists/noble/stable/binary-amd64/Packages"
# Same repo line as install_k8s_and_helm.sh: .../helm-debian/any/ any main
check index_helm fetch_index "$IDX/helm" "https://packages.buildkite.com/helm-linux/helm-debian/any/dists/any/main/binary-amd64/Packages"

# pkg_versions <index> <package> <version-prefix>: list matching versions, fail if none.
# Matches after an optional epoch ("5:29.5.0-..."), requiring a dot after the prefix;
# an empty prefix accepts any version.
pkg_versions() {
    python3 -I - "$@" <<'PY'
import re, sys
index, pkg, prefix = sys.argv[1:4]
found, cur = [], {}
for line in open(index, encoding="utf-8", errors="replace").read().split("\n") + [""]:
    if not line.strip():
        if cur.get("Package") == pkg and cur.get("Architecture") in ("amd64", "all") and (not prefix or re.match(r"^(\d+:)?" + re.escape(prefix) + r"(\.|$)", cur.get("Version", ""))):
            found.append(cur["Version"])
        cur = {}
    elif ":" in line and not line.startswith(" "):
        k, v = line.split(":", 1); cur[k] = v.strip()
found = sorted(set(found))
print(f"{pkg} prefix {prefix}: {len(found)} match(es)")
for v in found: print(v)
sys.exit(0 if found else 1)
PY
}
pkgcheck() { # <name> <index> <pkg> <prefix>
    local name="$1"; shift
    check "$name" pkg_versions "$@"
    { echo "== $name"; cat "$EVIDENCE_DIR/checks/${name}.out"; } >>"$EVIDENCE_DIR/package-versions.txt"
}
: >"$EVIDENCE_DIR/package-versions.txt"
pkgcheck pkg_kubeadm "$IDX/k8s" kubeadm "$KUBEV"
pkgcheck pkg_kubelet "$IDX/k8s" kubelet "$KUBEV"
pkgcheck pkg_kubectl "$IDX/k8s" kubectl "$KUBEV"
pkgcheck pkg_docker_ce "$IDX/docker" docker-ce "$DOCKERV"
# containerd.io: no version pinned by NIST (docker-ce depends on it); any noble build counts.
pkgcheck pkg_containerd_io "$IDX/docker" containerd.io ""
pkgcheck pkg_helm "$IDX/helm" helm "$HELMV"

################################################################################
# 6. git apply --check dry runs (clones are scratch; nothing is applied)
################################################################################
check ricdep_clone clone_pinned "$RICDEP_URL" "$RICDEP_SHA" "$WORK/ric-dep"
check kpimon_clone clone_pinned "$KPIMON_URL" "$KPIMON_SHA" "$WORK/kpimon-go"

# apply_check <repo> <subdir> <patch>: same cwd and flags as the NIST scripts, plus --check.
apply_check() {
    local repo="$1" sub="$2" patch="$3"
    [ -f "$patch" ] || { echo "patch file missing: $patch"; return 1; }
    cd "$repo/$sub" || return 1
    git apply --check --verbose --ignore-whitespace "$patch"
}

# Mirror apply_patches.sh L69: getConfigmap.go is converted CRLF -> LF (dos2unix) before patching.
sed -i 's/\r$//' "$WORK/ric-dep/depRicKubernetesOperator/internal/controller/getConfigmap.go" 2>/dev/null

P=$NIST_RIC/install_patch_files
D=$WORK/ric-dep
# Each line cites the apply_patches.sh line that applies the same patch.
check apply_ricdep_getConfigmap_go  apply_check "$D" depRicKubernetesOperator/internal/controller "$P/ric-dep/depRicKubernetesOperator/internal/controller/getConfigmap.go.patch"  # apply_patches.sh:73
check apply_ricdep_e2mgr_configmap  apply_check "$D" helm/e2mgr/templates "$P/ric-dep/helm/e2mgr/templates/configmap.yaml.patch"  # apply_patches.sh:78
check apply_ricdep_ni_e2mgr_configmap apply_check "$D" new-installer/helm/charts/nearrtric/e2mgr/templates "$P/ric-dep/new-installer/helm/charts/nearrtric/e2mgr/templates/configmap.yaml.patch"  # apply_patches.sh:83
check apply_ricdep_rtmgr_config     apply_check "$D" helm/rtmgr/templates "$P/ric-dep/helm/rtmgr/templates/config.yaml.patch"  # apply_patches.sh:90
check apply_ricdep_rtmgr_deployment apply_check "$D" helm/rtmgr/templates "$P/ric-dep/helm/rtmgr/templates/deployment.yaml.patch"  # apply_patches.sh:93
check apply_ricdep_ni_rtmgr_config  apply_check "$D" new-installer/helm/charts/nearrtric/rtmgr/templates "$P/ric-dep/new-installer/helm/charts/nearrtric/rtmgr/templates/config.yaml.patch"  # apply_patches.sh:98
check apply_ricdep_ni_rtmgr_deployment apply_check "$D" new-installer/helm/charts/nearrtric/rtmgr/templates "$P/ric-dep/new-installer/helm/charts/nearrtric/rtmgr/templates/deployment.yaml.patch"  # apply_patches.sh:101

# kpimon-go: install_xapp_kpi_monitor.sh git-restores the touched files and (L104-107) deletes the
# four LogicalOR / MatchingCondItem-Choice sources before the patches re-create them.
K=$WORK/kpimon-go
rm -f "$K/e2sm/headers/LogicalOR.h" "$K/e2sm/headers/MatchingCondItem-Choice.h" \
    "$K/e2sm/lib/LogicalOR.c" "$K/e2sm/lib/MatchingCondItem-Choice.c"
KP=$P/xApps/kpimon-go
# Line numbers below refer to install_xapp_kpi_monitor.sh.
check apply_kpimon_wrapper_c            apply_check "$K" . "$KP/e2sm/wrapper.c.patch"  # :98
check apply_kpimon_kpm2_0_asn           apply_check "$K" . "$KP/e2sm/asn1/kpm2_0.asn.patch"  # :108
check apply_kpimon_LogicalOR_h          apply_check "$K" . "$KP/e2sm/headers/LogicalOR.h.patch"  # :109
check apply_kpimon_MatchingCondItemChoice_h apply_check "$K" . "$KP/e2sm/headers/MatchingCondItem-Choice.h.patch"  # :110
check apply_kpimon_MatchingCondItem_h   apply_check "$K" . "$KP/e2sm/headers/MatchingCondItem.h.patch"  # :111
check apply_kpimon_LogicalOR_c          apply_check "$K" . "$KP/e2sm/lib/LogicalOR.c.patch"  # :112
check apply_kpimon_MatchingCondItemChoice_c apply_check "$K" . "$KP/e2sm/lib/MatchingCondItem-Choice.c.patch"  # :113
check apply_kpimon_MatchingCondItem_c   apply_check "$K" . "$KP/e2sm/lib/MatchingCondItem.c.patch"  # :114
check apply_kpimon_control_go           apply_check "$K" . "$KP/control/control.go.patch"  # :121

################################################################################
# 7. anonymous fetchability of each pinned fork SHA
################################################################################
fetch_sha() { # <url> <sha>
    local d; d=$(mktemp -d "$WORK/fetch.XXXXXX")
    git -C "$d" init -q && GIT_TERMINAL_PROMPT=0 git -C "$d" fetch -q --depth=1 "$1" "$2" &&
        [ "$(git -C "$d" rev-parse FETCH_HEAD)" = "$2" ] && echo "fetched $2 from $1"
}
check fetch_testbed_sha         fetch_sha "$TESTBED_URL" "$TESTBED_SHA"
check fetch_ns3_sha             fetch_sha "$NS3_URL" "$NS3_SHA"
check fetch_oran_interface_sha  fetch_sha "$ORAN_INTERFACE_URL" "$ORAN_INTERFACE_SHA"
check fetch_e2sim_sha           fetch_sha "$E2SIM_URL" "$E2SIM_SHA"

################################################################################
# 8. cleanup, verdict
################################################################################
cd / && rm -rf "$WORK"
gate_finish
