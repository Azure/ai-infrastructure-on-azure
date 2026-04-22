#!/usr/bin/env bash
#
# fetch-references.sh — refresh inferencex_* fields in every test config.
#
# Queries the InferenceX public API for the given publication date and updates
# each tests/**/conc-*.yaml with the matching reference row (tput_per_gpu,
# output_tput_per_gpu, median_tpot_ms, median_ttft_ms).
#
# The recipe-to-API-row match is by (hardware, framework, precision, isl, osl,
# spec_method, concurrency, total_gpus, decode_tp). Those eight keys uniquely
# identify a row within one publication.
#
# Usage:
#   ./fetch-references.sh                         # pin: 2026-02-03
#   ./fetch-references.sh 2026-03-15              # pin: different date
#   ./fetch-references.sh --dry-run               # preview without writing

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TESTS_DIR="${SCRIPT_DIR}"
MODEL="DeepSeek-R1-0528"
DEFAULT_DATE="2026-02-03"

DATE="$DEFAULT_DATE"
DRY_RUN=false
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    -h|--help)
      sed -n '2,15p' "$0"; exit 0 ;;
    [0-9]*-[0-9]*-[0-9]*) DATE="$arg" ;;
    *) echo "Unknown arg: $arg" >&2; exit 2 ;;
  esac
done

URL="https://inferencex.semianalysis.com/api/v1/benchmarks?model=${MODEL}&date=${DATE}&exact=true"
echo "Fetching: $URL"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
curl -fsS --compressed "$URL" -o "$TMP/api.json"

rows=$(python3 -c "import json;print(len(json.load(open('$TMP/api.json'))))")
echo "  got $rows rows"

FETCHED=$(date -u +%Y-%m-%d)
CONFIGS=$(find "$TESTS_DIR" -mindepth 2 -name 'conc-*.yaml' | sort)
updated=0
skipped=0
failed=0

for cfg in $CONFIGS; do
  conc=$(awk -F': *' '/^concurrency:/ {print $2; exit}' "$cfg")
  total_gpus=$(awk -F': *' '/^total_gpus:/ {print $2; exit}' "$cfg")
  isl=$(awk -F': *' '/^isl:/ {print $2; exit}' "$cfg")
  osl=$(awk -F': *' '/^osl:/ {print $2; exit}' "$cfg")
  sku=$(awk -F': *' '/^sku:/ {print $2; exit}' "$cfg")
  prec=$(awk -F': *' '/^precision:/ {print $2; exit}' "$cfg")
  spec=$(awk -F': *' '/^spec_method:/ {print $2; exit}' "$cfg")
  decode_gpus=$(awk -F': *' '/^decode_gpus_each:/ {print $2; exit}' "$cfg")

  result=$(python3 <<PY
import json, sys
rows = json.load(open("$TMP/api.json"))
match = [r for r in rows
  if r["hardware"]=="$sku"
  and r["framework"]=="dynamo-trt"
  and r["precision"]=="$prec"
  and r["isl"]==$isl and r["osl"]==$osl
  and r["spec_method"]=="$spec"
  and r["conc"]==$conc
  and (r["num_prefill_gpu"]+r["num_decode_gpu"])==$total_gpus
  and r["decode_tp"]==$decode_gpus]
if len(match) != 1:
    print("NOMATCH", len(match))
    sys.exit(0)
m = match[0]["metrics"]
print(f'{match[0]["date"]}|{m["tput_per_gpu"]:.2f}|{m["output_tput_per_gpu"]:.2f}|{m["median_tpot"]*1000:.2f}|{m["median_ttft"]*1000:.1f}')
PY
  )

  if [[ "$result" == NOMATCH* ]]; then
    echo "  SKIP  $cfg  (conc=$conc gpus=$total_gpus: $result)"
    skipped=$((skipped+1))
    continue
  fi

  IFS='|' read -r ix_date tput otput tpot ttft <<< "$result"

  if $DRY_RUN; then
    echo "  DRY   $cfg  tput=${tput} tpot=${tpot}ms ttft=${ttft}ms (ix_date=${ix_date})"
    continue
  fi

  if python3 - "$cfg" "$ix_date" "$FETCHED" "$tput" "$otput" "$tpot" "$ttft" <<'PY'
import sys, re, pathlib
path, ix_date, fetched, tput, otput, tpot, ttft = sys.argv[1:]
p = pathlib.Path(path)
text = p.read_text()
updates = {
    "inferencex_date": ix_date,
    "inferencex_fetched": fetched,
    "inferencex_tput_per_gpu": tput,
    "inferencex_output_tput_per_gpu": otput,
    "inferencex_median_tpot_ms": tpot,
    "inferencex_median_ttft_ms": ttft,
}
for key, val in updates.items():
    pattern = re.compile(rf'^{key}:.*$', re.MULTILINE)
    if not pattern.search(text):
        print(f"WARN {path}: key '{key}' not found, skipping", file=sys.stderr)
        continue
    text = pattern.sub(f"{key}: {val}", text)
p.write_text(text)
PY
  then
    echo "  OK    $cfg  tput=${tput} tpot=${tpot}ms ttft=${ttft}ms"
    updated=$((updated+1))
  else
    echo "  FAIL  $cfg"
    failed=$((failed+1))
  fi
done

echo
echo "Done. updated=${updated} skipped=${skipped} failed=${failed}"
[[ $failed -eq 0 ]]
