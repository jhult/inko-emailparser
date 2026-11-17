#!/usr/bin/env bash
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this file,
# You can obtain one at https://mozilla.org/MPL/2.0/.

# Email Parser Benchmark Script
# Runs performance benchmarks and saves results with timestamp.
# Supports JSON output for CI regression detection.

set -o errexit
set -o nounset
set -o pipefail

if [[ "${TRACE-0}" == "1" ]]; then
  set -o xtrace
fi

# Constants
_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR="$_script_dir"
readonly BENCHMARK_DIR="$SCRIPT_DIR"
readonly RESULTS_DIR="$SCRIPT_DIR/results"

# JSON/regression detection defaults
COMPARE_FILE=""
TOLERANCE_PERCENT=10
MIN_MS_DIFF=5
OUTPUT_JSON=false

unset _script_dir

# Help function
show_help() {
  cat <<'EOF'
Usage: ./benchmark.sh [options]

Run the email parser benchmark suite and save results.

Options:
    -h, --help              Show this help message and exit
    -v, --verbose           Enable verbose output (same as TRACE=1)
    --json                  Save results as JSON for CI regression detection
    --compare=FILE          Compare results against previous run (JSON file)
    --tolerance=PERC        Regression tolerance percentage (default: 10)
    --min-diff=MS           Minimum difference in ms for alert (default: 5)

Environment Variables:
    TRACE                   Set to '1' to enable debug tracing

Examples:
    ./benchmark.sh                  # Run benchmarks, save text results
    ./benchmark.sh --json           # Run benchmarks, save JSON results
    ./benchmark.sh --compare=results/baseline.json
    ./benchmark.sh --json --tolerance=20

Output:
    Text results: results/benchmark_YYYYMMDD_HHMMSS.txt
    JSON results: results/benchmark-latest.json
    Symlink:      results/latest.txt
EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
  -h | --help | help)
    show_help
    exit 0
    ;;
  -v | --verbose)
    export TRACE=1
    set -o xtrace
    shift
    ;;
  --json)
    OUTPUT_JSON=true
    shift
    ;;
  --compare=*)
    COMPARE_FILE="${1#*=}"
    OUTPUT_JSON=true
    shift
    ;;
  --tolerance=*)
    TOLERANCE_PERCENT="${1#*=}"
    shift
    ;;
  --min-diff=*)
    MIN_MS_DIFF="${1#*=}"
    shift
    ;;
  *)
    echo "Error: Unknown option: $1" >&2
    echo "Run './benchmark.sh --help' for usage information." >&2
    exit 1
    ;;
  esac
done

# Resolve the comparison path before main() changes into the benchmark
# directory, so paths are relative to the caller's working directory.
if [[ -n "$COMPARE_FILE" && "$COMPARE_FILE" != /* ]]; then
  COMPARE_FILE="$PWD/$COMPARE_FILE"
fi

# Print header function
print_header() {
  local text="$1"
  echo ""
  echo "==================================================================="
  echo "$text"
  echo "==================================================================="

}

# Print section function
print_section() {
  local text="$1"
  echo ""
  echo "$text"
}

# Parse ms value from benchmark output
# Extracts the numeric value from lines like "  425 ms"
parse_ms() {
  local label="$1"
  local output="$2"

  { echo "$output" | grep -A1 "$label" | grep -oE '[0-9]+ ms' | head -1 |
    grep -oE '[0-9]+' || true; }
}

# Read one benchmark value from a JSON results file
json_value() {
  local name="$1"
  local file="$2"

  { grep -oE "\"name\": \"${name}\", \"unit\": \"[a-z]+\", \"value\": [0-9]+" \
      "$file" | grep -oE '[0-9]+$' | head -1 || true; }
}

# Compare one measurement against the baseline
#
# Returns non-zero when the measurement regressed beyond the tolerance and the
# absolute difference is above the noise floor.
check_regression() {
  local name="$1"
  local current="$2"
  local baseline="$3"

  if [[ -z "$baseline" ]]; then
    echo "  $name: no baseline value, skipping"
    return 0
  fi

  local diff=$((current - baseline))

  if ((diff < 0)); then
    diff=$((0 - diff))
  fi

  local tolerance=$((baseline * TOLERANCE_PERCENT / 100))

  if ((diff < MIN_MS_DIFF)); then
    echo "  $name: ${current} ms vs ${baseline} ms (within ${MIN_MS_DIFF} ms noise floor)"
    return 0
  fi

  if ((current > baseline + tolerance)); then
    echo "  $name: REGRESSION ${current} ms vs ${baseline} ms (+${diff} ms)"
    return 1
  fi

  echo "  $name: ${current} ms vs ${baseline} ms (within ${TOLERANCE_PERCENT}%)"
  return 0
}

# Main function
main() {
  if [[ ! -d "$BENCHMARK_DIR" ]]; then
    echo "Error: Benchmark directory not found: $BENCHMARK_DIR" >&2
    exit 1
  fi

  mkdir -p "$RESULTS_DIR"

  local timestamp
  timestamp=$(date +"%Y%m%d_%H%M%S")
  local text_results_file="$RESULTS_DIR/benchmark_${timestamp}.txt"
  local json_results_file="$RESULTS_DIR/benchmark-latest.json"

  print_header "Email Parser Benchmark Suite"
  print_section "Running benchmarks..."
  echo "Timestamp: $(date)"
  echo ""

  # Run the benchmark and capture output
  cd "$BENCHMARK_DIR"
  local parsing_output
  parsing_output=$(inko run benchmark_bench.inko 2>&1)

  # Always show output and save text results
  echo "$parsing_output" | tee "$text_results_file"

  # Create symlink to latest text results
  ln -sf "$(basename "$text_results_file")" "$RESULTS_DIR/latest.txt"

  # Generate JSON if requested
  if [[ "$OUTPUT_JSON" == "true" ]]; then
    local simple_ms multipart_ms base64_ms qp_ms header_ms address_ms

    simple_ms=$(parse_ms "Benchmark 1:" "$parsing_output")
    multipart_ms=$(parse_ms "Benchmark 2:" "$parsing_output")
    base64_ms=$(parse_ms "Benchmark 3:" "$parsing_output")
    qp_ms=$(parse_ms "Benchmark 4:" "$parsing_output")
    header_ms=$(parse_ms "Benchmark 5:" "$parsing_output")
    address_ms=$(parse_ms "Benchmark 6:" "$parsing_output")

    # A missing measurement must never be recorded as 0: a smaller-is-better
    # chart would show a crash as a large improvement.
    if [[ -z "$simple_ms" || -z "$multipart_ms" || -z "$base64_ms" ||
      -z "$qp_ms" || -z "$header_ms" || -z "$address_ms" ]]; then
      echo "Error: failed to parse all benchmark timings from the output" >&2
      exit 1
    fi

    cat >"$json_results_file" <<EOF
[
  {"name": "simple_email_1000", "unit": "ms", "value": ${simple_ms}},
  {"name": "multipart_500", "unit": "ms", "value": ${multipart_ms}},
  {"name": "base64_1000", "unit": "ms", "value": ${base64_ms}},
  {"name": "quoted_printable_1000", "unit": "ms", "value": ${qp_ms}},
  {"name": "header_parsing_10000", "unit": "ms", "value": ${header_ms}},
  {"name": "address_parsing_5000", "unit": "ms", "value": ${address_ms}}
]
EOF

    print_section "JSON results saved to: $json_results_file"
  fi

  # Compare with previous run if requested
  if [[ -n "$COMPARE_FILE" ]]; then
    print_header "Comparing with: $COMPARE_FILE"

    if [[ ! -f "$COMPARE_FILE" ]]; then
      echo "Error: comparison file not found: $COMPARE_FILE" >&2
      exit 1
    fi

    local regressed=0

    check_regression simple_email_1000 "$simple_ms" \
      "$(json_value simple_email_1000 "$COMPARE_FILE")" || regressed=1
    check_regression multipart_500 "$multipart_ms" \
      "$(json_value multipart_500 "$COMPARE_FILE")" || regressed=1
    check_regression base64_1000 "$base64_ms" \
      "$(json_value base64_1000 "$COMPARE_FILE")" || regressed=1
    check_regression quoted_printable_1000 "$qp_ms" \
      "$(json_value quoted_printable_1000 "$COMPARE_FILE")" || regressed=1
    check_regression header_parsing_10000 "$header_ms" \
      "$(json_value header_parsing_10000 "$COMPARE_FILE")" || regressed=1
    check_regression address_parsing_5000 "$address_ms" \
      "$(json_value address_parsing_5000 "$COMPARE_FILE")" || regressed=1

    if ((regressed)); then
      echo "" >&2
      echo "Performance regression detected" >&2
      exit 1
    fi
  fi

  print_header "Benchmark complete!"
  print_section "Results saved:"
  echo "  Text: $text_results_file"
  echo "  Latest: $RESULTS_DIR/latest.txt"
  if [[ "$OUTPUT_JSON" == "true" ]]; then
    echo "  JSON: $json_results_file"
  fi
  if [[ -n "$COMPARE_FILE" ]]; then
    echo "  Baseline: $COMPARE_FILE"
  fi
  echo ""
}

main "$@"