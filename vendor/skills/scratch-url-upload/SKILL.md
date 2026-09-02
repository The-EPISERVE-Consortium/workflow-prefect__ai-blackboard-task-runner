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
  `https://files.catbox.moe/`) before treating the upload as successful.
  A non-URL response or a failed `curl` call is a real failure -- try the
  fallback, then report if that also fails.

## Fallback: catbox (permanent) when litterbox is blocked

litterbox sits behind a BunkerWeb WAF that has been observed to block the
upload endpoint for whole client IP ranges -- `curl -f` fails with HTTP 500
and the body is an HTML WAF challenge page rather than a URL (a tiny test
file fails the same way, so it is not a size/content issue). When that
happens, fall back to the sibling service from the same provider,
`catbox.moe/user/api.php` -- same API shape, different WAF posture:

```bash
curl -sS -f \
  -F "reqtype=fileupload" \
  -F "fileToUpload=@/output/report.md" \
  https://catbox.moe/user/api.php
```

- No `time` parameter -- **catbox hosts are permanent**. The file stays up
  until someone deletes it manually (which needs a userhash you don't have),
  so there is nothing to clean up but also no automatic expiry. Say so in
  your summary: the link is a permanent public URL, not a scratch one.
- Response body is again the bare URL (`https://files.catbox.moe/<id>.<ext>`).
- Only reach for this after litterbox has actually failed -- don't default
  to the permanent host.
- Upload the file the prompt actually asked for -- not every file sitting in
  `/output`.
- This host is public and unauthenticated: anyone with the URL can read the
  file, and it is not access-controlled. Fine for public-repo analysis
  output; do not use it for anything sensitive or proprietary without
  flagging that explicitly in your summary.
- Always state the returned URL plainly in your final response so it can be
  used directly (e.g. copied into a follow-up prompt) -- don't bury it in
  prose.
