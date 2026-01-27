# Email Parser Benchmark Suite

This directory contains performance benchmarks for the email parser.

## Running Benchmarks

### Recommended: Using the Benchmark Script

The easiest way to run benchmarks:

```bash
./scripts/benchmark.sh
```

This script:
- Runs the full benchmark suite
- Saves results with timestamp to `benchmark-results/`
- Creates a symlink to the latest results
- Provides a summary when complete

### Manual Execution

You can also run benchmarks directly:

```bash
cd test/benchmark
inko run benchmark_bench.inko
```

Or compile for release mode (faster execution):

```bash
cd test/benchmark
inko build --release benchmark_bench.inko
build/release/benchmark_bench
```

## Benchmark Categories

### Header Parsing Benchmarks
Tests the performance of parsing email headers:
- **Simple Headers**: Basic header parsing (10000 iterations)
- **Complex Headers**: Parsing emails with many header fields (5000 iterations)
- **Encoded Headers (RFC 2047)**: Decoding non-ASCII encoded headers (5000 iterations)

### Body Decoding Benchmarks
Tests the performance of decoding email body content:
- **Base64 Small**: Small Base64 encoded content (10000 iterations)
- **Base64 Large**: Large Base64 encoded content (1000 iterations)
- **Quoted-Printable Simple**: Basic quoted-printable decoding (10000 iterations)
- **Quoted-Printable UTF-8**: Decoding UTF-8 characters (5000 iterations)
- **7bit/8bit Decode**: Pass-through decoding (10000 iterations)

### Multipart Parsing Benchmarks
Tests the performance of parsing multipart MIME messages:
- **Multipart Alternative**: Simple text + HTML alternatives (1000 iterations)
- **Multipart Nested**: Nested multipart structures (1000 iterations)
- **Real Nested Multipart**: Real-world nested multipart emails (500 iterations)

### Large Email Handling Benchmarks
Tests the performance of parsing large and complex emails:
- **Many Headers**: Emails with many header fields (1000 iterations)
- **Large Body**: Emails with large body content (500 iterations)
- **Real Complex Email**: Complex real-world emails (500 iterations)
- **Apple Mail Format**: Apple Mail specific format (500 iterations)
- **Outlook Format**: Outlook specific format (500 iterations)

## Understanding Results

Each benchmark reports:
- **Iterations**: Number of times the operation was run
- **Status**: "Complete" or "Skipped" if fixture not found

The benchmark suite uses `Instant.new` before the loop and `.elapsed` after the loop to measure timing.

Note: Due to Inko type system limitations, exact timing values are not displayed. The benchmarks provide relative performance comparisons rather than absolute metrics.

## Performance Targets

The benchmarks help identify:
1. Hot spots in the parsing code
2. Performance regressions over time
3. Impact of optimizations
4. Scalability with large inputs

## Fixtures

Benchmarks use test fixtures from `../fixtures/`:
- `gmail-complex.eml` - Complex Gmail email
- `nested-multipart.eml` - Nested multipart structure
- `apple-mail.eml` - Apple Mail format
- `outlook.eml` - Outlook format
- And more...

## Adding New Benchmarks

To add a new benchmark:

1. Create a benchmark loop following the existing pattern:

```inko
out.print('Benchmarking Your Test (N iterations)...')
let parser = EmailParser.new
let test_data = 'your test data here'
let start = Instant.new
let mut i = 0
while i < N {
  let _ = parser.parse(test_data)
  i = i + 1
}
let _ = start.elapsed
out.print('  Complete')
```

2. Run the benchmark suite and verify it works
3. Add documentation to this README

## Notes

- Inko does not have a built-in benchmark framework like Rust's criterion
- The `Instant.elapsed` return type `Duration` which cannot be converted to string for display
- This benchmark suite provides basic timing infrastructure without detailed statistics
- For more advanced benchmarking, consider integrating with external tools
