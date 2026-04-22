#!/usr/bin/env bash
# Driver for full 8-recipe InferenceX suite on a fresh cluster.
#
# Topology groups (each group shares one helm values file):
#   ctx1-gen4         : conc-5, conc-12, conc-24
#   ctx1-gen3         : conc-33
#   ctx4-gen1-dep32   : conc-180
#   ctx8-gen1-dep32   : conc-308
#   ctx10-gen1-dep16  : conc-666
#   ctx10-gen1-dep8   : conc-2253
#
# Inside a group, recipes share the deployment via -s (skip-deploy). The last
# recipe of each group passes -t to teardown the whole chart (workloads + infra)
# so the next group starts with a fresh frontend/etcd/NATS — required to avoid
# stale Dynamo router state that inflates prefill TTFT (see README §3.1).
set -u
cd "$(dirname "$0")"
LOG_DIR=suite-logs-$(date -u +%Y%m%dT%H%M%SZ)
mkdir -p "$LOG_DIR"
SUMMARY="$LOG_DIR/summary.tsv"
printf 'recipe\tstatus\texit\tstart_utc\tend_utc\tlog\n' > "$SUMMARY"

# test-config :: run-test.sh-flags
# - first recipe of each topology group has no -s (fresh deploy)
# - last recipe of each topology group has -t (full teardown for next group)
TESTS=(
  "tests/trtllm/gb300-fp4/8k1k/mtp/conc-5.yaml|"
  "tests/trtllm/gb300-fp4/8k1k/mtp/conc-12.yaml|-s"
  "tests/trtllm/gb300-fp4/8k1k/mtp/conc-24.yaml|-s -t"
  "tests/trtllm/gb300-fp4/8k1k/mtp/conc-33.yaml|-t"
  "tests/trtllm/gb300-fp4/8k1k/mtp/conc-180.yaml|-t"
  "tests/trtllm/gb300-fp4/8k1k/mtp/conc-308.yaml|-t"
  "tests/trtllm/gb300-fp4/8k1k/mtp/conc-666.yaml|-t"
  "tests/trtllm/gb300-fp4/8k1k/mtp/conc-2253.yaml|-t"
)

for entry in "${TESTS[@]}"; do
  cfg="${entry%%|*}"
  flags="${entry##*|}"
  name=$(basename "$cfg" .yaml)
  log="$LOG_DIR/$name.log"
  start=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  echo "=== $(date -u +%H:%M:%S) START $name flags=[$flags] -> $log ==="
  if [ -n "$flags" ]; then
    ./run-test.sh "$cfg" $flags > "$log" 2>&1
  else
    ./run-test.sh "$cfg" > "$log" 2>&1
  fi
  rc=$?
  end=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  verdict=$(grep -oE '(PASS|FAIL|GAP)' "$log" | tail -1 || echo '?')
  printf '%s\t%s\t%d\t%s\t%s\t%s\n' "$name" "${verdict:-?}" "$rc" "$start" "$end" "$log" >> "$SUMMARY"
  echo "=== $(date -u +%H:%M:%S) END   $name rc=$rc verdict=${verdict:-?} ==="
  if [ $rc -ne 0 ]; then
    echo "!!! $name exited non-zero (rc=$rc); continuing with next recipe"
  fi
done

echo
echo "===== SUITE SUMMARY ====="
column -t -s $'\t' "$SUMMARY"
