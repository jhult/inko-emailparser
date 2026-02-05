# Implementation Plan: Streaming Multipart Parser (Phase 3)

## Status: REOPENED FOR PLANNING

## Key Insights from Inko Documentation

### 1. Type System Understanding

**Regular `type` vs `type async`**: 
- Use **regular `type`** for heap-allocated objects with mutation
- Use **`type async`** ONLY for concurrent processes (not needed here)
- The parser should be a regular `type` with methods, not an `async` process type

**Type Modifiers:**
- `type` - Heap allocated, supports mutation, trait casting, 8+ fields, 128+ bytes
- `type inline` - Stack allocated, small types, mixed value/heap data
- `type enum` - Algebraic data types with variants
- `type copy` - Immutable value types (Int, Float, Bool, Nil only)

### 2. Memory Management

**References:**
- `ref T` - Read-only borrow, keeps ownership
- `mut T` - Mutable borrow, keeps ownership  
- `uni T` - Unique value, can cross process boundaries

**For Handler Callbacks:**
- Use `ref mut Handler` in method parameters (like `streaming.inko` does)
- This allows reading and calling methods without transferring ownership

### 3. Callback-Based Streaming

**Pattern from `streaming.inko`:**
- Define trait with callback methods
- Pass `ref mut Handler` to methods that call callbacks
- Handler methods return `Result[Nil, String]` for error handling
- Methods receive trait instance as parameter, call methods directly

## Design Requirements

### Parser Type
```inko
type pub MultipartStreamParser {
  let mut @state: MultipartState
  let @boundary: String
  let mut @buffer: ByteArray
  # ... other fields
}

impl MultipartStreamParser {
  fn pub static new(...) -> MultipartStreamParser { ... }
  
  fn pub mut feed(...) -> Result[Nil, String] { ... }
  
  fn pub mut finish(...) -> Result[Nil, String] { ... }
}
```

### Handler Trait
```inko
trait pub MultipartStreamHandler {
  fn pub on_part_begin(...) -> Result[Nil, String]
  fn pub on_part_data(...) -> Result[Nil, String]
  fn pub on_part_end -> Result[Nil, String]
}
```

### Key Syntax Patterns

1. **Enum Matching**: Use `match` with enum variants, NOT `Type.Variant`
2. **Nil Value**: Use `Option.None`, not `Nil` as a value
3. **String Methods**: Use `.to_lower()` not `.to_lower_case()`
4. **Byte Access**: Use `.get()` not `.byte_at()` for safe access
5. **Loops**: No `continue` - use `loop` with `break` or conditional logic
6. **Assignment**: `x = x + 1` not `x += 1`

## Implementation Strategy

### Phase 1: Core Types
1. Create `MultipartState` enum
2. Create `CurrentPartContext` type
3. Create `MultipartStreamHandler` trait
4. Create `MultipartStreamParser` type

### Phase 2: Parser State Machine
1. Implement buffer management
2. Implement boundary detection
3. Implement state transitions:
   - Preamble -> AtBoundary
   - AtBoundary -> ReadingHeaders
   - ReadingHeaders -> ReadingBody
   - ReadingBody -> AtBoundary
   - AtBoundary -> End or next part

### Phase 3: Helper Functions
1. Header parsing without `continue`
2. Boundary extraction with proper String methods
3. Filename extraction
4. Validation functions

### Phase 4: Tests
1. Create `TestHandler` implementing trait
2. Test simple parts
3. Test multiple parts
4. Test chunked data
5. Test error cases

## Critical Inko Gotchas to Avoid

1. **NO `type async`** - This creates concurrent processes, not streaming parsers
2. **NO `!! Error` in trait** - Not valid syntax in this Inko version
3. **NO `+=` operators** - Use `x = x + 1`
4. **NO `continue`** - Restructure loops to avoid it
5. **NO `.byte_at()`** - Use `.get()` with match
6. **NO `Type.Variant` matching** - Use pattern matching correctly
7. **NO field assignment on immutable** - Mark fields with `mut`

## Next Steps

1. **Review existing `streaming.inko`** as template
2. **Implement minimal working version** with just basic parsing
3. **Add complexity incrementally** after basic tests pass
4. **Test thoroughly** before moving to phase 4

## Reference Files

- `/Users/jonathan/development/inko-emailparser/src/emailparser/streaming.inko` - Existing streaming API
- `/Users/jonathan/development/inko-syntax-guide/02-types-memory.md` - Type system
- `/Users/jonathan/development/inko-syntax-guide/06-concurrency.md` - Concurrency model
- `/Users/jonathan/development/inko-syntax-guide/12-gotchas.md` - Common mistakes
