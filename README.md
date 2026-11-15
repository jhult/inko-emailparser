# inko-emailparser

A comprehensive email parsing library for Inko, implementing RFC 5322 (Internet Message Format) and RFC 2045 (MIME).

## Features

- **RFC 5322 Email Message Parsing**
  - Header parsing (From, To, Cc, Bcc, Subject, Date, Message-ID, etc.)
  - Address list parsing (supports "Name <email>" format, comments, groups)
  - Header folding/unfolding
  - Threading support (In-Reply-To, References)

- **MIME Support (RFC 2045)**
  - Multipart message parsing (multipart/mixed, multipart/alternative, multipart/related)
  - Content-Transfer-Encoding decoding (base64, quoted-printable, 7bit, 8bit)
  - Attachment extraction with Content-Disposition handling
  - Inline image support with Content-ID
  - Nested multipart support (configurable depth)

- **Email Standards**
  - RFC 2047 encoded-word decoding for non-ASCII headers
  - RFC 5322 date formatting
  - RFC 5322 Message-ID generation and validation
  - Content-Type parameter parsing
  - Character set handling

- **Robustness & Security**
  - DoS protection with configurable limits (email size, attachment size, multipart depth)
  - Strict mode for RFC-compliant validation
  - Filename sanitization to prevent path traversal
  - Defensive error handling

## Architecture

The library is organized into modular components with clear separation of concerns:

```
src/emailparser.inko (main entry point)
├── ParserConfig (configuration)
└── EmailParser (public API)
    ├── parse() -> ParsedEmailMessage
    │   ├── parse_headers()
    │   ├── parse_email_addresses()
    │   ├── parse_mime_headers()
    │   └── parse_email_body()
    │
    └── Dependencies:
        ├── header.inko (header parsing)
        │   ├── parse_headers_impl()
        │   ├── parse_content_type_impl()
        │   └── sanitize_filename()
        │
        ├── address.inko (email addresses)
        │   ├── parse_address_list_impl()
        │   ├── remove_comments()
        │   └── is_valid_email_format()
        │
        ├── decoder.inko (content decoding)
        │   ├── decode_body_impl()
        │   ├── decode_quoted_printable()
        │   └── decode_rfc2047_word()
        │
        ├── multipart.inko (MIME parsing)
        │   ├── parse_multipart_impl()
        │   ├── merge_multipart_part()
        │   └── handle_nested_multipart()
        │
        ├── validation.inko (validators)
        │   ├── is_valid_boundary()
        │   ├── is_valid_mime_type()
        │   ├── is_valid_mime_subtype()
        │   ├── is_quoted_string()
        │   └── is_angle_bracketed()
        │
        ├── error.inko (error types)
        │   └── 21 error constructors
        │
        ├── limits.inko (constants)
        │   └── 12 system limits
        │
        └── [supporting modules]
            ├── date.inko (date formatting)
            ├── message_id.inko (Message-ID generation)
            ├── attachment.inko (attachment representation)
            ├── ascii.inko (ASCII character utilities)
            └── hex.inko (hex parsing)
```

### Module Organization

**Core Parsing Modules:**
- `emailparser.inko` - Main parser orchestrating all parsing logic
- `header.inko` - Header field parsing with folding/unfolding
- `address.inko` - Email address parsing (RFC 5322 addr-list)
- `multipart.inko` - Multipart MIME message parsing

**Content Processing:**
- `decoder.inko` - Content-Transfer-Encoding decoding (base64, quoted-printable)
- `validation.inko` - MIME type and boundary validation
- `limits.inko` - Size and count limits for DoS protection

**Supporting Modules:**
- `error.inko` - Typed error handling with 21 error variants and an `ErrorContext` record
- `attachment.inko` - Attachment representation with query methods
- `date.inko` - RFC 5322 date formatting
- `message_id.inko` - Message-ID generation and validation
- `ascii.inko` - ASCII character constants and predicates
- `hex.inko` - Hexadecimal parsing utilities

### Data Flow

```
Raw Email String
    ↓
EmailParser.parse()
    ↓
┌─────────────────────────────────────┐
│ parse_headers()                     │ → Parsed headers
│ parse_email_addresses()             │ → From/To/Cc/Bcc
│ parse_mime_headers()                │ → Content-Type, Encoding
│ parse_email_body()                  │ → Body + Attachments
└─────────────────────────────────────┘
    ↓
ParsedEmailMessage
```

## Installation

```sh
inko pkg add github.com/jhult/inko-emailparser 0.1.0
inko sync
```

## Quick Start

```inko
import emailparser (EmailParser)

let parser = EmailParser.new

match parser.parse(raw_email_string) {
  case Ok(message) -> {
    message.addresses.from.address
    message.addresses.to.get(0).or_panic.address
    message.subject
    message.text_body
  }
  case Error(e) -> {
    # Handle parsing error
  }
}
```

## Usage

### Basic Email Parsing

```inko
import emailparser (EmailParser)

let parser = EmailParser.new

match parser.parse(raw_email_string) {
  case Ok(message) -> {
    message.addresses.from  # EmailAddress
    message.addresses.to    # Array[EmailAddress]
    message.addresses.cc    # Array[EmailAddress]
    message.addresses.bcc   # Array[EmailAddress]
    message.subject         # String
    message.date            # String (RFC 5322 format)
    message.message_id      # String (bracket-free Message-ID)
    message.threading       # ThreadingInfo
    message.mime            # MIMEInfo
    message.text_body       # Option[String]
    message.html_body       # Option[String]
    message.attachments     # Array[EmailAttachment]
  }
  case Error(e) -> {
    # Handle parsing error
  }
}
```

### Configuration Options

Use the per-limit builders when only one or two limits need to change:

```inko
import emailparser (EmailParser)

let parser = EmailParser.new
  .with_max_email_size(100_000_000)
  .with_max_attachment_size(50_000_000)
```

Or configure everything at once with a shared `Limits` value. The same
`Limits` record works for `EmailParser` and `StreamingParser`:

```inko
import emailparser (EmailParser)
import emailparser.limits (Limits)
import emailparser.streaming (StreamingParser)

let limits = Limits(
  max_email_size: 100_000_000,
  max_attachment_size: 50_000_000,
  max_multipart_depth: 15,
  max_attachments: 200,
  max_headers: 2000,
)

let parser = EmailParser.new.with_limits(limits)
let streaming = StreamingParser.new.with_limits(limits)

# Streaming-only setting: bytes delivered per callback. Invalid values
# (zero or negative) are ignored.
let streaming = streaming.with_stream_chunk_size(32_768)
```

### Strict Mode

Enable strict parsing to fail on invalid header formats:

```inko
let parser = EmailParser.new.with_strict_mode(true)

match parser.parse(raw_email_string) {
  case Ok(message) -> {
    # Parsed successfully with strict validation
  }
  case Error(e) -> {
    # Strict mode rejected the email (e.g., malformed headers)
  }
}
```

### Working with Attachments

```inko
import emailparser (EmailParser)

let parser = EmailParser.new

match parser.parse(raw_email_string) {
  case Ok(message) -> {
    for att in message.attachments.iter {
      att.content_type          # String (e.g., "application/pdf")
      att.filename              # Option[String]
      att.content_disposition   # String ("attachment" or "inline")
      att.content_id            # Option[String] (for inline images)
      att.size                  # Int (bytes)
      att.content               # ByteArray
    }
  }
  case Error(e) -> {
    # Handle error
  }
}
```

### Attachment Query Methods

```inko
match att.filename {
  case Some(name) -> name
  case None -> 'unnamed'
}

att.has_filename?     # Bool
att.is_inline?        # Bool (true for inline images)
att.is_attachment?    # Bool (true for regular attachments)
att.is_image?         # Bool (true if content_type starts with "image/")
```

### Email Address Parsing

```inko
import emailparser (EmailParser)

let parser = EmailParser.new

let addrs = parser.parse_address_list(Option.Some('Alice <alice@example.com>, Bob <bob@example.com>'))

for addr in addrs.iter {
  addr.name     # Option[String] (display name)
  addr.address  # String (email address)
  addr.raw      # String (original raw string)
}
```

### Header Decoding (RFC 2047)

```inko
import emailparser (EmailParser)

let parser = EmailParser.new

let decoded = parser.decode_header_value('=?UTF-8?B?SGVsbG8gV29ybGQ=?=')
# Result: "Hello World"
```

### Date Formatting

```inko
import emailparser.date (EmailDateFormatter)
import std.time (DateTime)

let formatter = EmailDateFormatter.new

let now = formatter.format_now
# Result: local time with the system's UTC offset, e.g. "Wed, 15 Jan 2026 14:23:45 -0600"

let custom = formatter.format_datetime(DateTime.local)
# Result: uses the DateTime's own utc_offset

let with_tz = EmailDateFormatter.with_timezone("-0500").format_now
# Result: "Wed, 15 Jan 2026 09:23:45 -0500"
```

### Message-ID Generation

```inko
import emailparser.message_id (MessageIdGenerator)

let generator = MessageIdGenerator.new("example.com")

let msg_id = generator.generate
# Result: "<1736946800.1234567890123456@example.com>"

let with_prefix = generator.generate_with_prefix("user")
# Result: "<user.1736946800.123456789012@example.com>"

let is_valid = generator.is_valid(msg_id)
let local = generator.local_part(msg_id)
let domain = generator.domain_part(msg_id)
```

### Multipart Parsing

```inko
import emailparser (EmailParser)

let parser = EmailParser.new

match parser.parse_multipart(raw_body, "boundary123", "7bit") {
  case Ok((text, html, attachments)) -> {
    text         # Option[String] (text/plain body)
    html         # Option[String] (text/html body)
    attachments  # Array[EmailAttachment]
  }
  case Error(e) -> {
    # Handle error
  }
}
```

### Threading Support

```inko
import emailparser (EmailParser)

let parser = EmailParser.new

match parser.parse(raw_email_string) {
  case Ok(message) -> {
    message.threading.in_reply_to   # Option[String] (Message-ID being replied to)
    message.threading.references    # Array[String] (Message-ID thread chain)
    message.threading.thread_id     # String (computed thread root ID)
  }
  case Error(e) -> {
    # Handle error
  }
}
```

All Message-ID values (`message_id`, `in_reply_to`, `references` and
`thread_id`) are exposed **without surrounding angle brackets**, so they can be
compared directly. A reply's `thread_id` therefore equals the root message's
`message_id`.

## Data Structures

### ParsedEmailMessage

```inko
type pub ParsedEmailMessage {
  let pub @addresses: AddressInfo
  let pub @subject: String
  let pub @date: String
  let pub @message_id: String
  let pub @threading: ThreadingInfo
  let pub @mime: MIMEInfo
  let pub @text_body: Option[String]
  let pub @html_body: Option[String]
  let pub @attachments: Array[EmailAttachment]
  let pub @extra_headers: Array[(String, String)]
  let pub @size: Int
}
```

### EmailAddress

```inko
type pub EmailAddress {
  let pub @name: Option[String]
  let pub @address: String
  let pub @raw: String
}
```

### EmailAttachment

```inko
type pub EmailAttachment {
  let pub @content_type: String
  let pub @filename: Option[String]
  let pub @content_disposition: String
  let pub @content_id: Option[String]
  let pub @size: Int
  let pub @content: ByteArray
}
```

### ParserConfig

```inko
type pub ParserConfig {
  let pub @strict_mode: Bool
  let pub @max_email_size: Int
  let pub @max_attachment_size: Int
  let pub @max_multipart_depth: Int
  let pub @max_attachments: Int
  let pub @max_headers: Int
}
```

## Default Limits

- **max_email_size**: 50 MB (50,000,000 bytes)
- **max_attachment_size**: 25 MB (25,000,000 bytes)
- **max_multipart_depth**: 10 levels
- **max_attachments**: 100 attachments
- **max_headers**: 1000 headers

## Supported Email Features

### Content Types

- `text/plain` - Plain text emails
- `text/html` - HTML emails
- `multipart/alternative` - Text + HTML alternatives
- `multipart/mixed` - Text + attachments
- `multipart/related` - HTML with inline images
- Any other MIME types (treated as attachments)

### Content-Transfer-Encoding

- `7bit` - No encoding (passed through)
- `8bit` - No encoding (passed through)
- `base64` - Base64 decoding
- `quoted-printable` - Quoted-printable decoding

### Address Formats

- Simple: `user@example.com`
- With angle brackets: `<user@example.com>`
- With display name: `John Doe <john@example.com>`
- Quoted display name: `"John Doe" <john@example.com>`
- With comments: `John Doe (personal) <john@example.com>`
- Groups: `team: alice@example.com, bob@example.com;`

### Multipart Structures

- **multipart/alternative**: Alternative representations (text + HTML)
- **multipart/mixed**: Attachments with body
- **multipart/related**: HTML with inline resources (images)
- **Nested multipart**: Any combination of the above

When a message contains more than one `text/plain` part (or more than one
`text/html` part), their bodies are concatenated in the order they appear.

## Error Handling

Parser methods return a typed `emailparser.error.Error` value, so callers can
match on the specific failure instead of inspecting a message string.

### Parse Errors

```inko
import emailparser (EmailParser)
import emailparser.error (Error)

let parser = EmailParser.new

match parser.parse(raw_email_string) {
  case Ok(message) -> {
    # Success
  }
  case Error(e) -> match e {
    case EmailSizeExceeded(_, max_size, actual_size, _, _) -> {
      # Too large: max_size vs actual_size
    }
    case TooManyHeaders(_, count, max_headers, _, _, _) -> {
      # Header limit exceeded
    }
    case BoundaryNotFound(_, _, _, _) -> {
      # Multipart body has no boundary marker
    }
    case _ -> {
      # Every other variant; see Error.variant for the name
    }
  }
}
```

`Error` also exposes helpers that work for every variant:

- `to_message` - rendered message with severity and source location
- `severity` - `Severity.Warning`, `Severity.Error` or `Severity.Fatal`
- `variant` - the variant name as a `String`
- `context` - an `ErrorContext` with `message`, `severity`, `line`,
  `position` and `fragment`

### Strict Mode Errors

```inko
let parser = EmailParser.new.with_strict_mode(true)

match parser.parse(raw_email_string) {
  case Ok(message) -> {
    # Success (RFC compliant)
  }
  case Error(e) -> match e {
    case InvalidHeaderFieldName(_, name, _, _, _) -> {}
    case MalformedHeader(_, reason, _, _, _) -> {}
    case DuplicateHeader(_, name, _, _, _) -> {}
    case HeaderWithoutColon(_, _, _, _) -> {}
    case _ -> {}
  }
}
```

### Streaming Errors

`StreamingParser.parse_stream` and `parse_async_reader` return
`Result[StreamingResult, Error]` as well. The `StreamHandler.on_error`
callback receives `ref Error`, so handlers can inspect it before the parser
returns it to the caller.

## Performance Characteristics

- **O(n) parsing**: Linear time complexity for email size
- **Memory efficient**: Uses ByteArray for binary data
- **DoS protection**: Configurable limits prevent memory exhaustion
- **Lazy decoding**: Headers decoded on access
- **Size validation**: Early rejection of oversized emails

## Benchmarks

The project includes a benchmark suite to measure parsing performance and track regressions.

### Running Benchmarks

```bash
# Run benchmarks, save text results
./test/benchmark/benchmark.sh

# Run with JSON output (for CI regression detection)
./test/benchmark/benchmark.sh --json
```

This will:
1. Run the full benchmark suite
2. Save text results with timestamp to `test/benchmark/results/benchmark_YYYYMMDD_HHMMSS.txt`
3. Create a symlink at `test/benchmark/results/latest.txt` for easy access
4. With `--json`, save machine-readable results to `test/benchmark/results/benchmark-latest.json`

### Benchmark Categories

The benchmark suite tests:

- **Simple email parsing** (1000 iterations)
- **Multipart parsing** (500 iterations)
- **Base64 decoding** (1000 iterations)
- **Quoted-printable decoding** (1000 iterations)
- **Header parsing** (10000 iterations)
- **Address parsing** (5000 iterations)

### Comparing Results

To compare benchmark results between runs:

```bash
diff test/benchmark/results/latest.txt test/benchmark/results/benchmark_PREVIOUS_TIMESTAMP.txt
```

This helps identify performance regressions or improvements after code changes.

### Manual Benchmark Execution

You can also run benchmarks directly:

```bash
cd test/benchmark
inko run benchmark_bench.inko
```

Note: The benchmark suite measures relative performance. Due to Inko's type system limitations, exact timing values are not displayed, but the benchmarks complete successfully and can be used to compare relative performance between code versions.

## Modules

- `emailparser` - Main email parser with EmailParser type
- `emailparser.date` - RFC 5322 date formatting (EmailDateFormatter)
- `emailparser.message_id` - Message-ID generation (MessageIdGenerator)
- `emailparser.address` - Email address parsing (EmailAddress)
- `emailparser.attachment` - Attachment representation (EmailAttachment)
- `emailparser.error` - Error types (`Error`, `Severity`, `ErrorContext`) for parsing failures

## RFC Compliance

- **RFC 5322**: Internet Message Format
- **RFC 2045**: MIME (Multipurpose Internet Mail Extensions) Part One
- **RFC 2046**: MIME Part Two: Media Types
- **RFC 2047**: MIME Encoded-Word for Non-ASCII Text
- **RFC 2183**: Content-Disposition header

## License

[Mozilla Public License 2.0](LICENSE)

## Contributing

This is a single-developer project maintained for personal use. While the 
code is open source (MPL 2.0), external contributions are not accepted.

If you use this project and find bugs, feel free to file issues. Pull 
requests will not be merged.
