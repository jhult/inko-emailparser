# Streaming API Migration Guide

This guide helps you migrate from the non-streaming `EmailParser` to the streaming `StreamingParser`. It covers when to use streaming, how to convert existing code, performance trade-offs, and real-world examples.

## Table of Contents

1. [When to Use Streaming](#when-to-use-streaming)
2. [Performance Trade-offs](#performance-trade-offs)
3. [Migration Steps](#migration-steps)
4. [Common Migration Patterns](#common-migration-patterns)
5. [Real-World Examples](#real-world-examples)
6. [Troubleshooting](#troubleshooting)

---

## When to Use Streaming

### Decision Flowchart

```
Email size < 10MB?
  ├─ Yes → Use EmailParser (non-streaming)
  └─ No → Need all parts in memory?
           ├─ Yes → Use EmailParser (if RAM available)
           └─ No → Use StreamingParser
```

### Use StreamingParser When

| Scenario | Reason |
|----------|---------|
| **Emails > 10MB** | Significant memory savings |
| **Memory-constrained environments** | Embedded systems, cloud functions |
| **Processing attachments to disk** | Don't need attachment in memory |
| **Scanning for content** | Can abort early (e.g., malware detection) |
| **Streaming to database** | Insert chunks as they arrive |
| **Processing many emails concurrently** | Lower per-email memory footprint |

### Use EmailParser When

| Scenario | Reason |
|----------|---------|
| **Emails < 10MB** | Simpler API, no streaming overhead |
| **Need random access** | Revisit parts multiple times |
| **Simple use cases** | Extract text/HTML, skip attachments |
| **Development/testing** | Easier debugging |
| **Memory not constrained** | Plenty of RAM available |

### Email Size Guidelines

| Email Size | Recommended API | Peak Memory |
|------------|------------------|--------------|
| < 1MB | EmailParser | ~3MB |
| 1-10MB | Either | ~3-30MB (EmailParser) or ~70KB (Streaming) |
| 10-50MB | StreamingParser | ~30-165MB (EmailParser) or ~70KB (Streaming) |
| > 50MB | StreamingParser | Out of memory (EmailParser) or ~70KB (Streaming) |

**Note**: These are rough estimates. Actual memory depends on:
- Number and size of attachments
- Encoding type (Base64 expands 33%)
- Multipart nesting depth

---

## Performance Trade-offs

### Memory Usage

**EmailParser (non-streaming)**:
- Loads entire email into memory
- Decodes all attachments at once
- Peak memory = Raw email + Decoded attachments
- Formula: ~1.5 × Raw size (with Base64 attachments)

**StreamingParser**:
- Processes in configurable chunks (default 64KB)
- Decodes incrementally
- Peak memory = Chunk size + Handler state
- Formula: ~64KB + Handler state

**Example** (50MB email with 3 × 15MB Base64 attachments):
- EmailParser: ~165MB peak memory
- StreamingParser: ~70KB peak memory
- **Reduction: 99.96%**

### Processing Time

**EmailParser**:
- Faster for small emails (< 10MB)
- Single-pass decode of entire bodies
- No callback overhead

**StreamingParser**:
- ~25-50% slower (depends on chunk size)
- Multiple callback invocations
- Chunk boundary handling overhead

**Benchmark results** (10MB email with Base64 attachment):
- EmailParser: ~120ms
- StreamingParser: ~150ms (25% overhead)

**Trade-off summary**:
| Aspect | EmailParser | StreamingParser |
|---------|-------------|-----------------|
| Memory | O(n) | O(1) |
| Time | Fastest | +25-50% slower |
| Random access | Yes | No |
| Early abort | No | Yes |
| Complexity | Low | Medium |

### Callback Overhead

Streaming invokes callbacks for each chunk. Overhead depends on chunk size:

| Chunk Size | Callbacks (10MB attachment) | Total Overhead |
|------------|----------------------------|----------------|
| 8KB | ~1536 | ~15ms |
| 64KB | ~192 | ~2ms |
| 256KB | ~48 | ~0.5ms |
| 1MB | ~12 | ~0.1ms |

**Recommendation**: Use larger chunks (64KB - 1MB) to reduce overhead unless you need low-latency processing.

---

## Migration Steps

### Step 1: Analyze Your Current Code

Identify what you do with parsed emails:

```inko
# Current code with EmailParser
let parser = EmailParser.new
match parser.parse(email_string) {
  case Ok(message) -> {
    # What do you do with message?
    
    # 1. Extract text body?
    match message.text_body {
      case Some(text) -> process_text(text)
      case None -> {}
    }
    
    # 2. Extract HTML body?
    match message.html_body {
      case Some(html) -> process_html(html)
      case None -> {}
    }
    
    # 3. Process attachments?
    for att in message.attachments.iter {
      # Do you store to disk? Database? Scan?
      save_attachment(att.filename, att.content)
    }
    
    # 4. Just need metadata?
    let subject = message.subject
    let from = message.from
  }
  case Error(e) -> handle_error(e)
}
```

**Key questions**:
1. Do you need the full email in memory?
2. Do you revisit parts multiple times?
3. What do you do with attachments?
4. Do you need to abort early?

### Step 2: Create a StreamHandler

Define a handler that performs the same operations as your current code:

```inko
import emailparser.streaming (StreamHandler, AttachmentInfo)

type MyHandler {
  let mut @text_body: String
  let mut @html_body: String
  let mut @attachment_count: Int
}

impl StreamHandler for MyHandler {
  fn pub mut on_begin -> Result[Int, String] {
    @text_body = ''
    @html_body = ''
    @attachment_count = 0
    Result.Ok(0)
  }
  
  fn pub mut on_text_chunk(chunk: String) -> Result[Int, String] {
    @text_body = @text_body + chunk
    Result.Ok(0)
  }
  
  fn pub mut on_html_chunk(chunk: String) -> Result[Int, String] {
    @html_body = @html_body + chunk
    Result.Ok(0)
  }
  
  fn pub mut on_attachment_begin(info: ref AttachmentInfo) -> Result[Int, String] {
    # Prepare for attachment (e.g., open file)
    prepare_attachment(info.filename)
    Result.Ok(0)
  }
  
  fn pub mut on_attachment_chunk(
    chunk: ByteArray,
    info: ref AttachmentInfo,
  ) -> Result[Int, String] {
    # Write chunk to file/database
    write_attachment_chunk(info.filename, chunk)
    Result.Ok(0)
  }
  
  fn pub mut on_attachment_end(info: ref AttachmentInfo) -> Result[Int, String] {
    # Finalize attachment (e.g., close file)
    finalize_attachment(info.filename)
    @attachment_count = @attachment_count + 1
    Result.Ok(0)
  }
  
  fn pub mut on_end -> Result[Int, String] {
    # Do post-processing with @text_body, @html_body
    Result.Ok(0)
  }
  
  fn pub mut on_headers(headers: ref Array[(String, String)]) -> Result[Int, String] {
    # If you need headers, process them here
    Result.Ok(0)
  }
  
  fn pub mut on_error(error: String) -> Result[Int, String] {
    # Log error
    log_error(error)
    Result.Ok(0)
  }
}
```

### Step 3: Replace Parser Call

```inko
# Old code:
let parser = EmailParser.new
match parser.parse(email_string) {
  case Ok(message) -> {
    # Process message
  }
  case Error(e) -> handle_error(e)
}

# New code:
let parser = StreamingParser.new
let handler = MyHandler.new
match parser.parse_stream(email_string, handler) {
  case Ok(result) -> {
    # result contains metadata (subject, from, etc.)
    # Content was processed via callbacks
  }
  case Error(e) -> handle_error(e)
}
```

### Step 4: Adjust for Streaming Characteristics

**Difference 1: No `ParsedEmailMessage`**

Streaming returns `StreamingResult` (metadata only), not full message:

```inko
# Old:
match message.text_body {
  case Some(text) -> process(text)
  case None -> {}
}

# New: Text body built in handler
process(handler.text_body)
```

**Difference 2: Attachments not in result**

Attachment metadata is delivered via callbacks:

```inko
# Old:
for att in message.attachments.iter {
  save_attachment(att.filename, att.content)
}

# New: Save incrementally in callbacks
fn pub mut on_attachment_chunk(
  chunk: ByteArray,
  info: ref AttachmentInfo,
) -> Result[Int, String] {
  save_chunk(info.filename, chunk)
  Result.Ok(0)
}
```

**Difference 3: Callbacks can fail**

If a callback returns `Result.Error`, parsing stops:

```inko
fn pub mut on_attachment_chunk(
  chunk: ByteArray,
  info: ref AttachmentInfo,
) -> Result[Int, String] {
  match save_chunk(info.filename, chunk) {
    case Ok(_) -> Result.Ok(0)
    case Error(e) -> Result.Error("Failed to save: ${e}")
  }
}
```

### Step 5: Validate

1. **Unit tests**: Ensure same results for small emails
2. **Integration tests**: Verify behavior with attachments
3. **Memory profiling**: Confirm reduced memory usage
4. **Performance benchmarking**: Check acceptable overhead

---

## Common Migration Patterns

### Pattern 1: Save Attachments to Disk

**Old code (EmailParser)**:

```inko
let parser = EmailParser.new
match parser.parse(email_string) {
  case Ok(message) -> {
    for att in message.attachments.iter {
      match att.filename {
        case Some(name) -> {
          let path = "attachments/${name}"
          match File.new(path) {
            case Ok(file) -> {
              file.write_bytes(att.content)
              file.flush
            }
            case Error(e) -> handle_error(e)
          }
        }
        case None -> {}
      }
    }
  }
  case Error(e) -> handle_error(e)
}
```

**New code (StreamingParser)**:

```inko
import std.fs.file (File)

type AttachmentSaver {
  let mut @current_file: Option[File]
}

impl StreamHandler for AttachmentSaver {
  fn pub mut on_attachment_begin(info: ref AttachmentInfo) -> Result[Int, String] {
    match info.filename {
      case Some(name) -> {
        let path = "attachments/${name}"
        match File.new(path) {
          case Ok(file) -> {
            @current_file = Option.Some(file)
            Result.Ok(0)
          }
          case Error(e) -> Result.Error(e.to_string)
        }
      }
      case None -> Result.Ok(0)
    }
  }
  
  fn pub mut on_attachment_chunk(
    chunk: ByteArray,
    info: ref AttachmentInfo,
  ) -> Result[Int, String] {
    match @current_file {
      case Some(ref mut file) -> {
        match file.write_bytes(chunk) {
          case Ok(_) -> Result.Ok(0)
          case Error(e) -> Result.Error(e.to_string)
        }
      }
      case None -> Result.Ok(0)
    }
  }
  
  fn pub mut on_attachment_end(info: ref AttachmentInfo) -> Result[Int, String] {
    match @current_file {
      case Some(ref mut file) -> {
        match file.flush {
          case Ok(_) -> Result.Ok(0)
          case Error(e) -> Result.Error(e.to_string)
        }
      }
      case None -> Result.Ok(0)
    }
    @current_file = Option.None
    Result.Ok(0)
  }
  
  # ... other callbacks
}

let parser = StreamingParser.new
let handler = AttachmentSaver.new
match parser.parse_stream(email_string, handler) {
  case Ok(result) -> {}
  case Error(e) -> handle_error(e)
}
```

**Benefits**:
- Peak memory: ~70KB instead of attachment size
- Can handle arbitrarily large attachments
- Disk I/O happens during parsing (pipelined)

### Pattern 2: Insert Attachments to Database

**Old code (EmailParser)**:

```inko
let parser = EmailParser.new
match parser.parse(email_string) {
  case Ok(message) -> {
    let msg_id = db.insert_message(
      message.subject,
      message.from.address,
      message.text_body,
      message.html_body,
    )
    
    for att in message.attachments.iter {
      db.insert_attachment(msg_id, att.filename, att.content)
    }
  }
  case Error(e) -> handle_error(e)
}
```

**New code (StreamingParser)**:

```inko
type DatabaseInserter {
  let @db: DatabaseConnection
  let mut @current_msg_id: Option[Int]
  let mut @current_att_id: Option[Int]
  let mut @chunk_index: Int
}

impl StreamHandler for DatabaseInserter {
  fn pub mut on_headers(headers: ref Array[(String, String)]) -> Result[Int, String] {
    let subject = get_header_value(headers, 'Subject')
    let from = get_header_value(headers, 'From')
    @current_msg_id = Option.Some(@db.insert_message(subject, from))
    Result.Ok(0)
  }
  
  fn pub mut on_text_chunk(chunk: String) -> Result[Int, String] {
    match @current_msg_id {
      case Some(id) -> {
        @db.append_text_chunk(id, chunk)
        Result.Ok(0)
      }
      case None -> Result.Ok(0)
    }
  }
  
  fn pub mut on_attachment_begin(info: ref AttachmentInfo) -> Result[Int, String] {
    @chunk_index = 0
    match @current_msg_id {
      case Some(msg_id) -> {
        let att_id = @db.insert_attachment(
          msg_id,
          info.filename,
          info.content_type,
          info.size,
        )
        @current_att_id = Option.Some(att_id)
        Result.Ok(0)
      }
      case None -> Result.Ok(0)
    }
  }
  
  fn pub mut on_attachment_chunk(
    chunk: ByteArray,
    info: ref AttachmentInfo,
  ) -> Result[Int, String] {
    match @current_att_id {
      case Some(att_id) -> {
        @db.insert_attachment_chunk(att_id, @chunk_index, chunk)
        @chunk_index = @chunk_index + 1
        Result.Ok(0)
      }
      case None -> Result.Ok(0)
    }
  }
  
  fn pub mut on_attachment_end(info: ref AttachmentInfo) -> Result[Int, String] {
    match @current_att_id {
      case Some(att_id) -> {
        @db.finalize_attachment(att_id)
        @current_att_id = Option.None
        Result.Ok(0)
      }
      case None -> Result.Ok(0)
    }
    Result.Ok(0)
  }
  
  # ... other callbacks
}
```

**Benefits**:
- No need to load full attachments into application memory
- Database manages buffering
- Parallel inserts possible (with connection pooling)

### Pattern 3: Scan for Malware/Content

**Old code (EmailParser)**:

```inko
let parser = EmailParser.new
match parser.parse(email_string) {
  case Ok(message) -> {
    for att in message.attachments.iter {
      if scan_for_malware(att.content) {
        reject_email("Malware detected")
        return
      }
    }
    accept_email
  }
  case Error(e) -> handle_error(e)
}
```

**New code (StreamingParser)**:

```inko
type MalwareScanner {
  let mut @found_malware: Bool
}

impl StreamHandler for MalwareScanner {
  fn pub mut on_attachment_chunk(
    chunk: ByteArray,
    info: ref AttachmentInfo,
  ) -> Result[Int, String] {
    if @found_malware {
      return Result.Error("Malware detected, aborting")
    }
    
    if scan_for_malware(chunk) {
      @found_malware = true
      return Result.Error("Malware detected in attachment")
    }
    
    Result.Ok(0)
  }
  
  # Skip other callbacks (don't store content)
  fn pub mut on_text_chunk(chunk: String) -> Result[Int, String] {
    Result.Ok(0)
  }
  
  fn pub mut on_html_chunk(chunk: String) -> Result[Int, String] {
    Result.Ok(0)
  }
  
  # ... stub implementations for other callbacks
}

let parser = StreamingParser.new
let handler = MalwareScanner.new
match parser.parse_stream(email_string, handler) {
  case Ok(result) -> accept_email
  case Error(e) -> reject_email(e)
}
```

**Benefits**:
- Early abort: Stop scanning as soon as malware found
- Low memory: Only current chunk in memory
- Fast: Don't need to download/store entire attachment

### Pattern 4: Extract Metadata Only

**Old code (EmailParser)**:

```inko
let parser = EmailParser.new
match parser.parse(email_string) {
  case Ok(message) -> {
    let metadata = EmailMetadata(
      subject: message.subject,
      from: message.from.address,
      to: message.to.map(|addr| addr.address),
      date: message.date,
      attachment_count: message.attachments.size,
    )
    save_metadata(metadata)
  }
  case Error(e) -> handle_error(e)
}
```

**New code (StreamingParser)**:

```inko
type MetadataExtractor {
  let mut @metadata: Option[EmailMetadata]
}

impl StreamHandler for MetadataExtractor {
  fn pub mut on_headers(headers: ref Array[(String, String)]) -> Result[Int, String] {
    let subject = get_header_value(headers, 'Subject')
    let from = get_header_value(headers, 'From')
    let to = get_header_values(headers, 'To')
    let date = get_header_value(headers, 'Date')
    
    @metadata = Option.Some(EmailMetadata(
      subject: subject,
      from: from,
      to: to,
      date: date,
      attachment_count: 0,
    ))
    Result.Ok(0)
  }
  
  fn pub mut on_attachment_begin(info: ref AttachmentInfo) -> Result[Int, String] {
    match @metadata {
      case Some(ref mut m) -> {
        m.attachment_count = m.attachment_count + 1
      }
      case None -> {}
    }
    Result.Ok(0)
  }
  
  # Skip all content callbacks
  fn pub mut on_text_chunk(chunk: String) -> Result[Int, String] {
    Result.Ok(0)
  }
  
  fn pub mut on_html_chunk(chunk: String) -> Result[Int, String] {
    Result.Ok(0)
  }
  
  fn pub mut on_attachment_chunk(
    chunk: ByteArray,
    info: ref AttachmentInfo,
  ) -> Result[Int, String] {
    # Don't store attachment content
    Result.Ok(0)
  }
  
  fn pub mut on_end -> Result[Int, String] {
    match @metadata {
      case Some(m) -> save_metadata(m)
      case None -> {}
    }
    Result.Ok(0)
  }
  
  # ... other callbacks
}

let parser = StreamingParser.new
let handler = MetadataExtractor.new
match parser.parse_stream(email_string, handler) {
  case Ok(result) -> {
    # result also contains metadata
    # or use handler.metadata
  }
  case Error(e) -> handle_error(e)
}
```

**Benefits**:
- Minimal memory: Only metadata in memory
- Fast: No content processing
- Scalable: Can process thousands of emails concurrently

---

## Real-World Examples

### Example 1: Email Migration Service

**Scenario**: Migrate millions of emails from old server to new one.

**Requirements**:
- Process 10M emails (avg 5MB, some 50MB)
- Store metadata in database
- Save attachments to object storage (S3)
- Parallel processing

**Solution**: Use StreamingParser with parallel workers.

```inko
type async MigrationWorker {
  fn async process_email(email_string: String) -> Result[Nil, String] {
    let parser = StreamingParser.new
    let handler = MigrationHandler.new(db_connection, s3_client)
    
    match parser.parse_stream(email_string, handler) {
      case Ok(_) -> Result.Ok(Nil)
      case Error(e) -> Result.Error(e)
    }
  }
}

type MigrationHandler {
  let @db: DatabaseConnection
  let @s3: S3Client
  let mut @current_msg_id: Option[Int]
  let mut @current_s3_key: Option[String]
  let mut @s3_buffer: ByteArray
}

impl StreamHandler for MigrationHandler {
  fn pub mut on_headers(headers: ref Array[(String, String)]) -> Result[Int, String] {
    let msg_id = @db.insert_email(headers)
    @current_msg_id = Option.Some(msg_id)
    Result.Ok(0)
  }
  
  fn pub mut on_attachment_begin(info: ref AttachmentInfo) -> Result[Int, String] {
    let s3_key = "emails/${@current_msg_id}/${info.filename}"
    @current_s3_key = Option.Some(s3_key)
    @s3_buffer = recover ByteArray.new
    Result.Ok(0)
  }
  
  fn pub mut on_attachment_chunk(
    chunk: ByteArray,
    info: ref AttachmentInfo,
  ) -> Result[Int, String] {
    @s3_buffer.append(chunk)
    # Upload in 1MB batches to reduce S3 API calls
    if @s3_buffer.size >= 1_048_576 {
      match @current_s3_key {
        case Some(key) -> {
          match @s3.upload_part(key, @s3_buffer) {
            case Ok(_) -> @s3_buffer = recover ByteArray.new
            case Error(e) -> return Result.Error(e.to_string)
          }
        }
        case None -> {}
      }
    }
    Result.Ok(0)
  }
  
  fn pub mut on_attachment_end(info: ref AttachmentInfo) -> Result[Int, String] {
    match @current_s3_key {
      case Some(key) -> {
        # Upload final part
        if @s3_buffer.size > 0 {
          match @s3.upload_part(key, @s3_buffer) {
            case Ok(_) -> @s3.finalize_upload(key)
            case Error(e) -> return Result.Error(e.to_string)
          }
        }
      }
      case None -> {}
    }
    Result.Ok(0)
  }
  
  # ... other callbacks
}
```

**Benefits**:
- Can handle 50MB emails with <100MB memory per worker
- Uploads in parallel with parsing (pipelining)
- 1000+ workers possible on single machine

### Example 2: Email Gateway with Malware Scanning

**Scenario**: Scan incoming emails for malware before delivery.

**Requirements**:
- Scan attachments incrementally
- Abort immediately if malware found
- Clean emails delivered immediately
- Process 10K emails/hour

**Solution**: Use StreamingParser with early abort.

```inko
type MalwareGatewayHandler {
  let @scanner: MalwareScanner
  let mut @found_threat: Bool
}

impl StreamHandler for MalwareGatewayHandler {
  fn pub mut on_attachment_chunk(
    chunk: ByteArray,
    info: ref AttachmentInfo,
  ) -> Result[Int, String] {
    if @found_threat {
      return Result.Error("Threat detected, aborting")
    }
    
    match @scanner.scan(chunk) {
      case Ok(result) -> {
        if result.threat_found {
          @found_threat = true
          log_threat(info.filename, result.threat_name)
          return Result.Error("Malware detected")
        }
        Result.Ok(0)
      }
      case Error(e) -> Result.Error("Scan failed: ${e}")
    }
  }
  
  # ... stub for other callbacks
}

fn process_incoming_email(email_string: String) -> DeliveryDecision {
  let parser = StreamingParser.new
  let handler = MalwareGatewayHandler.new
  
  match parser.parse_stream(email_string, handler) {
    case Ok(result) -> {
      DeliveryDecision.Accept(result)
    }
    case Error(e) -> {
      if e.contains?("Malware detected") {
        DeliveryDecision.Reject("Malware found")
      } else {
        DeliveryDecision.Quarantine("Scan error: ${e}")
      }
    }
  }
}
```

**Benefits**:
- Early abort: Don't need to download entire attachment
- Low latency: Detect malware in first chunk
- Memory efficient: Only current chunk in scanner

### Example 3: Email Analytics Pipeline

**Scenario**: Extract analytics from email corpus.

**Requirements**:
- Extract text bodies for NLP processing
- Count attachment types/sizes
- Don't store original attachments
- Process 1M+ emails

**Solution**: Use StreamingParser with in-memory text buffering only.

```inko
type AnalyticsHandler {
  let mut @text_bodies: Array[(Int, String)]  # (email_id, text)
  let mut @attachment_stats: Array[(Int, String, Int)]  # (email_id, type, size)
  let mut @current_email_id: Int
  let mut @current_attachment_size: Int
}

impl StreamHandler for AnalyticsHandler {
  fn pub mut on_headers(headers: ref Array[(String, String)]) -> Result[Int, String] {
    @current_email_id = get_email_id(headers)
    Result.Ok(0)
  }
  
  fn pub mut on_text_chunk(chunk: String) -> Result[Int, String] {
    let mut found = false
    let mut i = 0
    while i < @text_bodies.size {
      match @text_bodies.get(i) {
        case Ok((id, _)) -> {
          if id == @current_email_id {
            @text_bodies[i] = (id, @text_bodies[i].1 + chunk)
            found = true
            break
          }
        }
        case Error(_) -> {}
      }
      i = i + 1
    }
    
    if !found {
      @text_bodies.push((@current_email_id, chunk))
    }
    
    Result.Ok(0)
  }
  
  fn pub mut on_attachment_begin(info: ref AttachmentInfo) -> Result[Int, String] {
    @current_attachment_size = 0
    Result.Ok(0)
  }
  
  fn pub mut on_attachment_chunk(
    chunk: ByteArray,
    info: ref AttachmentInfo,
  ) -> Result[Int, String] {
    @current_attachment_size = @current_attachment_size + chunk.size
    Result.Ok(0)
  }
  
  fn pub mut on_attachment_end(info: ref AttachmentInfo) -> Result[Int, String] {
    @attachment_stats.push((
      @current_email_id,
      info.content_type,
      @current_attachment_size,
    ))
    Result.Ok(0)
  }
  
  fn pub mut on_end -> Result[Int, String] {
    # Process analytics
    run_nlp(@text_bodies)
    calculate_statistics(@attachment_stats)
    Result.Ok(0)
  }
  
  # ... other callbacks
}
```

**Benefits**:
- Store only text bodies (typically <10KB each)
- Attachment statistics only (no content stored)
- Can process 1M emails with <10GB memory

---

## Troubleshooting

### Issue: Handler Callback Not Called

**Symptoms**: Callbacks not executing, parsing succeeds anyway.

**Cause**: Missing or incorrect callback implementation.

**Solution**: Implement all required callbacks:

```inko
impl StreamHandler for MyHandler {
  fn pub mut on_begin -> Result[Int, String] { Result.Ok(0) }
  fn pub mut on_headers(headers: ref Array[(String, String)]) -> Result[Int, String] { Result.Ok(0) }
  fn pub mut on_text_chunk(chunk: String) -> Result[Int, String] { Result.Ok(0) }
  fn pub mut on_html_chunk(chunk: String) -> Result[Int, String] { Result.Ok(0) }
  fn pub mut on_attachment_begin(info: ref AttachmentInfo) -> Result[Int, String] { Result.Ok(0) }
  fn pub mut on_attachment_chunk(chunk: ByteArray, info: ref AttachmentInfo) -> Result[Int, String] { Result.Ok(0) }
  fn pub mut on_attachment_end(info: ref AttachmentInfo) -> Result[Int, String] { Result.Ok(0) }
  fn pub mut on_end -> Result[Int, String] { Result.Ok(0) }
  fn pub mut on_error(error: String) -> Result[Int, String] { Result.Ok(0) }
}
```

### Issue: Incomplete Attachment Data

**Symptoms**: Attachment chunks don't match expected size.

**Cause**: Not calling `decoder.finish()` after last chunk.

**Solution**: StreamingParser handles this automatically. If implementing custom decoder:

```inko
# After all chunks processed
match decoder.finish {
  case Ok(final_chunk) -> {
    # Process final chunk
  }
  case Error(e) -> {
    # Handle error
  }
}
```

### Issue: High Memory Usage

**Symptoms**: StreamingParser still uses significant memory.

**Cause**: Handler buffers all content.

**Solution**: Process chunks immediately, don't buffer:

```inko
# Bad: Buffering all data
type BadHandler {
  let mut @all_attachments: Array[(String, ByteArray)]
}

fn pub mut on_attachment_chunk(chunk: ByteArray, info: ref AttachmentInfo) -> Result[Int, String] {
  @all_attachments.push((info.filename, chunk))
  Result.Ok(0)
}

# Good: Streaming to file
type GoodHandler {
  let mut @current_file: Option[File]
}

fn pub mut on_attachment_chunk(chunk: ByteArray, info: ref AttachmentInfo) -> Result[Int, String] {
  match @current_file {
    case Some(ref mut file) -> {
      file.write_bytes(chunk)
      Result.Ok(0)
    }
    case None -> Result.Ok(0)
  }
}
```

### Issue: Parser Aborts Early

**Symptoms**: Parsing stops with error before complete.

**Cause**: Handler callback returns `Result.Error`.

**Solution**: Return `Result.Ok(0)` unless you want to abort:

```inko
fn pub mut on_attachment_chunk(chunk: ByteArray, info: ref AttachmentInfo) -> Result[Int, String] {
  match process_chunk(chunk) {
    case Ok(_) -> Result.Ok(0)
    case Error(e) -> {
      # Option 1: Abort parsing
      # Result.Error(e)
      
      # Option 2: Continue (recommended for non-critical errors)
      log_error(e)
      Result.Ok(0)
    }
  }
}
```

### Issue: Performance Slower Than Expected

**Symptoms**: StreamingParser significantly slower than EmailParser.

**Cause**: Small chunk size or expensive callback logic.

**Solution 1**: Increase chunk size:

```inko
let config = StreamingConfig.new
config.stream_chunk_size = 262144  # 256KB
let parser = StreamingParser.with_config(config)
```

**Solution 2**: Optimize callback logic:

```inko
# Bad: Expensive operation in callback
fn pub mut on_attachment_chunk(chunk: ByteArray, info: ref AttachmentInfo) -> Result[Int, String] {
  for byte in chunk.iter {  # Very slow
    process_byte(byte)
  }
  Result.Ok(0)
}

# Good: Use efficient operations
fn pub mut on_attachment_chunk(chunk: ByteArray, info: ref AttachmentInfo) -> Result[Int, String] {
  write_to_file(chunk)  # Batch operation
  Result.Ok(0)
}
```

---

## Checklist

Before deploying streaming to production:

- [ ] Identified emails that benefit from streaming (size > 10MB)
- [ ] Created appropriate `StreamHandler` implementation
- [ ] Verified handler doesn't buffer all content (unless required)
- [ ] Set appropriate configuration (chunk_size, max_sizes)
- [ ] Added error handling for callback failures
- [ ] Tested with real-world emails (small and large)
- [ ] Profiled memory usage (confirm reduction)
- [ ] Benchmarked performance (acceptable overhead?)
- [ ] Updated monitoring/alerting for new patterns
- [ ] Documented migration for team

---

## Resources

- [Streaming API Design](./streaming-api.md)
- [Streaming Implementation](./streaming-implementation.md)
- [Source Code](../src/emailparser/streaming.inko)
- [Example Handlers](../test/emailparser/test_streaming_integration.inko)
