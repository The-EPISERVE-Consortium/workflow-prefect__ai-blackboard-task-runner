---
name: scratch-url-upload
description: Use only when the prompt explicitly asks for a file to be uploaded temporarily / to a scratch URL / to a link that can be reused elsewhere (e.g. "upload it temporarily", "give me a scratch URL for the report", "post it somewhere I can link to"). Not triggered by default -- most runs should not upload anything anywhere.
---

# Scratch URL upload

Only act if the prompt explicitly asks for a file to be made available at a
temporary/scratch link. If it doesn't, do nothing in this skill.

## Primary: litterbox (auto-expiring)

When it does, upload the requested file to `litterbox.catbox.moe` -- a free,
no-signup, purpose-built temporary file host (files are deleted automatically
after the chosen retention window, nothing to clean up):

```bash
curl -sS -f \
  -F "reqtype=fileupload" \
  -F "time=72h" \
  -F "fileToUpload=@/output/report.md" \
  https://litterbox.catbox.moe/resources/internals/api.php
```

- `time` must be one of `1h`, `12h`, `24h`, `72h`. Default to `72h` unless
  the prompt asks for a shorter/longer window (72h is the maximum this
  service offers -- if asked for something longer, say so explicitly rather
  than silently capping it).
- The response body *is* the URL (plain text, nothing to parse out) --
  verify the response actually looks like a URL (starts with
  `https://litterbox.catbox.moe/` or, for the fallback below,
  `https://0x0.st/`) before treating the upload as successful.
  A non-URL response or a failed `curl` call is a real failure -- try the
  fallback, then report if that also fails.

## Fallback: 0x0.st when litterbox is blocked

litterbox sits behind a BunkerWeb WAF that has been observed to block the
upload endpoint for whole client IP ranges -- `curl -f` fails with HTTP 500
and the body is an HTML WAF challenge page rather than a URL (a tiny test
file fails the same way, so it is not a size/content issue). When that
happens, fall back to `0x0.st` (The Null Pointer) -- also free, no-signup,
plain-`curl`, and **still auto-expiring** so there is nothing to clean up:

```bash
curl -sS -f \
  -F "file=@/output/report.md" \
  -F "expires=72" \
  https://0x0.st
```

- `expires` is in **hours** (any value <= 1e6; larger values are read as a
  UNIX millisecond timestamp). Pass the same window you would have given
  litterbox -- default `72`, and unlike litterbox 0x0.st will accept a
  larger number if the prompt asks for one.
- Without `expires`, 0x0.st still deletes the file on its own: retention
  scales with size from ~30 days (large) down to ~365 days (tiny). It is
  never permanent -- but pass `expires` anyway so the window is explicit.
- Response body is the bare URL (`https://0x0.st/<id>.<ext>`); the same
  URL-shape check applies.
- If 0x0.st answers `403` with a "user agent ... blocked" body, retry once
  with an explicit `-A "scratch-url-upload/1.0"`.
- Only reach for this after litterbox has actually failed -- don't default
  to it.
- Upload the file the prompt actually asked for -- not every file sitting in
  `/output`.
- This host is public and unauthenticated: anyone with the URL can read the
  file, and it is not access-controlled. Fine for public-repo analysis
  output; do not use it for anything sensitive or proprietary without
  flagging that explicitly in your summary.
- Always state the returned URL plainly in your final response so it can be
  used directly (e.g. copied into a follow-up prompt) -- don't bury it in
  prose.
