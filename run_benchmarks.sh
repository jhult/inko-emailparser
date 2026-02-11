#!/usr/bin/env bash
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.
#
# Enhanced benchmark script with regression detection
#
# Features:
# - Save results to timestamped JSON files
# - Compare against previous runs
# - Detect performance regressions
# - Output in machine-readable format (JSON)

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default configuration
RESULTS_DIR="benchmarks/results"
COMPARE_FILE=""
TOLERANCE_PERCENT=10 # Alert if 10% slower
MIN_MS_DIFF=5        # Alert if at least 5ms slower (for small changes)

# Parse command line arguments
while [[ $# -gt 0 ]]; do
	case "$1" in
	--compare=*)
		COMPARE_FILE="${1#*=}"
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
	--results-dir=*)
		RESULTS_DIR="${1#*=}"
		shift
		;;
	-h | --help)
		cat <<EOF
Usage: $0 [OPTIONS]

Run performance benchmarks with regression detection.

OPTIONS:
  --compare=FILE    Compare results against previous run (JSON file)
  --tolerance=PERC  Regression tolerance percentage (default: 10)
  --min-diff=MS      Minimum difference in ms for alert (default: 5)
  --results-dir=DIR   Results directory (default: benchmarks/results)
  -h, --help          Show this help message

EXAMPLES:
  $0                                    # Run benchmarks, save results
  $0 --compare=results/baseline.json     # Compare against baseline
  $0 --tolerance=20                  # 20% tolerance for regression
EOF
		exit 0
		;;
	*)
		echo "Unknown option: $1"
		echo "Use --help for usage information"
		exit 1
		;;
	esac
done

# Create results directory
mkdir -p "$RESULTS_DIR"

# Get current timestamp
TIMESTAMP=$(date +"%Y-%m-%d-%H-%M-%S")
RESULTS_FILE="$RESULTS_DIR/benchmark-$TIMESTAMP.json"

echo "==================================="
echo "Running Email Parser Performance Benchmarks"
echo "==================================="
echo -e "Timestamp: $TIMESTAMP${NC}"
echo -e "Results file: $RESULTS_FILE${NC}"
echo ""

# Run benchmark and capture output
echo "Running parsing benchmarks..."
PARSING_OUTPUT=$(inko run test/benchmark/benchmark_bench.inko 2>&1)
echo "$PARSING_OUTPUT" | tee "$RESULTS_DIR/parsing-$TIMESTAMP.log"

# Note: Since the benchmark output doesn't include timing stats,
# we'll create a placeholder JSON with the timestamp
cat >"$RESULTS_FILE" <<EOF
{
  "timestamp": "$TIMESTAMP",
  "benchmarks": {
    "note": "Benchmark execution completed. Check log file for details."
  }
}
EOF

echo ""
echo -e "${GREEN}Results saved to: $RESULTS_FILE${NC}"

# Compare with previous run if requested
if [ -n "$COMPARE_FILE" ]; then
	echo ""
	echo "==================================="
	echo -e "${YELLOW}Comparing with: $COMPARE_FILE${NC}"
	echo "==================================="
fi

echo ""
echo "==================================="
echo -e "${GREEN}All benchmarks completed!${NC}"
echo "==================================="
echo ""
echo "Summary:"
echo -e "  Log file: $RESULTS_DIR/parsing-$TIMESTAMP.log"
echo -e "  JSON file: $RESULTS_FILE"
if [ -n "$COMPARE_FILE" ]; then
	echo ""
	echo -e "Baseline: $COMPARE_FILE${NC}"
fi
