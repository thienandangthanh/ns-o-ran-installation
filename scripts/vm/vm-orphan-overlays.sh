#!/usr/bin/env bash
# vm-orphan-overlays.sh: list image files in VM_IMAGE_DIR that libvirt no longer tracks (leaked overlays).
#
# A file is tracked when it is named by the domain (live and --inactive XML), by any snapshot's XML (its own
# overlay list and the frozen domain definition it carries), or sits on the backing chain of a tracked file, as
# libvirt's storage pool reports it (`vol-dumpxml`, which reads images the host user cannot open). Every other
# regular file in VM_IMAGE_DIR is untracked: printed one per line with its allocated size, exit 1. Exit 0 and no
# output when there is none. Read-only for images and snapshots; it refreshes the pool's volume list first so a
# file created by the last revert is visible to vol-dumpxml.
#
#   vm-orphan-overlays.sh [--evidence DIR]   # DIR gets tracked.txt, untracked.txt and the snapshot tree
source "$(dirname "$0")/vm-common.sh"

evidence=""
[ "${1:-}" = --evidence ] && { evidence="$2"; mkdir -p "$evidence"; }
pool="${VM_POOL:-VMs}"

xml_files() { grep -o "file='[^']*'" | sed "s/^file='//; s/'\$//"; }

"${VIRSH[@]}" pool-refresh "$pool" >/dev/null || die "pool-refresh $pool failed"
named=$(
    { "${VIRSH[@]}" dumpxml "$VM_DOMAIN"; "${VIRSH[@]}" dumpxml --inactive "$VM_DOMAIN"
      for s in $("${VIRSH[@]}" snapshot-list "$VM_DOMAIN" --name); do "${VIRSH[@]}" snapshot-dumpxml "$VM_DOMAIN" "$s"; done
    } | xml_files | sort -u
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
