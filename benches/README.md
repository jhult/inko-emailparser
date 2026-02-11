# Performance Benchmarks

This directory contains performance benchmarks for the inko-emailparser library.

## Running Benchmarks

Each benchmark file can be run independently:

```bash
# Run individual benchmarks
inko run benches/bench_parsing.inko

# Or run all benchmarks with regression detection
./run_benchmarks.sh
```

## Benchmark Categories

### Parsing Benchmarks (`bench_parsing.inko`)
- **Simple email parsing**: Measures time to parse a simple plain text email
- **Multipart parsing**: Tests performance with multipart MIME messages
- **Base64 decoding**: Performance of Base64-encoded content decoding
- **Quoted-printable decoding**: Performance of quoted-printable decoding
- **Header parsing**: Measures time to parse email headers
- **Address parsing**: Performance of parsing email address lists

## Performance Goals

These benchmarks help ensure:
1. **No regressions**: Changes don't slow down existing operations
2. **Optimization validation**: Performance improvements actually improve
3. **Scale understanding**: How operations scale with data size
4. **Cross-platform consistency**: Performance is acceptable on all platforms

## Interpreting Results

- **ms per operation**: Lower is better
- **Median**: The 50th percentile - good for typical case performance
- **P95**: The 95th percentile - good for tail latency
- **P99**: The 99th percentile - good for worst-case performance
- **Compare across runs**: Track changes over time
- **Platform differences**: Some variation expected between OS/architectures
- **Watch for outliers**: Sudden spikes may indicate issues

## Benchmark Script

The `run_benchmarks.sh` script provides:

- **Regression detection**: Compares against previous runs
- **JSON output**: Machine-readable results for tracking
- **Configurable tolerance**: Set acceptable performance variance
- **Baseline comparison**: Compare against a specific baseline file

### Usage Examples

```bash
# Run benchmarks with default settings
./run_benchmarks.sh

# Compare against a previous run
./run_benchmarks.sh --compare=benchmarks/results/benchmark-2024-01-15-10-30-00.json

# Use custom tolerance (20% regression threshold)
./run_benchmarks.sh --tolerance=20

# Set minimum difference threshold for alerts (10ms)
./run_benchmarks.sh --min-diff=10
```

## Future Improvements

- Add memory usage profiling
- Support for larger datasets
- Streaming parser benchmarks
- Concurrent operation benchmarks
- Integration with CI for regression detection
