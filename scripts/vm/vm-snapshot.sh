#!/usr/bin/env bash
# Offline, disk-only external snapshots of the gate VM.
#
#   vm-snapshot.sh create <name> [--need-gb N] [--evidence DIR]
#   vm-snapshot.sh revert <name>
#   vm-snapshot.sh delete <name>
#   vm-snapshot.sh list
#   vm-snapshot.sh check-protected <name>   # prints protected|deletable
#
# create: graceful shutdown -> snapshot-create-as --disk-only --atomic -> start
#         -> wait for ssh. Refuses when host /home has < 20 GB + N free.
# revert: graceful shutdown -> snapshot-revert -> start -> wait for ssh.
# delete: refuses fresh-install, f7-rerun-green, r3p-green and (under substitution 4) r2-green before any virsh call.

source "$(dirname "$0")/vm-common.sh"

cmd="${1:-}"; shift $(($# > 0))
name=""; if [ $# -gt 0 ] && [ "${1#--}" = "$1" ]; then name="$1"; shift; fi
need_gb=0; evidence=""
while [ $# -gt 0 ]; do
    case "$1" in
        --need-gb) need_gb="$2"; shift 2 ;;
        --evidence) evidence="$2"; shift 2 ;;
        *) die "unknown arg $1" ;;
    esac
done

# grep without -q: an early grep exit would SIGPIPE virsh and fail under pipefail.
snapshot_exists() { "${VIRSH[@]}" snapshot-list "$VM_DOMAIN" --name | grep -x "$1" >/dev/null; }

case "$cmd" in
create)
    [ -n "$name" ] || die "create needs a name"
    snapshot_exists "$name" && die "snapshot $name already exists"
    free=$(host_free_gb)
    min=$((HOST_MIN_FREE_GB + need_gb))
    [ "$free" -ge "$min" ] || die "host /home has ${free}G free, need >= ${min}G: STOP and ask the user"
    vm_shutdown || die "guest did not shut down within 240 s"
    hlog "creating external disk-only snapshot $name (host free ${free}G)"
    # The cdrom (sda) has no source and is excluded explicitly.
    "${VIRSH[@]}" snapshot-create-as "$VM_DOMAIN" "$name" \
        --description "gate snapshot $name $(date -u +%FT%TZ)" \
        --disk-only --atomic \
        --diskspec "vda,snapshot=external,file=$VM_IMAGE_DIR/ubuntu24.04-$name.qcow2" \
        --diskspec sda,snapshot=no || die "snapshot-create-as failed"
    if [ -n "$evidence" ]; then
        mkdir -p "$evidence"
        "${VIRSH[@]}" snapshot-dumpxml "$VM_DOMAIN" "$name" >"$evidence/snapshot-$name.xml"
        disk_chain >"$evidence/disk-chain-after-$name.txt"
    fi
    vm_start || die "VM did not come back on ssh after snapshot $name"
    hlog "snapshot $name created; VM up"
    ;;
revert)
    [ -n "$name" ] || die "revert needs a name"
    snapshot_exists "$name" || die "no snapshot $name"
    vm_shutdown || die "guest did not shut down within 240 s"
    hlog "reverting to $name"
    "${VIRSH[@]}" snapshot-revert "$VM_DOMAIN" "$name" || die "snapshot-revert $name failed"
    vm_start || die "VM did not come back on ssh after revert to $name"
    hlog "reverted to $name; VM up"
    ;;
delete)
    [ -n "$name" ] || die "delete needs a name"
    is_protected "$name" && die "refusing to delete protected snapshot $name"
    snapshot_exists "$name" || die "no snapshot $name"
    "${VIRSH[@]}" snapshot-delete "$VM_DOMAIN" "$name" || die "libvirt refused to delete $name: STOP and ask the user"
    hlog "deleted snapshot $name"
    ;;
check-protected)
    [ -n "$name" ] || die "check-protected needs a name"
    if is_protected "$name"; then echo protected; else echo deletable; fi
    ;;
list)
    "${VIRSH[@]}" snapshot-list "$VM_DOMAIN" --tree
    disk_chain
    echo "host /home free: $(host_free_gb)G"
    ;;
*)
    sed -n '2,14p' "$0"; exit 2 ;;
esac
