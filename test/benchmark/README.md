# Email Parser Benchmark Suite

This directory contains performance benchmarks for the email parser.

## Running Benchmarks

### Using the Benchmark Script

```bash
# Run benchmarks, save text results
./test/benchmark/benchmark.sh

# Run benchmarks with JSON output (for CI regression detection)
./test/benchmark/benchmark.sh --json

# Compare against a previous run
./test/benchmark/benchmark.sh --compare=test/benchmark/results/baseline.json

# Custom tolerance (20% regression threshold)
./test/benchmark/benchmark.sh --json --tolerance=20
```

The script:
- Runs the full benchmark suite
- Saves text results with timestamp to `test/benchmark/results/`
- Creates a symlink at `results/latest.txt` for easy access
- With `--json`, saves machine-readable results for CI integration

### Manual Execution

```bash
cd test/benchmark
inko run benchmark_bench.inko
```

## Benchmark Categories

- **Simple email parsing** (1000 iterations)
- **Multipart parsing** (500 iterations)
- **Base64 decoding** (1000 iterations)
- **Quoted-printable decoding** (1000 iterations)
- **Header parsing** (10000 iterations)
- **Address parsing** (5000 iterations)

## Understanding Results

Each benchmark reports elapsed time in milliseconds. Due to Inko's type system, timing values provide relative performance comparisons between code versions rather than absolute metrics.

## Fixtures

Benchmarks use test fixtures from `../fixtures/`:
- `gmail-complex.eml` - Complex Gmail email
- `nested-multipart.eml` - Nested multipart structure
- `apple-mail.eml` - Apple Mail format
- `outlook.eml` - Outlook format

## Adding New Benchmarks

To add a new benchmark, follow the existing pattern in `benchmark_bench.inko`:

```inko
out.print('Benchmark N: Description (iterations)...')
let start = Instant.new
let mut i = 0
while i < ITERATIONS {
  parser.parse(test_data)
  i = i + 1
}
let elapsed = start.elapsed
out.print('  ${elapsed.to_millis} ms')
```

Then update the `parse_ms` labels in `benchmark.sh` if needed for JSON output.