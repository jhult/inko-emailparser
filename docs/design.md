# Email Parser Design Documentation

This document contains design rationale, trade-offs, security considerations, and RFC references for the email parser implementation.

## Overview

The email parser implements RFC 5322 (Internet Message Format) and RFC 2045 (MIME) to parse raw email messages into structured data. It handles headers, MIME multipart messages, attachments, content transfer encodings, and character set handling.

## Design Principles

1. **Security by Default**: All limits are conservative to prevent DoS attacks
2. **RFC Compliance**: Follows relevant RFCs while being pragmatic about real-world email
3. **Performance**: Limits prevent excessive processing time and memory usage
4. **Pragmatism**: Accepts common non-compliant emails (e.g., LF-only line endings)

## Default Limits and Rationale

### Maximum Email Size: 50 MB

**Function**: `default_max_email_size`

**Rationale**:
- **Gmail limits**: 25 MB for attachments, ~50 MB total message size
- **DoS prevention**: Prevents memory exhaustion from oversized emails
- **Base64 expansion**: 33% overhead for attachments means a 50 MB limit accommodates ~37.5 MB of actual content after encoding
- **Performance**: Larger emails significantly increase processing time
- **Real-world data**: Most legitimate emails are < 10 MB

**RFC Reference**: RFC 5322 does not specify a maximum size

**Security Consideration**: Oversized emails can be used for memory exhaustion attacks. The 50 MB limit balances security with practical needs.

---

### Maximum Attachment Size: 25 MB

**Function**: `default_max_attachment_size`

**Rationale**:
- **Gmail attachment limit**: 25 MB
- **Outlook/O365 attachment limit**: 20-150 MB depending on plan
- **DoS prevention**: Prevents memory exhaustion from large attachments
- **Storage efficiency**: Limits disk usage for parsed emails
- **Base64 overhead**: Accounts for 33% encoding expansion

**RFC Reference**: RFC 2045 section 6.8 (Content-Transfer-Encoding)

**Interaction**: Works with `max_email_size` for overall message limit

**Security Consideration**: Large attachments can exhaust memory and disk space. The 25 MB limit aligns with major email providers.

---

### Maximum Multipart Depth: 10 levels

**Function**: `default_max_multipart_depth`

**Rationale**:
- **Stack overflow prevention**: Limits recursive parsing depth
- **Real-world usage**: Most emails have 2-4 nesting levels max
- **DoS prevention**: Prevents pathological nested multipart attacks
- **Processing time**: O(depth) complexity for nested structures

**Typical Multipart Structure**:
```
multipart/mixed (Level 1: message root)
  ├── multipart/alternative (Level 2: text + HTML)
  │   ├── text/plain
  │   └── multipart/related (Level 3: HTML + inline images)
  │       └── text/html + inline images
  └── attachments (Level 2)
```

**Real-world data**:
- Level 1: `multipart/mixed` (message root)
- Level 2: `multipart/alternative` (text + HTML)
- Level 3: `multipart/related` (HTML + inline images)
- Level 4+: Rarely used

**RFC Reference**: RFC 2046 section 5.1.3 (Nested Multipart)

**Security Consideration**: Deeply nested multipart structures can cause stack overflow. The 10-level limit is far above real-world usage while preventing abuse.

---

### Maximum Header Decoding Iterations: 1000

**Function**: `default_max_header_iterations`

**Rationale**:
- **RFC 2047 encoded-word parsing**: Limits number of encoded words processed
- **DoS prevention**: Prevents infinite loops from pathological inputs
- **Real-world usage**: Most headers have < 50 encoded words
- **Performance**: Each iteration performs string operations and decoding
- **Safety**: Ensures bounded execution time for header parsing

**RFC Reference**: RFC 2047 section 6 (Encoded-Word Syntax)

**Used in**: `decode_header_value_impl()` for RFC 2047 encoded words

**Example pathological case**: Many small encoded words in Subject header

**Security Consideration**: Excessive encoded words can cause CPU exhaustion. The 1000 iteration limit is 20x higher than typical real-world usage.

---

### Maximum Message IDs: 100

**Function**: `default_max_message_ids`

**Rationale**:
- **Threading limits**: Prevents excessive thread ancestry processing
- **Real-world usage**: Typical email threads have < 20 references
- **Industry practice**: Gmail/Outlook cap displayed thread history at reasonable depths
- **DoS prevention**: Prevents abuse via massive References headers
- **Performance**: Each message ID is stored and processed

**RFC Reference**: RFC 5322 section 3.6.4 (Message-ID Header Field)

**Used in**: `parse_message_ids_impl()` for References and In-Reply-To headers

**Example pathological case**: References header with many ancestor message IDs

**Security Consideration**: Massive References headers can be used for memory exhaustion. The 100 limit is 5x higher than typical thread depths.

---

### Maximum Attachments: 100

**Function**: `default_max_attachments`

**Rationale**:
- **Storage limits**: Prevents excessive memory/disk usage
- **Real-world usage**: Most emails have < 10 attachments
- **User experience**: Large attachment lists are rarely useful
- **DoS prevention**: Prevents abuse via many small attachments
- **Processing time**: Each attachment requires decoding and validation

**RFC Reference**: RFC 2045 section 6 (Content-Transfer-Encoding)

**Used in**: `parse_multipart_impl()` to cap attachment count

**Interaction**: `max_attachment_size` limits each attachment's size

**Security Consideration**: Many small attachments can exhaust memory even when individually small. The 100 limit is 10x higher than typical usage.

---

## Line Ending Normalization

**Function**: `normalize_line_endings`

**Design**: RFC 5322 specifies CRLF (`\r\n`) line endings, but we accept LF-only (`\n`) for compatibility with common non-compliant emails.

**Rationale**:
- **Real-world compatibility**: Many systems generate LF-only emails
- **Pragmatism**: Strict RFC compliance would reject valid emails
- **Simplicity**: Normalizing to LF simplifies parsing logic

**Implementation**: Replaces all CRLF sequences with LF before parsing.

---

## Security Considerations

### DoS Prevention

All limits are designed to prevent denial-of-service attacks:

1. **Memory exhaustion**: Size limits prevent loading maliciously large emails
2. **CPU exhaustion**: Iteration limits prevent infinite loops and excessive processing
3. **Stack overflow**: Depth limits prevent pathological recursion

### Memory Management

- **Streaming where possible**: Large attachments are processed without loading entire content
- **Bounded allocations**: All limits ensure bounded memory usage
- **Early validation**: Limits are checked before expensive operations

### Input Validation

- **RFC compliance**: Validates against relevant RFCs
- **Pragmatic acceptance**: Accepts common non-compliant inputs
- **Fail-safe**: Invalid data is rejected rather than causing undefined behavior

---

## RFC Compliance

### Primary RFCs

- **RFC 5322**: Internet Message Format (base email format)
- **RFC 2045**: MIME (Multipurpose Internet Mail Extensions) Part One
- **RFC 2046**: MIME Part Two (Media Types)
- **RFC 2047**: MIME Part Three (Message Header Extensions)
- **RFC 2822**: Obsoleted by RFC 5322 (historical reference)

### Key Sections Implemented

- **RFC 5322 Section 3.6**: Header Field Definitions
  - 3.6.4: Message-ID Header Field
  - 3.6.5: References and In-Reply-To Header Fields
- **RFC 2045 Section 6**: Content-Transfer-Encoding
  - 6.8: Base64 Encoding
  - 6.7: Quoted-Printable Encoding
- **RFC 2046 Section 5.1.3**: Nested Multipart
- **RFC 2047 Section 6**: Encoded-Word Syntax

---

## Performance Considerations

### Complexity Analysis

- **Header parsing**: O(n) where n = header size
- **Multipart parsing**: O(d * m) where d = depth, m = message size
- **Attachment decoding**: O(a) where a = attachment size

### Optimization Strategies

1. **Early termination**: Limits are checked before expensive operations
2. **Single-pass parsing**: Headers and body parsed in one pass
3. **Lazy evaluation**: Some fields computed only when accessed
4. **Memory reuse**: Buffers reused where possible

---

## Trade-offs

### Strictness vs. Compatibility

**Trade-off**: Strict RFC compliance vs. accepting real-world emails

**Decision**: Pragmatic acceptance
- Accept LF-only line endings
- Tolerate minor formatting errors
- Reject only malformed or malicious data

**Rationale**: Strict compliance would reject many legitimate emails from common systems.

### Memory vs. Speed

**Trade-off**: Streaming (slower but memory-efficient) vs. buffering (faster but memory-intensive)

**Decision**: Mixed approach
- Stream large attachments
- Buffer headers and small messages
- Limits ensure bounded memory usage

**Rationale**: Balances performance with resource constraints.

### Security vs. Usability

**Trade-off**: Strict limits (secure but restrictive) vs. permissive limits (usable but risky)

**Decision**: Conservative but practical
- Limits far above real-world usage (10x-20x)
- Aligns with major email providers
- Configurable for specific use cases

**Rationale**: Prevents abuse while accommodating legitimate edge cases.

---

## Future Considerations

### Potential Enhancements

1. **Streaming API**: Incremental parsing for very large emails
2. **Validation modes**: Strict vs. lenient parsing modes
3. **Custom limits**: Per-instance limit configuration
4. **Performance metrics**: Built-in profiling and logging

### Extensibility

- **Custom decoders**: Plugin system for content-transfer encodings
- **Validation hooks**: User-defined validation logic
- **Format converters**: Output to other formats (JSON, XML, etc.)

---

## References

### RFCs

- [RFC 5322](https://www.rfc-editor.org/rfc/rfc5322): Internet Message Format
- [RFC 2045](https://www.rfc-editor.org/rfc/rfc2045): MIME Part One
- [RFC 2046](https://www.rfc-editor.org/rfc/rfc2046): MIME Part Two
- [RFC 2047](https://www.rfc-editor.org/rfc/rfc2047): MIME Part Three

### External Resources

- Gmail attachment limits: https://support.google.com/mail/answer/6584
- Outlook attachment limits: https://support.microsoft.com/en-us/office/attachment-limits-in-outlook-com-2b1ea2a0-c316-4cfc-9f64-a25533af6c7d

---

## Changelog

### Version 0.1.0

- Initial design documentation
- Extracted rationale from inline comments
- Documented all default limits with security considerations
