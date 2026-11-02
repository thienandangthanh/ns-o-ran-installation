#!/usr/bin/env bash
# vm-orphan-overlays.sh: list image files in VM_IMAGE_DIR that libvirt no longer tracks (leaked overlays).
#
# A file is tracked when it is named by any defined domain (live and --inactive XML; other VMs keep images in the
# same directory), by any snapshot's XML (its own
# overlay list and the frozen domain definition it carries), or sits on the backing chain of a tracked file, as
# libvirt's storage pool reports it (`vol-dumpxml`, which reads images the host user cannot open). Every other
# regular file in VM_IMAGE_DIR is untracked: printed one per line with its allocated size, exit 1. Exit 0 and no
# output when there is none. Read-only for images and snapshots; it refreshes the pool's volume list first so a
# file created by the last revert is visible to vol-dumpxml.
#
#   vm-orphan-overlays.sh [--evidence DIR]   # DIR gets tracked.txt, untracked.txt and the snapshot tree
#   vm-orphan-overlays.sh --pending          # the leak that has not happened yet: pass only when VM_DOMAIN's active
#                                            # vda is the overlay its current snapshot will unlink at the next revert
#                                            # (the top-level <revertDisks> entry, or <disks> when there is none)
source "$(dirname "$0")/vm-common.sh"

evidence=""
[ "${1:-}" = --evidence ] && { evidence="$2"; mkdir -p "$evidence"; }
pool="${VM_POOL:-VMs}"

if [ "${1:-}" = --pending ]; then
    active=$("${VIRSH[@]}" domblklist "$VM_DOMAIN" | awk '$1 == "vda" { print $2 }')
    cur=$("${VIRSH[@]}" snapshot-current "$VM_DOMAIN" --name 2>/dev/null) || die "no current snapshot"
    recorded=$("${VIRSH[@]}" snapshot-dumpxml "$VM_DOMAIN" "$cur" | python3 -I -c '
import sys, xml.etree.ElementTree as ET
root = ET.fromstring(sys.stdin.read())
for tag in ("revertDisks", "disks"):          # top-level children only: the nested <domain> disks never match
    el = root.find(tag)
    if el is None:
        continue
    for d in el.findall("disk"):
        src = d.find("source")
        if d.get("name") == "vda" and src is not None:
            print(src.get("file")); sys.exit(0)
    if tag == "revertDisks":
        break
')
    echo "current snapshot $cur; active vda $active; unlinked at the next revert: ${recorded:-none}"
    [ -n "$active" ] && [ "$active" = "$recorded" ]
    exit
fi

xml_files() { grep -o "file='[^']*'" | sed "s/^file='//; s/'\$//"; }

"${VIRSH[@]}" pool-refresh "$pool" >/dev/null || die "pool-refresh $pool failed"
named=$(
    for dom in $("${VIRSH[@]}" list --all --name); do
        "${VIRSH[@]}" dumpxml "$dom"; "${VIRSH[@]}" dumpxml --inactive "$dom"
        for s in $("${VIRSH[@]}" snapshot-list "$dom" --name); do "${VIRSH[@]}" snapshot-dumpxml "$dom" "$s"; done
    done | xml_files | sort -u
) || die "reading the domain or snapshot XML failed"

# close over backing chains: a tracked file's backing file is tracked too
declare -A tracked=()
queue=()
for f in $named; do queue+=("$f"); done
while [ "${#queue[@]}" -gt 0 ]; do
    f="${queue[0]}"; queue=("${queue[@]:1}")
    [ -n "${tracked[$f]:-}" ] && continue
    tracked[$f]=1
    [ -e "$f" ] || continue
    b=$("${VIRSH[@]}" vol-dumpxml "$f" 2>/dev/null | sed -n '/<backingStore>/,/<\/backingStore>/s:.*<path>\(.*\)</path>.*:\1:p' | head -n 1)
    [ -n "$b" ] && queue+=("$b")
done

untracked=()
for f in "$VM_IMAGE_DIR"/*; do
    [ -f "$f" ] || continue
    [ -n "${tracked[$f]:-}" ] || untracked+=("$f")
done

if [ -n "$evidence" ]; then
    printf '%s\n' "${!tracked[@]}" | sort >"$evidence/tracked.txt"
    printf '%s\n' "${untracked[@]}" | sed '/^$/d' >"$evidence/untracked.txt"
    "${VIRSH[@]}" snapshot-list "$VM_DOMAIN" --tree >"$evidence/snapshot-tree.txt"
    disk_chain >"$evidence/disk-chain.txt"
fi
for f in "${untracked[@]}"; do printf '%s\t%s\n' "$f" "$(du -h "$f" 2>/dev/null | cut -f1)"; done
[ "${#untracked[@]}" -eq 0 ]
