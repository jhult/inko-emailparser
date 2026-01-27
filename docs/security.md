# Security Policy

## Supported Versions

Currently, only the latest version of inko-emailparser is supported. Security updates will be provided for the latest release.

| Version | Supported |
|---------|-----------|
| Latest  | Yes       |

## Security Considerations

Email parsing can expose applications to various security threats. This library implements several defenses against common attacks, but users should understand the risks and limitations.

### Known Security Risks

1. **Memory Exhaustion**: Malicious emails can be crafted to consume excessive memory through large attachments or deeply nested multipart structures
2. **CPU Exhaustion**: Complex encoding schemes and deeply nested structures can cause high CPU usage
3. **Path Traversal**: Attachment filenames may contain directory traversal attempts
4. **MIME Parsing**: Improperly validated MIME headers can lead to parsing vulnerabilities
5. **Encoding Attacks**: Malformed base64 or quoted-printable encoding can cause parser instability

### Implemented Security Measures

This library includes the following built-in protections:

#### Size Limits

- **`max_email_size`**: Default 50 MB - Limits total email size to prevent memory exhaustion
- **`max_attachment_size`**: Default 25 MB - Limits individual attachment size

```inko
let parser = EmailParser.with_limits(
  max_email_size: 100_000_000,      # 100 MB
  max_attachment_size: 50_000_000,  # 50 MB
  max_multipart_depth: 10
)
```

#### Depth and Iteration Limits

- **`max_multipart_depth`**: Default 10 levels - Prevents stack overflow from deeply nested multipart messages
- **`max_header_iterations`**: Default 1000 iterations - Limits RFC 2047 header decoding iterations
- **`max_message_ids`**: Default 100 message IDs - Limits parsing of References/In-Reply-To headers

#### Filename Sanitization

The `sanitize_filename` function protects against path traversal attacks by:

- Rejecting filenames containing `..` (parent directory traversal)
- Rejecting path separators (`/` and `\`)
- Rejecting null bytes and control characters (ASCII 0-31)
- Limiting filename length to 255 characters
- Requiring at least one printable character

```inko
# Automatically applied when parsing attachments
case Some(f) -> sanitize_filename(f)
```

#### Input Validation

- Email size validation before parsing begins
- Attachment size validation during decoding
- Boundary string validation for multipart messages
- Header folding/unfolding with iteration limits

## Security Best Practices for Users

### 1. Always Validate Email Sources

Never trust emails from untrusted sources without additional validation:

```inko
match parser.parse(raw_email) {
  case Ok(message) => {
    # Validate sender and content before processing
    if is_trusted_sender(message.from) {
      process_email(message)
    }
  }
  case Error(e) => {
    # Log and reject malformed emails
    log_error("Email parsing failed: " + e)
  }
}
```

### 2. Use Appropriate Limits

Adjust limits based on your use case:

- For web applications: Lower limits (e.g., 10-25 MB)
- For batch processing: Higher limits with timeouts
- For high-security contexts: Lowest possible limits

```inko
# Conservative limits for untrusted input
let parser = EmailParser.with_limits(
  max_email_size: 10_000_000,       # 10 MB
  max_attachment_size: 5_000_000,   # 5 MB
  max_multipart_depth: 5
)
```

### 3. Handle Attachments Safely

Never execute attachments or open them in unsafe contexts:

```inko
message.attachments.each(fn (attachment) {
  # Validate filename before saving
  match attachment.filename {
    case Some(name) => {
      # Already sanitized, but verify before filesystem operations
      if is_safe_filename(name) {
        save_attachment(name, attachment.content)
      }
    }
    case None => {
      # Handle unnamed attachments
    }
  }
})
```

### 4. Implement Timeouts

Always use timeouts when parsing emails from network sources:

```inko
# Example with timeout (pseudo-code)
timeout_parse(parser, raw_email, seconds: 30)
```

### 5. Log Security Events

Log parsing failures and suspicious patterns:

```inko
case Error(e) => {
  if e.contains("exceeds maximum") {
    log_security_event("Potential DoS attempt: " + e)
  }
}
```

### 6. Validate Decoded Content

The library decodes content-transfer-encoding, but you should validate the result:

- Check for unexpected binary data in text fields
- Validate character sets are appropriate
- Scan attachments for malware before saving

### 7. Use Strict Mode for Production

Enable strict mode to fail on invalid headers:

```inko
let parser = EmailParser.with_strict_mode(true)
```

## Vulnerability Reporting Process

If you discover a security vulnerability, please report it responsibly.

### Reporting a Vulnerability

**Do not** open a public issue.

For security-related questions or vulnerability reports, please use GitHub's private vulnerability reporting feature or contact the maintainers directly.

Please include:

1. Description of the vulnerability
2. Steps to reproduce the issue
3. Potential impact assessment
4. Suggested fix (if known)

### What to Expect

1. **Acknowledgment**: You'll receive a response within 48 hours
2. **Validation**: We'll investigate and confirm the vulnerability
3. **Resolution**: We'll develop a fix within a reasonable timeframe
4. **Disclosure**: We'll coordinate public disclosure with you

### Security Updates

Security updates will be:

- Released as patch version updates (e.g., 0.1.0 -> 0.1.1)
- Announced in the release notes
- Updated in this SECURITY.md file

### Coordinated Disclosure

We follow responsible disclosure practices:

1. Fix the vulnerability first
2. Release a security update
3. Publish security advisory
4. Credit the reporter (if desired)

## Additional Resources

- [RFC 5322 - Internet Message Format](https://tools.ietf.org/html/rfc5322)
- [RFC 2045 - MIME (Multipurpose Internet Mail Extensions)](https://tools.ietf.org/html/rfc2045)
- [RFC 2047 - MIME Encoded-Word](https://tools.ietf.org/html/rfc2047)
- [GitHub Security Best Practices](https://docs.github.com/en/code-security)

---

**Note**: This security policy is a living document. As new threats are discovered and mitigations implemented, this document will be updated.
