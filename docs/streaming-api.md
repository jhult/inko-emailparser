# Streaming API Design for inko-emailparser

## Executive Summary

This document outlines a comprehensive streaming API design for processing large emails without loading the entire message into memory. The current parser loads complete email messages into memory, which can be problematic for emails approaching the 50MB default size limit. The proposed streaming API provides a callback/event-based architecture that enables progressive parsing of email components as they become available, dramatically reducing memory consumption and improving performance for large messages.

## Table of Contents

1. [Problem Statement](#problem-statement)
2. [Current Architecture Analysis](#current-architecture-analysis)
3. [Design Goals](#design-goals)
4. [API Design](#api-design)
5. [Memory-Efficient Parsing](#memory-efficient-parsing)
6. [Callback Architecture](#callback-architecture)
7. [Incremental Decoders](#incremental-decoders)
8. [Async Reader Interface](#async-reader-interface)
9. [Async API Guide](#async-api-guide)
10. [Configuration Guide](#configuration-guide)
11. [Error Handling](#error-handling)
12. [Backward Compatibility](#backward-compatibility)
13. [Trade-offs and Considerations](#trade-offs-and-considerations)
14. [Implementation Phases](#implementation-phases)
15. [Proof of Concept Examples](#proof-of-concept-examples)

---

## Problem Statement

### Current Limitations

The current `EmailParser` implementation loads the entire email message into memory before parsing begins:

```inko
# Current API - loads entire email into memory
let parser = EmailParser.new
match parser.parse(raw_email_string) {
  case Ok(message) -> {
    # Entire message (headers, bodies, attachments) in memory
    for att in message.attachments.iter {
      # Each attachment's full content is in memory
    }
  }
  case Error(e) -> { }
}
```

**Issues:**

1. **Memory consumption**: A 50MB email requires ~50MB of RAM minimum
2. **Base64 expansion**: Attachments expand by 33% during decoding, further increasing memory usage
3. **Processing latency**: User must wait for entire email to parse before accessing any data
4. **DoS vulnerability**: Memory-based attacks using large attachments or deep nesting
5. **Scalability limits**: Cannot handle emails larger than available RAM

### Real-World Scenarios

1. **Email servers processing large attachments**: 50MB PDFs, images, archives
2. **Email migration tools**: Processing millions of emails, many with attachments
3. **Email gateways**: Scanning for malware without loading full payloads
4. **Storage-constrained environments**: Embedded systems, cloud functions with memory limits
5. **High-throughput processing**: Processing multiple large emails concurrently

---

## Current Architecture Analysis

### Current Data Structures

```inko
type pub ParsedEmailMessage {
  let pub @from: EmailAddress
  let pub @to: Array[EmailAddress]
  let pub @subject: String
  let pub @text_body: Option[String]      # Full body in memory
  let pub @html_body: Option[String]      # Full body in memory
  let pub @attachments: Array[EmailAttachment]  # All attachments in memory
  # ... other fields
}

type pub EmailAttachment {
  let pub @content: ByteArray             # Full attachment in memory
  let pub @size: Int
  # ... other fields
}
```

### Memory Usage Analysis

For a typical 50MB email:
- **Raw email**: 50MB
- **Normalized email** (line endings): ~50MB
- **Headers**: ~5KB
- **Text body**: ~5KB
- **HTML body**: ~50KB
- **Attachments (3 × 15MB)**: 45MB raw, 60MB decoded
- **Total memory**: ~165MB (3.3× raw size)

### Parsing Flow

```
Raw String (50MB)
    ↓
normalize_line_endings() - allocates new String (~50MB)
    ↓
parse_headers_impl() - allocates Array[(String, String)]
    ↓
parse_multipart_impl() - recursive, allocates many Strings
    ↓
decode_body_impl() - for each attachment, allocates decoded String
    ↓
ParsedEmailMessage - holds all data in memory (~165MB total)
```

---

## Design Goals

### Primary Goals

1. **Memory Efficiency**: Parse large emails with O(1) memory (constant space relative to email size)
2. **Progressive Processing**: Access parsed components as they become available
3. **Backward Compatibility**: Existing API continues to work unchanged
4. **Performance**: No significant performance regression for small emails (<1MB)

### Secondary Goals

1. **Flexibility**: Allow users to skip unwanted parts (e.g., ignore attachments)
2. **Extensibility**: Easy to add new streaming operations
3. **Safety**: Maintain current error handling and validation
4. **Ergonomics**: Simple, intuitive API for common use cases

### Non-Goals

1. **Random access**: No ability to jump to arbitrary parts without parsing linearly
2. **Modifying emails**: Read-only API (email composition is a separate concern)
3. **Protocol streaming**: No SMTP/IMAP streaming (assumes email already loaded)

---

## API Design

### Core Types

#### 1. StreamingParser

```inko
type pub StreamingParser {
  let pub @config: StreamingConfig
}

type pub StreamingConfig {
  let pub @strict_mode: Bool
  let pub @max_email_size: Int
  let pub @max_attachment_size: Int
  let pub @max_multipart_depth: Int
  let pub @max_headers: Int
  let pub @stream_chunk_size: Int  # NEW: bytes to process per callback
}
```

#### 2. Event Callbacks (StreamHandler Trait)

```inko
trait pub StreamHandler {
  # Called when parsing begins
  fn pub on_begin(!! Error) -> Result[Nil, String]

  # Called when headers are parsed
  fn pub on_headers(!! Error, headers: ref Array[(String, String)]) -> Result[Nil, String]

  # Called when text body is available (in chunks)
  fn pub on_text_chunk(!! Error, chunk: String) -> Result[Nil, String]

  # Called when HTML body is available (in chunks)
  fn pub on_html_chunk(!! Error, chunk: String) -> Result[Nil, String]

  # Called when an attachment header is parsed (metadata only)
  fn pub on_attachment_begin(!! Error, info: AttachmentInfo) -> Result[Nil, String]

  # Called when attachment data is available (in chunks)
  fn pub on_attachment_chunk(!! Error, chunk: ByteArray, info: AttachmentInfo) -> Result[Nil, String]

  # Called when attachment is complete
  fn pub on_attachment_end(!! Error, info: AttachmentInfo) -> Result[Nil, String]

  # Called when parsing completes successfully
  fn pub on_end(!! Error) -> Result[Nil, String]

  # Called when an error occurs (optional, errors also propagated to caller)
  fn pub on_error(!! Error, error: String) -> Result[Nil, String]
}
```

#### 3. Attachment Metadata (Without Content)

```inko
type pub AttachmentInfo {
  let pub @index: Int                       # Attachment number (0-based)
  let pub @content_type: String
  let pub @filename: Option[String]
  let pub @content_disposition: String
  let pub @content_id: Option[String]
  let pub @size: Int                        # Total size (if known)
  let pub @transfer_encoding: String
}
```

#### 4. StreamingResult

```inko
type pub StreamingResult {
  let pub @from: EmailAddress
  let pub @to: Array[EmailAddress]
  let pub @cc: Array[EmailAddress]
  let pub @bcc: Array[EmailAddress]
  let pub @subject: String
  let pub @date: String
  let pub @message_id: String
  let pub @in_reply_to: Option[String]
  let pub @references: Array[String]
  let pub @thread_id: String
  let pub @content_type: String
  let pub @content_transfer_encoding: String
  let pub @charset: Option[String]
  let pub @extra_headers: Array[(String, String)]
  let pub @attachment_count: Int
  # NOTE: No @text_body, @html_body, @attachments - content is streamed
}
```

### API Usage Examples

#### Example 1: Stream to File (Save Attachments)

```inko
import emailparser (StreamingParser, AttachmentInfo, StreamingResult)
import std.fs.file (File)

type AttachmentSaver {}

impl StreamHandler for AttachmentSaver {
  let mut @current_file: Option[File]
  let mut @file_count: Int

  fn pub static new -> AttachmentSaver {
    AttachmentSaver(
      current_file: Option.None,
      file_count: 0,
    )
  }

  fn pub on_begin(!! Error) -> Result[Nil, String] {
    @file_count = 0
    Result.Ok(Nil)
  }

  fn pub on_attachment_begin(!! Error, info: AttachmentInfo) -> Result[Nil, String] {
    match info.filename {
      case Some(name) -> {
        let path = "attachments/${@file_count.to_string}_${name}"
        match File.new(path) {
          case Ok(file) -> {
            @current_file = Option.Some(file)
            @file_count = @file_count + 1
            Result.Ok(Nil)
          }
          case Error(e) -> Result.Error(e.to_string)
        }
      }
      case None -> {
        # Skip unnamed attachments
        @current_file = Option.None
        Result.Ok(Nil)
      }
    }
  }

  fn pub on_attachment_chunk(!! Error, chunk: ByteArray, info: AttachmentInfo) -> Result[Nil, String] {
    match @current_file {
      case Some(ref mut file) -> {
        match file.write_bytes(chunk) {
          case Ok(_) -> Result.Ok(Nil)
          case Error(e) -> Result.Error(e.to_string)
        }
      }
      case None -> Result.Ok(Nil)
    }
  }

  fn pub on_attachment_end(!! Error, info: AttachmentInfo) -> Result[Nil, String] {
    @current_file = Option.None
    Result.Ok(Nil)
  }

  fn pub on_end(!! Error) -> Result[Nil, String] {
    Result.Ok(Nil)
  }

  fn pub on_error(!! Error, error: String) -> Result[Nil, String] {
    Result.Ok(Nil)
  }

  # Stub implementations for other callbacks
  fn pub on_headers(!! Error, headers: ref Array[(String, String)]) -> Result[Nil, String] {
    Result.Ok(Nil)
  }

  fn pub on_text_chunk(!! Error, chunk: String) -> Result[Nil, String] {
    Result.Ok(Nil)
  }

  fn pub on_html_chunk(!! Error, chunk: String) -> Result[Nil, String] {
    Result.Ok(Nil)
  }
}

# Usage
let parser = StreamingParser.new
let handler = AttachmentSaver.new
match parser.parse_stream(raw_email_string, handler) {
  case Ok(result) -> {
    # result contains metadata only
    "Saved ${result.attachment_count.to_string} attachments"
  }
  case Error(e) -> "Parse error: ${e}"
}
```

#### Example 2: Stream to Database (Store Chunks)

```inko
import emailparser (StreamingParser, AttachmentInfo)

type DatabaseInserter {
  let mut @current_att_id: Option[Int]
  let mut @chunk_index: Int
  let @db_connection: DatabaseConnection  # hypothetical
}

impl StreamHandler for DatabaseInserter {
  fn pub static new(db: DatabaseConnection) -> DatabaseInserter {
    DatabaseInserter(
      current_att_id: Option.None,
      chunk_index: 0,
      db_connection: db,
    )
  }

  fn pub on_attachment_begin(!! Error, info: AttachmentInfo) -> Result[Nil, String] {
    # Create attachment record in database
    match @db_connection.insert_attachment(info) {
      case Ok(id) -> {
        @current_att_id = Option.Some(id)
        @chunk_index = 0
        Result.Ok(Nil)
      }
      case Error(e) -> Result.Error(e.to_string)
    }
  }

  fn pub on_attachment_chunk(!! Error, chunk: ByteArray, info: AttachmentInfo) -> Result[Nil, String] {
    match @current_att_id {
      case Some(att_id) -> {
        # Store chunk with sequence number
        match @db_connection.insert_chunk(att_id, @chunk_index, chunk) {
          case Ok(_) -> {
            @chunk_index = @chunk_index + 1
            Result.Ok(Nil)
          }
          case Error(e) -> Result.Error(e.to_string)
        }
      }
      case None -> Result.Ok(Nil)
    }
  }

  fn pub on_attachment_end(!! Error, info: AttachmentInfo) -> Result[Nil, String] {
    @current_att_id = Option.None
    Result.Ok(Nil)
  }

  # ... other callback implementations
}
```

#### Example 3: Scan Without Storing (Anti-Virus/Content Filter)

```inko
import emailparser (StreamingParser, AttachmentInfo)

type ContentScanner {
  let mut @found_suspicious: Bool

  fn pub static new -> ContentScanner {
    ContentScanner(found_suspicious: false)
  }

  fn pub on_attachment_chunk(!! Error, chunk: ByteArray, info: AttachmentInfo) -> Result[Nil, String] {
    if @found_suspicious {
      return Result.Error("Suspicious content detected, aborting")
    }

    # Scan chunk for malicious patterns
    if scan_for_malware(chunk) {
      @found_suspicious = true
      return Result.Error("Malware detected in attachment")
    }

    Result.Ok(Nil)
  }

  fn pub on_error(!! Error, error: String) -> Result[Nil, String] {
    # Log error but continue
    Result.Ok(Nil)
  }

  # ... other callback implementations
}

fn scan_for_malware(chunk: ByteArray) -> Bool {
  # Pattern matching implementation
  false
}
```

#### Example 4: Extract Only Metadata (No Content)

```inko
import emailparser (StreamingParser)

type MetadataExtractor {
  let mut @result: StreamingResult

  fn pub static new -> MetadataExtractor {
    MetadataExtractor(result: create_empty_result())
  }

  fn pub on_headers(!! Error, headers: ref Array[(String, String)]) -> Result[Nil, String] {
    @result = parse_metadata_from_headers(ref headers)
    Result.Ok(Nil)
  }

  # Skip all content callbacks (return Result.Ok immediately)
  fn pub on_text_chunk(!! Error, chunk: String) -> Result[Nil, String] {
    Result.Ok(Nil)
  }

  fn pub on_html_chunk(!! Error, chunk: String) -> Result[Nil, String] {
    Result.Ok(Nil)
  }

  fn pub on_attachment_chunk(!! Error, chunk: ByteArray, info: AttachmentInfo) -> Result[Nil, String] {
    # Don't store attachment content
    Result.Ok(Nil)
  }

  # ... other callback implementations
}
```

---

## Memory-Efficient Parsing

### Streaming Architecture

```
Raw String (50MB)
    ↓
Parser processes in chunks (e.g., 64KB at a time)
    ↓
Headers parsed → on_headers callback (5KB in memory)
    ↓
Text body → on_text_chunk callback (one 64KB chunk at a time)
    ↓
HTML body → on_html_chunk callback (one 64KB chunk at a time)
    ↓
Attachment 1:
  - on_attachment_begin (metadata only, ~100 bytes)
  - on_attachment_chunk (64KB chunk) → handler processes
  - on_attachment_chunk (64KB chunk) → handler processes
  - ...
  - on_attachment_end (handler flushes)
    ↓
Attachment 2... (repeat)
    ↓
on_end callback
```

### Memory Profile

For a 50MB email using streaming:

- **Parser state**: ~1KB (position tracking, buffers)
- **Current chunk**: 64KB (configurable)
- **Headers**: 5KB (once)
- **Handler state**: User-defined (typically <1MB)
- **Total memory**: ~70KB (0.14% of current 165MB)

**Memory reduction: ~99.86%**

### Chunked Decoding

Instead of decoding entire bodies at once, decode in chunks:

```inko
# Current: Decode entire body
fn decode_body_impl(raw: String, encoding: String) -> String {
  let decoder = Decoder.new
  let output = ByteArray.new
  decoder.decode(raw.to_byte_array, output)  # Full decode
  output.into_string
}

# Streaming: Decode and emit chunks
fn decode_body_stream(
  raw: String,
  encoding: String,
  chunk_size: Int,
  handler: ref StreamHandler,
) -> Result[Nil, String] {
  let decoder = StreamingDecoder.new(encoding: encoding)
  let mut position = 0

  while position < raw.size {
    let chunk_end = if position + chunk_size > raw.size {
      raw.size
    } else {
      position + chunk_size
    }

    let raw_chunk = raw.substring(position, chunk_end)
    let mut decoded_chunk = ByteArray.new

    match decoder.decode_chunk(raw_chunk.to_byte_array, decoded_chunk) {
      case Ok(_) -> {
        # Emit chunk
        match handler.on_text_chunk(decoded_chunk.into_string) {
          case Ok(_) -> {}
          case Error(e) -> return Result.Error(e)
        }
        position = chunk_end
      }
      case Error(e) -> return Result.Error(e.to_string)
    }
  }

  Result.Ok(Nil)
}
```

### Boundary-Aware Streaming

For multipart messages, streaming becomes more complex:

1. **Scan for boundary markers** while reading chunks
2. **Track part state** (headers vs body, current boundary depth)
3. **Emit callbacks at appropriate points**

```inko
type StreamingState {
  let mut @phase: StreamingPhase
  let mut @depth: Int
  let mut @boundary: Option[String]
  let mut @buffer: String  # Holds partial boundary matches
  let mut @in_headers: Bool
}

type enum StreamingPhase {
  case Headers
  case Body
  case Multipart
  case Attachment
  case End
}

fn stream_multipart(
  raw: String,
  boundary: String,
  handler: ref StreamHandler,
  state: mut StreamingState,
) -> Result[Nil, String] {
  # Process input in chunks, watching for boundary markers
  let chunk_size = 65536  # 64KB
  let mut position = 0

  while position < raw.size {
    let chunk = get_next_chunk(raw, position, chunk_size)
    let (processed, new_position) = process_chunk(
      chunk,
      boundary,
      handler,
      state,
    )

    position = new_position
  }

  Result.Ok(Nil)
}

fn process_chunk(
  chunk: String,
  boundary: String,
  handler: ref StreamHandler,
  state: mut StreamingState,
) -> (Int, Int) {
  # 1. Check for boundary marker in chunk
  # 2. If found, switch phases and emit appropriate callback
  # 3. Otherwise, emit content chunk based on current phase
  # 4. Handle partial boundary at chunk boundaries
  # ...
  (chunk.size, 0)
}
```

### Attachment Streaming

Attachments are the biggest memory consumer. Streaming them provides maximum benefit:

```inko
fn stream_attachment(
  body_raw: String,
  info: AttachmentInfo,
  handler: ref StreamHandler,
  chunk_size: Int,
) -> Result[Nil, String] {
  # Emit begin callback
  match handler.on_attachment_begin(info) {
    case Ok(_) -> {}
    case Error(e) -> return Result.Error(e)
  }

  # Decode and stream in chunks
  let decoder = StreamingDecoder.new(encoding: info.transfer_encoding)
  let mut position = 0

  while position < body_raw.size {
    let chunk_end = min(position + chunk_size, body_raw.size)
    let raw_chunk = body_raw.substring(position, chunk_end)
    let mut decoded_chunk = ByteArray.new

    match decoder.decode_chunk(raw_chunk.to_byte_array, decoded_chunk) {
      case Ok(_) -> {
        # Emit chunk
        match handler.on_attachment_chunk(decoded_chunk, info) {
          case Ok(_) -> {}
          case Error(e) -> return Result.Error(e)
        }
        position = chunk_end
      }
      case Error(e) -> return Result.Error(e.to_string)
    }
  }

  # Emit end callback
  match handler.on_attachment_end(info) {
    case Ok(_) -> {}
    case Error(e) -> return Result.Error(e)
  }

  Result.Ok(Nil)
}
```

---

## Callback Architecture

### Callback Lifecycle

```
on_begin()
  ↓
on_headers() [called once]
  ↓
[For text/plain body]:
  on_text_chunk() [called multiple times]
    ↓
[For text/html body]:
  on_html_chunk() [called multiple times]
    ↓
[For each attachment]:
  on_attachment_begin() [once per attachment]
  on_attachment_chunk() [multiple times per attachment]
  on_attachment_end() [once per attachment]
    ↓
on_end()
    ↓
[If error occurs at any point]:
  on_error() [optional]
```

### Error Propagation

**Two mechanisms for error handling:**

1. **Immediate abort**: Callback returns `Result.Error`
   - Parsing stops immediately
   - Error is returned to caller
   - Used for critical errors

2. **Continue processing**: Callback returns `Result.Ok` but logs error
   - Parsing continues
   - Error reported via `on_error` callback
   - Used for non-critical errors (e.g., malformed attachment)

```inko
# Example: Skip malformed attachments but continue parsing
type PermissiveHandler {}

impl StreamHandler for PermissiveHandler {
  fn pub on_attachment_chunk(!! Error, chunk: ByteArray, info: AttachmentInfo) -> Result[Nil, String] {
    match process_chunk(chunk) {
      case Ok(_) -> Result.Ok(Nil)
      case Error(e) -> {
        # Log but don't fail
        log_error("Attachment ${info.index}: ${e}")
        Result.Ok(Nil)
      }
    }
  }
}
```

### Contextual Information

Callbacks receive contextual information:

```inko
trait pub StreamHandler {
  # All callbacks receive !! Error for panics
  # Headers callback receives headers reference
  fn pub on_headers(!! Error, headers: ref Array[(String, String)]) -> Result[Nil, String]

  # Attachment callbacks include metadata
  fn pub on_attachment_chunk(!! Error, chunk: ByteArray, info: AttachmentInfo) -> Result[Nil, String]
}
```

**Why `!! Error`?**

Inko uses `!!` for methods that can panic. This allows callbacks to:

1. Use `panic!` for unrecoverable errors (immediate failure)
2. Return `Result` for recoverable errors
3. Propagate panics to the parser

### Handler State Management

Handlers maintain state across callbacks:

```inko
type StreamingAttachmentHandler {
  let mut @current_file: Option[File]
  let mut @attachment_index: Int
  let mut @bytes_written: Int
  let @output_dir: String
}

impl StreamingAttachmentHandler {
  fn pub static new(output_dir: String) -> StreamingAttachmentHandler {
    StreamingAttachmentHandler(
      current_file: Option.None,
      attachment_index: 0,
      bytes_written: 0,
      output_dir: output_dir,
    )
  }

  fn pub on_attachment_begin(!! Error, info: AttachmentInfo) -> Result[Nil, String] {
    @attachment_index = @attachment_index + 1

    match info.filename {
      case Some(name) -> {
        let path = "${@output_dir}/${@attachment_index.to_string}_${name}"
        match File.new(path) {
          case Ok(file) -> {
            @current_file = Option.Some(file)
            @bytes_written = 0
            Result.Ok(Nil)
          }
          case Error(e) -> Result.Error(e.to_string)
        }
      }
      case None -> Result.Ok(Nil)
    }
  }

  fn pub on_attachment_chunk(!! Error, chunk: ByteArray, info: AttachmentInfo) -> Result[Nil, String] {
    match @current_file {
      case Some(ref mut file) -> {
        match file.write_bytes(chunk) {
          case Ok(bytes) -> {
            @bytes_written = @bytes_written + bytes
            Result.Ok(Nil)
          }
          case Error(e) -> Result.Error(e.to_string)
        }
      }
      case None -> Result.Ok(Nil)
    }
  }
}
```

---

## Incremental Decoders

The streaming API uses incremental decoders that can process data in chunks without loading entire encoded bodies into memory. Two decoders are implemented:

### Base64StreamingDecoder

Processes Base64-encoded data incrementally, handling chunk boundaries gracefully.

**Key Features:**
- Buffers input until padding (`=`) is detected
- Filters whitespace (CR, LF, space, tab) automatically
- Supports strict mode (rejects invalid characters) and lax mode (skips them)
- Tracks decoded bytes against `max_size` limit
- Returns empty `ByteArray` until a complete encoded block is available

**Usage Example:**

```inko
import emailparser.streaming_decoder (Base64StreamingDecoder)

let mut decoder = Base64StreamingDecoder.new(50_000_000, false)

# Feed data in chunks
let chunk1 = "SGVsbG8gV29ybGQ="
match decoder.feed(chunk1) {
  case Ok(decoded) -> {
    # Process decoded chunk
    if decoded.size > 0 {
      Stdout.new.print("Got ${decoded.size.to_string} bytes")
    }
  }
  case Error(e) -> Stderr.new.print("Error: ${e}")
}

# Call finish to get any remaining data
match decoder.finish {
  case Ok(final) -> {
    # Process final chunk
  }
  case Error(e) -> Stderr.new.print("Error: ${e}")
}
```

**Chunk Boundary Handling:**

Base64 encodes 3 bytes into 4 characters. Chunk boundaries can occur anywhere in the encoded stream. The decoder handles this by:

1. Accumulating input in an internal buffer
2. Only decoding when complete quads (4 characters) are found or padding is present
3. Returning any decoded data immediately when available
4. Buffering incomplete quads for the next chunk

**Example of chunked input:**
```
Chunk 1: "SGVsbG8g" (decodes to "Hello")
Chunk 2: "V29ybGQ=" (decodes to "World")
```

### QuotedPrintableStreamingDecoder

Processes Quoted-Printable encoded data, handling soft line breaks and incomplete sequences.

**Key Features:**
- Buffers incomplete sequences (`=XX` split across chunks)
- Handles soft line breaks (`=\r\n` or `=\n`)
- Supports underscore-as-space mode (RFC 2047 encoded-word)
- Configurable error handling (`preserve_equals_on_error`)
- Tracks decoded size against `max_size` limit

**Usage Example:**

```inko
import emailparser.streaming_decoder (QuotedPrintableStreamingDecoder)

let mut decoder = QuotedPrintableStreamingDecoder.new(50_000_000, false, false)

# Feed data in chunks
let chunk1 = "Hello=20"
match decoder.feed(chunk1) {
  case Ok(decoded) -> {
    # Process decoded chunk
  }
  case Error(e) -> Stderr.new.print("Error: ${e}")
}
```

**Chunk Boundary Handling:**

Quoted-Printable sequences can be split across chunks. The decoder handles this by:

1. Detecting incomplete sequences (`=` at end, `=X`, `=\r`)
2. Buffering everything until a complete sequence is available
3. Returning empty result when data is incomplete
4. Processing complete sequences in the next chunk

**Example of chunked input:**
```
Chunk 1: "Hello=" (incomplete - buffers all)
Chunk 2: "20World" (completes "=20" and decodes "Hello World")
```

**Special Cases:**

- `=` followed by `=`: Treated as literal `=` (common in encoded-words)
- `=\r\n` or `=\n`: Soft line break - removed from output
- Underscore-as-space: Converts `_` to space when enabled (RFC 2047)

### Decoder Comparison

| Feature | Base64StreamingDecoder | QuotedPrintableStreamingDecoder |
|---------|----------------------|-------------------------------|
| Output size | 75% of input | Similar to input |
| Chunk boundaries | Buffered until quad complete | Buffered until sequence complete |
| Whitespace | Filtered automatically | Preserved (except soft breaks) |
| Strict mode | Invalid char check | N/A |
| Max size | Truncates on exceed | Returns error on exceed |

---

## Async Reader Interface

The `AsyncReader` trait provides a generic interface for reading data incrementally from various sources.

### Trait Definition

```inko
trait pub AsyncReader {
  # Read up to size bytes from source
  #
  # Returns:
  # - Ok(ByteArray) with bytes read (may be empty if EOF)
  # - Error(String) if a read error occurs
  fn pub mut read(size: Int) -> Result[ByteArray, String]
}
```

### ByteArrayReader

A simple implementation that wraps in-memory `ByteArray` for testing and when data is already loaded.

**Features:**
- Zero-copy reading from existing data
- Returns empty `ByteArray` on EOF (not error)
- Never returns `Error` (always `Ok`)
- Tracks position and size for debugging

**Usage Example:**

```inko
import emailparser.streaming_reader (AsyncReader, ByteArrayReader)

let data = "email content here".to_byte_array
let mut reader = ByteArrayReader.new(data)

loop {
  match reader.read(1024) {
    case Ok(chunk) -> {
      if chunk.size == 0 {
        break
      }
      # Process chunk
    }
    case Error(e) -> Stderr.new.print("Error: ${e}")
  }
}
```

**Methods:**

```inko
fn pub static new(data: ByteArray) -> ByteArrayReader
fn pub static from_string(text: String) -> ByteArrayReader
fn pub position -> Int
fn pub size -> Int
fn pub eof? -> Bool
```

### Future Reader Implementations

The trait-based design allows for additional implementations:

- **FileReader**: Read from files asynchronously
- **TcpStreamReader**: Read from network connections
- **BufferedReader**: Add buffering to any reader

---

## Async API Guide

The streaming API provides three methods for parsing emails:

### 1. parse_stream - Synchronous String Parsing

Parse an email from a complete `String` with streaming callbacks.

**Signature:**

```inko
fn pub mut parse_stream[H: mut + StreamHandler](
  raw: String,
  handler: mut H,
) -> Result[StreamingResult, String]
```

**Use When:**
- Email is already loaded into memory as a `String`
- You need synchronous processing
- Testing with in-memory data

**Example:**

```inko
let parser = StreamingParser.new
let handler = MyHandler.new
match parser.parse_stream(email_string, handler) {
  case Ok(result) -> {
    # result contains metadata only
  }
  case Error(e) -> {
    # Handle error
  }
}
```

### 2. parse_async_raw - Async String Parsing

Parse an email from a `String` with async processing.

**Signature:**

```inko
fn pub mut parse_async_raw[H: mut + StreamHandler](
  raw: String,
  handler: mut H,
) -> Result[StreamingResult, String]
```

**Use When:**
- Email is in memory but handlers perform async operations
- Handlers need to await async operations
- Backpressure handling needed

**Example:**

```inko
# In an async process
type async Main {
  fn async main {
    let parser = StreamingParser.new
    let handler = AsyncHandler.new
    match parser.parse_async_raw(email_string, handler) {
      case Ok(result) -> {}
      case Error(e) -> {}
    }
  }
}
```

### 3. parse_async_reader - Async Reader Parsing

Parse an email incrementally from an `AsyncReader`.

**Signature:**

```inko
fn pub mut parse_async_reader[H: mut + StreamHandler](
  reader: AsyncReader,
  handler: mut H,
) -> Result[StreamingResult, String]
```

**Use When:**
- Reading from files, network, or other incremental sources
- Email size is too large for memory
- True streaming (not just chunked processing) is needed

**Example:**

```inko
import emailparser.streaming_reader (ByteArrayReader)

let reader = ByteArrayReader.from_string(email_string)
let parser = StreamingParser.new
let handler = FileSaver.new("output")

match parser.parse_async_reader(reader, handler) {
  case Ok(result) -> {
    # Parsed successfully
  }
  case Error(e) -> {
    # Handle error
  }
}
```

### Method Comparison

| Method | Input | Async Handlers | True Streaming | Use Case |
|--------|-------|---------------|----------------|-----------|
| `parse_stream` | `String` | No | No | Testing, small emails |
| `parse_async_raw` | `String` | Yes | No | Async processing |
| `parse_async_reader` | `AsyncReader` | Yes | Yes | Files, network, large emails |

### Callback Execution

Regardless of parsing method, callbacks are executed synchronously:

- **For `parse_stream`**: Callbacks run synchronously in caller's process
- **For `parse_async_raw`**: Handlers can use `await` within callbacks
- **For `parse_async_reader`**: Handlers can use `await` within callbacks

**Note:** The parser itself is synchronous - it waits for callbacks to complete before proceeding.

### Memory Footprint by Method

| Method | Email in Memory | Chunk Size | Peak Memory |
|--------|-----------------|-------------|--------------|
| `parse_stream` | Yes (entire email) | Configurable | Email size + chunk size |
| `parse_async_raw` | Yes (entire email) | Configurable | Email size + chunk size |
| `parse_async_reader` | No | Configurable | Chunk size only |

---

## Configuration Guide

The `StreamingConfig` type provides fine-grained control over parsing behavior.

### Configuration Options

```inko
type pub StreamingConfig {
  let pub mut @strict_mode: Bool
  let pub mut @fail_fast: Bool
  let pub mut @max_email_size: Int
  let pub mut @max_attachment_size: Int
  let pub mut @max_multipart_depth: Int
  let pub mut @max_headers: Int
  let pub mut @stream_chunk_size: Int
}
```

### Default Configuration

```inko
StreamingConfig(
  strict_mode: false,
  fail_fast: false,
  max_email_size: 50_000_000,      # 50MB
  max_attachment_size: 25_000_000,   # 25MB
  max_multipart_depth: 10,
  max_headers: 1000,
  stream_chunk_size: 65536,          # 64KB
)
```

### strict_mode

**Controls validation strictness.**

- `false` (default): Lax parsing, recovers from common errors
- `true`: Strict RFC compliance, rejects malformed emails

**Impact:**
- Base64: Invalid characters (lax: skip, strict: error)
- Multipart: Missing boundaries (lax: attempt recovery, strict: error)

**Recommendation:**
- Use `false` for production (handle real-world emails)
- Use `true` for validation/testing

```inko
let config = StreamingConfig.new
config.strict_mode = true
let parser = StreamingParser.with_config(config)
```

### fail_fast

**Controls error propagation to handlers.**

- `false` (default): Errors returned to caller, handler's `on_error` called
- `true`: Parsing stops immediately on first error

**Impact:**
- Handler `on_error` always called regardless of setting
- With `fail_fast=false`, parser may continue after non-fatal errors
- With `fail_fast=true`, any error aborts parsing

**Recommendation:**
- Use `false` when you want to collect multiple errors
- Use `true` for critical applications where any error is unacceptable

```inko
let config = StreamingConfig.new
config.fail_fast = true
```

### max_email_size

**Maximum allowed email size in bytes.**

**Default:** `50_000_000` (50MB)

**Impact:**
- Prevents memory exhaustion
- Rejects emails larger than limit with clear error message

**Recommendation:**
- Increase if you need to handle larger emails (up to available RAM)
- Decrease for constrained environments (embedded, cloud functions)

```inko
let config = StreamingConfig.new
config.max_email_size = 100_000_000  # 100MB
```

### max_attachment_size

**Maximum decoded attachment size in bytes.**

**Default:** `25_000_000` (25MB)

**Impact:**
- Enforced per attachment
- Decoders truncate or error when exceeded

**Recommendation:**
- Set based on your storage capacity
- Consider Base64 expansion (33%) when setting limit

```inko
let config = StreamingConfig.new
config.max_attachment_size = 50_000_000  # 50MB per attachment
```

### max_multipart_depth

**Maximum nesting level for multipart messages.**

**Default:** `10`

**Impact:**
- Prevents stack overflow from deeply nested multipart
- Rejects emails exceeding depth

**Recommendation:**
- Rarely need to increase (10 is very generous)
- Decrease for stricter validation

```inko
let config = StreamingConfig.new
config.max_multipart_depth = 5
```

### max_headers

**Maximum number of headers per part.**

**Default:** `1000`

**Impact:**
- Prevents header flood attacks
- Rejects parts with excessive headers

**Recommendation:**
- Rarely need to adjust
- Decrease for stricter validation

```inko
let config = StreamingConfig.new
config.max_headers = 500
```

### stream_chunk_size

**Size of chunks delivered to callbacks in bytes.**

**Default:** `65536` (64KB)

**Impact:**
- Smaller chunks: Lower latency, more callbacks
- Larger chunks: Higher throughput, fewer callbacks
- Trade-off: Callback overhead vs responsiveness

**Recommendations:**

| Scenario | Chunk Size | Reason |
|----------|-------------|---------|
| Small emails | 16KB | Lower latency |
| Large attachments | 256KB - 1MB | Higher throughput |
| Network I/O | 8KB - 16KB | Match TCP segment size |
| Default | 64KB | Balanced |

```inko
let config = StreamingConfig.new
config.stream_chunk_size = 131072  # 128KB
```

### Builder Pattern

`StreamingConfig` provides fluent builder methods:

```inko
let config = StreamingConfig.new
  .with_strict_mode(true)
  .with_fail_fast(false)
  .with_max_email_size(100_000_000)
  .with_stream_chunk_size(131072)

let parser = StreamingParser.with_config(config)
```

---

## Error Handling

### Error Types

Extend existing error types with streaming-specific errors:

```inko
type enum StreamingError {
  case ParserError(Error)
  case HandlerError(String)
  case StreamAborted(String)
  case ChunkDecodeError(String)
  case BoundaryError(String)
}
```

### Error Scenarios

1. **Parser errors** (existing):
   - Invalid email format
   - Size limit exceeded
   - Boundary not found
   - Multipart depth exceeded

2. **Handler errors** (new):
   - Callback returns `Result.Error`
   - Handler panic (caught via `!! Error`)
   - I/O errors in handler (file write, network send, etc.)

3. **Streaming errors** (new):
   - Invalid chunk size
   - Partial boundary at end of stream
   - Decode error mid-stream

### Error Recovery Strategies

#### Strategy 1: Fail Fast (Default)

```inko
# Handler returns error on first problem
type StrictHandler {}

impl StreamHandler for StrictHandler {
  fn pub on_attachment_chunk(!! Error, chunk: ByteArray, info: AttachmentInfo) -> Result[Nil, String] {
    match process_chunk(chunk) {
      case Ok(_) -> Result.Ok(Nil)
      case Error(e) -> Result.Error("Failed to process chunk: ${e}")
    }
  }
}
```

#### Strategy 2: Permissive (Skip Bad Parts)

```inko
# Handler logs errors but continues
type PermissiveHandler {
  let mut @errors: Array[String]
}

impl StreamHandler for PermissiveHandler {
  fn pub on_error(!! Error, error: String) -> Result[Nil, String] {
    @errors.push(error)
    Result.Ok(Nil)
  }

  fn pub on_attachment_chunk(!! Error, chunk: ByteArray, info: AttachmentInfo) -> Result[Nil, String] {
    match process_chunk(chunk) {
      case Ok(_) -> Result.Ok(Nil)
      case Error(e) -> {
        @errors.push("Attachment ${info.index}: ${e}")
        Result.Ok(Nil)
      }
    }
  }
}
```

#### Strategy 3: Conditional Abort

```inko
# Abort only on certain conditions
type ConditionalHandler {
  let @abort_on_attachment_errors: Bool

  fn pub on_attachment_chunk(!! Error, chunk: ByteArray, info: AttachmentInfo) -> Result[Nil, String] {
    match process_chunk(chunk) {
      case Ok(_) -> Result.Ok(Nil)
      case Error(e) -> {
        if @abort_on_attachment_errors {
          Result.Error(e)
        } else {
          Result.Ok(Nil)
        }
      }
    }
  }
}
```

---

## Backward Compatibility

### Maintain Existing API

The current `EmailParser` API remains unchanged:

```inko
# Existing API continues to work
let parser = EmailParser.new
match parser.parse(raw_email_string) {
  case Ok(message) -> {
    # message: ParsedEmailMessage with full content in memory
    for att in message.attachments.iter {
      # All attachments loaded
    }
  }
  case Error(e) -> { }
}
```

### Implementation Strategy

1. **Keep current implementation as-is**
2. **Add new `StreamingParser` type** in separate module
3. **Share common code** (header parsing, MIME logic, error types)
4. **Internal refactoring** (optional, extract shared functions)

### API Migration Path

Users can migrate gradually:

```inko
# Phase 1: Use current API (no changes)
let parser = EmailParser.new
parser.parse(email_string)

# Phase 2: Use streaming for large emails
if email_string.size > 10_000_000 {  # >10MB
  let stream_parser = StreamingParser.new
  let handler = create_handler()
  stream_parser.parse_stream(email_string, handler)
} else {
  let parser = EmailParser.new
  parser.parse(email_string)
}

# Phase 3: Migrate to streaming exclusively
let stream_parser = StreamingParser.new
let handler = create_handler()
stream_parser.parse_stream(email_string, handler)
```

### Code Sharing

Extract common functions for reuse:

```inko
# Shared in emailparser/header.inko
fn pub parse_headers_impl(...) -> Result[Array[(String, String)], Error]

# Used by both parsers
# EmailParser uses it directly
# StreamingParser uses it to emit on_headers callback

# Shared in emailparser/multipart.inko
fn pub extract_part_metadata(...) -> (String, Array[(String, String)], ...)

# Used by both parsers
```

---

## Trade-offs and Considerations

### Complexity vs Performance

| Aspect | Current API | Streaming API |
|--------|-------------|---------------|
| **Code complexity** | Low | High |
| **Learning curve** | Low | Medium |
| **Memory usage** | O(n) | O(1) |
| **Processing time** | Fast start, long total | Fast first results |
| **Random access** | Yes (after parse) | No (linear only) |
| **Use cases** | Small emails, full access | Large emails, progressive |

**Trade-off decision:**

- **Use current API** when:
  - Email size < 10MB
  - Need full random access to all parts
  - Simplicity is priority
  - Memory is not constrained

- **Use streaming API** when:
  - Email size > 10MB
  - Only need sequential access
  - Memory is constrained
  - Need to process progressively

### Which Parts to Stream?

**Recommendations:**

1. **Headers**: Don't stream (too small, needed for all decisions)
   - Load into memory once (typically <10KB)
   - Required for parsing strategy

2. **Text bodies**: Stream (can be large, optional to store)
   - Useful for search/indexing
   - Can skip if not needed

3. **HTML bodies**: Stream (can be large, optional to store)
   - Similar to text bodies
   - Often larger than text

4. **Attachments**: Always stream (primary memory consumer)
   - Can be very large (up to 25MB each)
   - Often only need to save to disk or database
   - Can skip entirely for metadata-only parsing

**Chunk size selection:**

- **Default**: 64KB (good balance of throughput and latency)
- **Small files**: 16KB (lower latency)
- **Large attachments**: 256KB or 1MB (higher throughput)
- **Network I/O**: 8KB or 16KB (match TCP segment size)

### Callback Overhead

**Performance considerations:**

- **Callback cost**: ~10-100ns per call (depends on language overhead)
- **Chunk overhead**: 64KB chunks = ~150-1500 calls for 10MB attachment
- **Total overhead**: ~1.5-15ms per 10MB attachment (negligible)

**Optimization techniques:**

1. **Batch callbacks**: Combine multiple small chunks
2. **Direct buffer access**: Pass ByteArray references instead of copying
3. **Zero-copy decoding**: Decode directly into handler's buffer

### Threading and Concurrency

**Current constraints:**

- Inko uses actor-based concurrency (processes)
- StreamingParser is synchronous by design
- Callbacks run in same process as parser

**Future extensions:**

1. **Parallel attachment processing**:
   - Spawn process per attachment
   - Send chunks to processes via channels
   - Requires `uni` values for safety

2. **Async I/O in handlers**:
   - Use async file/network operations
   - Parser pauses while waiting for I/O
   - Backpressure handling

**Current recommendation:**

- Keep parsing synchronous and single-threaded
- Use `uni` values for concurrent processing if needed
- Implement backpressure if handlers are slower than parser

---

## Implementation Phases

### Phase 1: Core Infrastructure (Weeks 1-2)

**Tasks:**

1. Create `StreamingParser` type
2. Define `StreamHandler` trait
3. Define `AttachmentInfo` type
4. Define `StreamingResult` type
5. Create `StreamingConfig` type
6. Add `parse_stream()` method to `StreamingParser`

**Deliverables:**

- `src/emailparser/streaming.inko` module
- Basic structure with stub callbacks
- Documentation of new types

### Phase 2: Header Streaming (Week 3)

**Tasks:**

1. Implement header parsing with `on_headers` callback
2. Create metadata extraction functions
3. Implement `on_begin` and `on_end` callbacks
4. Add error handling for header parsing

**Deliverables:**

- Functional header streaming
- `StreamingResult` populated with header metadata
- Unit tests for header streaming

### Phase 3: Body Streaming (Week 4)

**Tasks:**

1. Implement text body chunking
2. Implement HTML body chunking
3. Create chunked decoder (base64, quoted-printable)
4. Add body size tracking
5. Implement `on_text_chunk` and `on_html_chunk` callbacks

**Deliverables:**

- Functional body streaming
- Chunked decoding implementation
- Unit tests for body streaming

### Phase 4: Attachment Streaming (Weeks 5-6)

**Tasks:**

1. Implement attachment metadata extraction
2. Create `on_attachment_begin`, `on_attachment_chunk`, `on_attachment_end` callbacks
3. Implement chunked attachment decoding
4. Handle nested multipart with streaming
5. Add boundary-aware streaming for multipart
6. Track attachment sizes

**Deliverables:**

- Functional attachment streaming
- Multipart streaming support
- Unit tests for attachment streaming

### Phase 5: Error Handling and Edge Cases (Week 7)

**Tasks:**

1. Implement `on_error` callback
2. Add streaming error types
3. Handle partial boundaries at chunk boundaries
4. Implement recovery strategies (fail fast, permissive, conditional)
5. Add context to error messages (line numbers, byte offsets)

**Deliverables:**

- Comprehensive error handling
- Error recovery implementations
- Unit tests for error scenarios

### Phase 6: Documentation and Examples (Week 8)

**Tasks:**

1. Write API documentation for all new types
2. Create example handlers:
   - File saver
   - Database inserter
   - Content scanner
   - Metadata extractor
3. Write migration guide
4. Update README with streaming API examples

**Deliverables:**

- Complete API documentation
- 4+ example handlers
- Migration guide
- Updated README

### Phase 7: Testing and Validation (Weeks 9-10)

**Tasks:**

1. Test with real-world large emails (10MB, 25MB, 50MB)
2. Benchmark memory usage (current vs streaming)
3. Benchmark performance (small vs large emails)
4. Validate RFC compliance for streaming
5. Test error scenarios (malformed emails, oversized attachments)
6. Stress test with concurrent parsers

**Deliverables:**

- Performance benchmarks
- Memory usage comparison
- RFC compliance validation
- Stress test results

### Phase 8: Refinement and Polish (Weeks 11-12)

**Tasks:**

1. Optimize chunk sizes based on benchmarks
2. Reduce callback overhead if needed
3. Add convenience methods (e.g., pre-built handlers)
4. Refine error messages for better UX
5. Code review and cleanup
6. Final documentation polish

**Deliverables:**

- Optimized implementation
- Convenience handler library
- Polished documentation
- Code review approval

---

## Proof of Concept Examples

### Example 1: Simple Print Handler

```inko
import emailparser (StreamingParser, AttachmentInfo, StreamingResult)

type PrintHandler {}

impl StreamHandler for PrintHandler {
  fn pub on_begin(!! Error) -> Result[Nil, String] {
    Stdout.new.print("=== Starting email parsing ===")
    Result.Ok(Nil)
  }

  fn pub on_headers(!! Error, headers: ref Array[(String, String)]) -> Result[Nil, String] {
    Stdout.new.print("Headers parsed:")
    for (name, value) in headers.iter {
      Stdout.new.print("  ${name}: ${value.substring(0, 50)}")
    }
    Result.Ok(Nil)
  }

  fn pub on_text_chunk(!! Error, chunk: String) -> Result[Nil, String] {
    Stdout.new.print("Text body chunk (${chunk.size.to_string} bytes)")
    Result.Ok(Nil)
  }

  fn pub on_attachment_begin(!! Error, info: AttachmentInfo) -> Result[Nil, String] {
    Stdout.new.print(
      "Attachment #${info.index.to_string}: ${info.filename.or("unnamed")} (${info.content_type})"
    )
    Result.Ok(Nil)
  }

  fn pub on_attachment_chunk(!! Error, chunk: ByteArray, info: AttachmentInfo) -> Result[Nil, String] {
    Stdout.new.print("  Received chunk: ${chunk.size.to_string} bytes")
    Result.Ok(Nil)
  }

  fn pub on_end(!! Error) -> Result[Nil, String] {
    Stdout.new.print("=== Parsing complete ===")
    Result.Ok(Nil)
  }

  fn pub on_error(!! Error, error: String) -> Result[Nil, String] {
    Stderr.new.print("Error: ${error}")
    Result.Ok(Nil)
  }

  fn pub on_html_chunk(!! Error, chunk: String) -> Result[Nil, String] {
    Result.Ok(Nil)
  }

  fn pub on_attachment_end(!! Error, info: AttachmentInfo) -> Result[Nil, String] {
    Result.Ok(Nil)
  }
}

# Usage
let parser = StreamingParser.new
let handler = PrintHandler.new
match parser.parse_stream(large_email_string, handler) {
  case Ok(result) -> {
    Stdout.new.print("Email processed: ${result.subject}")
  }
  case Error(e) -> {
    Stderr.new.print("Failed to parse: ${e}")
  }
}
```

### Example 2: Chunked Attachment Writer

```inko
import emailparser (StreamingParser, AttachmentInfo)
import std.fs.file (File)
import std.stdio (Stdout)

type ChunkedWriter {
  let @output_dir: String
  let mut @current_file: Option[File]
  let mut @chunk_count: Int

  fn pub static new(output_dir: String) -> ChunkedWriter {
    ChunkedWriter(
      output_dir: output_dir,
      current_file: Option.None,
      chunk_count: 0,
    )
  }

  fn pub on_attachment_begin(!! Error, info: AttachmentInfo) -> Result[Nil, String] {
    @chunk_count = 0

    match info.filename {
      case Some(name) -> {
        # Sanitize filename
        let safe_name = name.replace('/', '_').replace('\\', '_')
        let path = "${@output_dir}/${safe_name}"

        match File.new(path) {
          case Ok(file) -> {
            @current_file = Option.Some(file)
            Stdout.new.print("Writing attachment: ${path}")
            Result.Ok(Nil)
          }
          case Error(e) -> Result.Error("Failed to create file: ${e.to_string}")
        }
      }
      case None -> Result.Ok(Nil)
    }
  }

  fn pub on_attachment_chunk(!! Error, chunk: ByteArray, info: AttachmentInfo) -> Result[Nil, String] {
    match @current_file {
      case Some(ref mut file) -> {
        match file.write_bytes(chunk) {
          case Ok(_) -> {
            @chunk_count = @chunk_count + 1

            # Progress indicator
            if @chunk_count % 100 == 0 {
              Stdout.new.print("  Processed ${(@chunk_count.to_string)} chunks...")
            }

            Result.Ok(Nil)
          }
          case Error(e) -> Result.Error("Failed to write chunk: ${e.to_string}")
        }
      }
      case None -> Result.Ok(Nil)
    }
  }

  fn pub on_attachment_end(!! Error, info: AttachmentInfo) -> Result[Nil, String] {
    match @current_file {
      case Some(ref mut file) -> {
        match file.flush {
          case Ok(_) -> {
            Stdout.new.print("  Completed: ${(@chunk_count.to_string)} chunks total")
            @current_file = Option.None
            Result.Ok(Nil)
          }
          case Error(e) -> Result.Error("Failed to flush file: ${e.to_string}")
        }
      }
      case None -> Result.Ok(Nil)
    }
  }

  # Stub implementations for other callbacks
  fn pub on_begin(!! Error) -> Result[Nil, String] { Result.Ok(Nil) }
  fn pub on_headers(!! Error, headers: ref Array[(String, String)]) -> Result[Nil, String] { Result.Ok(Nil) }
  fn pub on_text_chunk(!! Error, chunk: String) -> Result[Nil, String] { Result.Ok(Nil) }
  fn pub on_html_chunk(!! Error, chunk: String) -> Result[Nil, String] { Result.Ok(Nil) }
  fn pub on_end(!! Error) -> Result[Nil, String] { Result.Ok(Nil) }
  fn pub on_error(!! Error, error: String) -> Result[Nil, String] {
    Stderr.new.print("Error: ${error}")
    Result.Ok(Nil)
  }
}

# Usage
let parser = StreamingParser.new
let handler = ChunkedWriter.new("attachments")
match parser.parse_stream(large_email_string, handler) {
  case Ok(result) -> {
    Stdout.new.print("Success! Processed ${result.attachment_count.to_string} attachments")
  }
  case Error(e) -> {
    Stderr.new.print("Failed: ${e}")
  }
}
```

### Example 3: Memory-Mapped Attachment Processing

```inko
import emailparser (StreamingParser, AttachmentInfo)
import std.fs.file (File)
import std.stdio (Stdout)

type MemoryMappedProcessor {
  let @output_dir: String
  let mut @current_file: Option[File]
  let mut @total_bytes: Int

  fn pub static new(output_dir: String) -> MemoryMappedProcessor {
    MemoryMappedProcessor(
      output_dir: output_dir,
      current_file: Option.None,
      total_bytes: 0,
    )
  }

  fn pub on_attachment_begin(!! Error, info: AttachmentInfo) -> Result[Nil, String] {
    @total_bytes = 0

    match info.filename {
      case Some(name) -> {
        let safe_name = name.replace('/', '_').replace('\\', '_')
        let path = "${@output_dir}/${safe_name}"

        match File.new(path) {
          case Ok(file) -> {
            @current_file = Option.Some(file)
            Stdout.new.print("Processing attachment: ${path}")
            Result.Ok(Nil)
          }
          case Error(e) -> Result.Error("Failed to create file: ${e.to_string}")
        }
      }
      case None -> Result.Ok(Nil)
    }
  }

  fn pub on_attachment_chunk(!! Error, chunk: ByteArray, info: AttachmentInfo) -> Result[Nil, String] {
    match @current_file {
      case Some(ref mut file) -> {
        match file.write_bytes(chunk) {
          case Ok(bytes_written) -> {
            @total_bytes = @total_bytes + bytes_written
            Result.Ok(Nil)
          }
          case Error(e) -> Result.Error("Failed to write chunk: ${e.to_string}")
        }
      }
      case None -> Result.Ok(Nil)
    }
  }

  fn pub on_attachment_end(!! Error, info: AttachmentInfo) -> Result[Nil, String] {
    match @current_file {
      case Some(_) -> {
        Stdout.new.print("  Total bytes written: ${@total_bytes.to_string}")
        @current_file = Option.None
        Result.Ok(Nil)
      }
      case None -> Result.Ok(Nil)
    }
  }

  # Stub implementations for other callbacks
  fn pub on_begin(!! Error) -> Result[Nil, String] { Result.Ok(Nil) }
  fn pub on_headers(!! Error, headers: ref Array[(String, String)]) -> Result[Nil, String] { Result.Ok(Nil) }
  fn pub on_text_chunk(!! Error, chunk: String) -> Result[Nil, String] { Result.Ok(Nil) }
  fn pub on_html_chunk(!! Error, chunk: String) -> Result[Nil, String] { Result.Ok(Nil) }
  fn pub on_end(!! Error) -> Result[Nil, String] { Result.Ok(Nil) }
  fn pub on_error(!! Error, error: String) -> Result[Nil, String] {
    Stderr.new.print("Error: ${error}")
    Result.Ok(Nil)
  }
}

# Usage
let parser = StreamingParser.new
let handler = MemoryMappedProcessor.new("output")
match parser.parse_stream(large_email_string, handler) {
  case Ok(result) -> {
    Stdout.new.print("Processing complete!")
  }
  case Error(e) -> {
    Stderr.new.print("Failed: ${e}")
  }
}
```

---

## Conclusion

This design provides a comprehensive streaming API that:

1. **Reduces memory usage by ~99.86%** for large emails (165MB → 70KB)
2. **Maintains backward compatibility** with existing API
3. **Enables progressive processing** for better user experience
4. **Supports flexible use cases** (file saving, database insertion, scanning)
5. **Provides robust error handling** with multiple recovery strategies
6. **Follows RFC specifications** for email parsing
7. **Leverages Inko's strengths** (ownership, type safety, async processes)

The implementation is divided into **8 phases over 12 weeks**, with clear deliverables and validation criteria at each stage.

### Key Takeaways

- **Streaming is essential** for processing large emails efficiently
- **Callback-based API** provides flexibility without complexity
- **Chunked processing** enables O(1) memory usage
- **Backward compatibility** ensures smooth migration
- **Extensive documentation** and examples will drive adoption

### Next Steps

1. Review and approve this design document
2. Begin Phase 1 implementation
3. Create test email corpus (various sizes, attachment types)
4. Set up benchmarking infrastructure
5. Start with proof-of-concept handler implementations

---

## Appendix

### A. RFC Compliance Checklist

- [ ] RFC 5322: Internet Message Format
  - [ ] Header parsing (streaming)
  - [ ] Body parsing (streaming)
  - [ ] Address list parsing (unchanged)
  - [ ] Date parsing (unchanged)

- [ ] RFC 2045: MIME Part One
  - [ ] Content-Type parsing (unchanged)
  - [ ] Content-Transfer-Encoding (streaming)
  - [ ] Multipart structure (streaming)
  - [ ] Content-ID handling (unchanged)

- [ ] RFC 2046: MIME Part Two
  - [ ] Multipart media types (streaming)
  - [ ] Nested multipart (streaming)
  - [ ] Boundary handling (streaming)

- [ ] RFC 2047: MIME Encoded-Word
  - [ ] Header decoding (unchanged)

- [ ] RFC 2183: Content-Disposition
  - [ ] Disposition parsing (unchanged)
  - [ ] Filename handling (unchanged)

### B. Performance Benchmarks (Expected)

| Email Size | Current Memory | Streaming Memory | Reduction |
|------------|----------------|------------------|-----------|
| 1MB        | ~3MB           | ~70KB            | 97.7%     |
| 10MB       | ~30MB          | ~70KB            | 99.8%     |
| 25MB       | ~80MB          | ~70KB            | 99.9%     |
| 50MB       | ~165MB         | ~70KB            | 99.96%    |

### C. API Comparison

```inko
# Current API (non-streaming)
let parser = EmailParser.new
match parser.parse(raw_email_string) {
  case Ok(message) -> {
    # Full message in memory
    for att in message.attachments.iter {
      # Each attachment fully loaded
      process_attachment(att.content)
    }
  }
  case Error(e) -> { }
}

# Streaming API
let stream_parser = StreamingParser.new
let handler = MyHandler.new
match stream_parser.parse_stream(raw_email_string, handler) {
  case Ok(metadata) -> {
    # Only metadata in memory
    # Content processed via callbacks
  }
  case Error(e) -> { }
}
```

### D. Glossary

- **Chunk**: A fixed-size portion of data processed in one callback call
- **Handler**: An implementation of `StreamHandler` that processes streamed data
- **Attachment**: A file included in an email (image, PDF, etc.)
- **Multipart**: An email structure with multiple parts (text, HTML, attachments)
- **Boundary**: A delimiter separating parts in a multipart email
- **Callback**: A function/method called by the parser to notify of events
- **Progressive processing**: Processing data as it becomes available, not all at once
- **O(1) memory**: Memory usage is constant regardless of input size
- **Base64 expansion**: Base64 encoding increases data size by ~33%
