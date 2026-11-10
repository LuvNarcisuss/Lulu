# Lulu Agreement Revision

Published on November 9, 2026 in the Lulu project's public `legal/2026-11-09-lulu/` directory. This name-only revision carries forward the November 3 agreement text. The earlier guest sign-in and account-deletion wording and the unassigned operator and contact details still require separate review before distribution.

Both files returned HTTP 200 with MIME type `application/pdf` on anonymous HTTPS download. The downloaded bytes exactly match the released PDFs and the bundled offline copies. See [public verification](public-verification.json) and the [Storage listing](storage-publication.png). The November 3 objects remain available at their original URLs.

The login links and Settings use the same PDF reader. Lulu checks the downloaded revision against its configured SHA-256 hash and falls back to the matching bundled copy if the download fails validation. The consent version is derived from the two released PDFs in Terms, Privacy order.

For layout review, pass a temporary copy of the Markdown sources to `scripts/backend_legal.py`. The PDFs in this directory are the exact published bytes.
