#!/bin/bash
# run-all.sh — run the L-release E2 milestone harness M1..M5 in order.
# M4/M5 exit 2 (NOT RUN) until a KPM xApp subscriber is available (Q4).
# Run ON oran-kvm-2.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

declare -A RES
for m in m1-sctp m2-e2setup m3-ranfunction m4-subscription m5-dummy-kpm; do
  echo "================ $m ================"
  bash "$HERE/$m.sh"
  rc=$?
  case $rc in
    0) RES[$m]="GREEN" ;;
    2) RES[$m]="NOT-RUN (subscriber needed)" ;;
    *) RES[$m]="FAIL" ;;
  esac
done

echo ""
echo "================ SUMMARY ================"
for m in m1-sctp m2-e2setup m3-ranfunction m4-subscription m5-dummy-kpm; do
  printf "  %-16s %s\n" "$m" "${RES[$m]}"
done
