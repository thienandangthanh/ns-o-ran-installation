#!/usr/bin/env bash
# Runs the checkpoint 2 VM gate chain at one harness SHA, in order, and stops at the first red step.
# usage: p08-gate-chain.sh HARNESS_SHA [FIRST_STEP_INDEX]
# Each line of $log: <utc> <index> <step> <args> <exit code>.
set -u
repo=/home/andang/orca/workspaces/ns-o-ran-installation/migrate-l-release-NIST-1-8-0
sha=$1; first=${2:-0}
here=/tmp/claude-1000/-home-andang-orca-workspaces-ns-o-ran-installation-migrate-l-release-NIST-1-8-0/f0b59251-b401-4457-9af9-e65d8dcc0ecc/scratchpad
log=$here/p08-gate-chain.tsv
export EVIDENCE_HOST_ROOT=$repo/plans/261103-0008-GH-1-post-m9-realism-m10/evidence
ref=plans/261103-0008-GH-1-post-m9-realism-m10/reference
m9ref=plans/261023-0009-GH-1-m8-m9-paced-rungs-and-m9/reference/r3p/equal
cd "$repo" || exit 2
[ "$(git rev-parse HEAD)" = "$sha" ] || { echo "HEAD is not $sha"; exit 2; }
steps=(
  "gate-m2-refnode.sh|3600|"
  "gate-m3-xapps.sh|3600|"
  "gate-m4-ns3-build.sh|7200|"
  "gate-m5-agent-setup.sh|3600|"
  "gate-m6-kpm.sh|3600|"
  "gate-m7-multignb.sh|3600|"
  "gate-i0-rc-install.sh|3600|"
  "gate-q8-rc-smoke.sh|3600|"
  "gate-r0-rc-scripted.sh|5400|--mode single"
  "gate-r1-rc-multi-control.sh|5400|--mode single"
  "gate-i2-ts-xapp-install.sh|3600|"
  "gate-r2-ts-stub-qp.sh|10800|--mode c1"
  "gate-r3p-ts-predictor.sh|5400|--mode calibrate"
  "gate-r3p-ts-predictor.sh|5400|--mode dryrun --stage b --stage-a-class scripts/gates/r3p-stage-a.json"
  "gate-r3p-ts-predictor.sh|10800|--mode c1 --reference-transform $ref/m9-r3p-raw $m9ref"
  "gate-r3p-ts-predictor.sh|10800|--mode c1 --delta-ms 150 --reference-transform $ref/r3p-d150/raw $ref/r3p-d150/equal"
  "gate-r3p-ts-predictor.sh|10800|--mode c1 --delta-ms 500 --reference-transform $ref/r3p-d500/raw $ref/r3p-d500/equal"
  "gate-e2i-interop.sh|5400|--image-tag 09aeabb8b0f99b0c"
  "probes/probe-delta-seam-smoke.sh|7200|"
  "gate-r1-rc-multi-control.sh|10800|--mode c1"
)
for i in "${!steps[@]}"; do
  [ "$i" -lt "$first" ] && continue
  IFS='|' read -r g t a <<<"${steps[$i]}"
  # shellcheck disable=SC2086
  bash scripts/vm/vm-exec.sh "$g" --harness-sha "$sha" --timeout "$t" -- $a >"$here/p08-step-$i.log" 2>&1
  rc=$?
  printf '%s\t%s\t%s %s\t%s\n' "$(date -u +%FT%TZ)" "$i" "$g" "$a" "$rc" >>"$log"
  [ "$rc" -eq 0 ] || { echo "step $i ($g $a) exit $rc"; exit "$rc"; }
done
echo "chain green"
