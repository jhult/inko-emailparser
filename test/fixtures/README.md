# Email Test Fixtures

This directory contains real-world email samples for testing the email parser.

## Fixture Files

- `gmail-simple.eml` - Simple Gmail email with basic headers
- `gmail-complex.eml` - Complex Gmail email with multipart/mixed and attachments
- `outlook.eml` - Outlook/O365 email with threading headers
- `apple-mail.eml` - Apple Mail email with quoted-printable encoding
- `utf8-subject.eml` - Email with internationalized UTF-8 subject and body
- `non-ascii-address.eml` - Email with RFC 2047 encoded non-ASCII addresses
- `nested-multipart.eml` - Email with nested multipart structures
- `special-filenames.eml` - Email with attachments containing special characters in filenames

## Usage

These fixtures can be used for manual testing or future automated tests.
Current automated tests use inline email content due to Inko's file I/O API design.
