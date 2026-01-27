#!/usr/bin/env bash
# Email Parser Benchmark Script
# Runs performance benchmarks and saves results with timestamp

set -o errexit
set -o nounset
set -o pipefail

if [[ "${TRACE-0}" == "1" ]]; then
  set -o xtrace
fi

# Constants
_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR="$_script_dir"

_project_dir="$(dirname "$SCRIPT_DIR")"
readonly PROJECT_DIR="$_project_dir"

readonly BENCHMARK_DIR="$PROJECT_DIR/test/benchmark"
readonly RESULTS_DIR="$PROJECT_DIR/benchmark-results"
unset _script_dir _project_dir

# Help function
show_help() {
  cat <<'EOF'
Usage: ./benchmark.sh [options]

Run the email parser benchmark suite and save results with timestamp.

Options:
    -h, --help              Show this help message and exit
    -v, --verbose           Enable verbose output (same as TRACE=1)

Environment Variables:
    TRACE                   Set to '1' to enable debug tracing

Examples:
    ./benchmark.sh                  # Run benchmarks
    ./benchmark.sh --help           # Show help
    TRACE=1 ./benchmark.sh          # Run with debug tracing

Output:
    Results are saved to: benchmark-results/benchmark_YYYYMMDD_HHMMSS.txt
    A symlink is created at: benchmark-results/latest.txt

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
  *)
    echo "Error: Unknown option: $1" >&2
    echo "Run './benchmark.sh --help' for usage information." >&2
    exit 1
    ;;
  esac
done

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

# Main function
main() {
  # Validate directories exist
  if [[ ! -d "$BENCHMARK_DIR" ]]; then
    echo "Error: Benchmark directory not found: $BENCHMARK_DIR" >&2
    exit 1
  fi

  # Create results directory if it doesn't exist
  if [[ ! -d "$RESULTS_DIR" ]]; then
    mkdir -p "$RESULTS_DIR"
  fi

  # Generate timestamp for results file
  local timestamp
  timestamp=$(date +"%Y%m%d_%H%M%S")
  local results_file="$RESULTS_DIR/benchmark_${timestamp}.txt"
  local summary_file="$RESULTS_DIR/latest.txt"

  # Print header
  print_header "Email Parser Benchmark Suite"
  print_section "Running benchmarks..."
  echo "Timestamp: $(date)"
  echo ""

  # Run the benchmark and capture output
  cd "$BENCHMARK_DIR"
  inko run benchmark_bench.inko 2>&1 | tee "$results_file"

  # Create a symlink to the latest results
  ln -sf "$(basename "$results_file")" "$summary_file"

  # Print completion message
  print_header "Benchmark complete!"
  print_section "Results saved:"
  echo "  File: $results_file"
  echo "  Latest: $summary_file"
  print_section "To compare results:"
  echo "  diff $summary_file $RESULTS_DIR/benchmark_PREVIOUS_TIMESTAMP.txt"
  echo ""
}

main "$@"
