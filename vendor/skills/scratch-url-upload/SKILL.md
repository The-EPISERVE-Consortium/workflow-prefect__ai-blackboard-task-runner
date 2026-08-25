---
name: scratch-url-upload
description: Use only when the prompt explicitly asks for a file to be uploaded temporarily / to a scratch URL / to a link that can be reused elsewhere (e.g. "upload it temporarily", "give me a scratch URL for the report", "post it somewhere I can link to"). Not triggered by default -- most runs should not upload anything anywhere.
---

# Scratch URL upload

Only act if the prompt explicitly asks for a file to be made available at a
temporary/scratch link. If it doesn't, do nothing in this skill.

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
  `https://litterbox.catbox.moe/`) before treating the upload as successful.
  A non-URL response or a failed `curl` call is a real failure to report,
  not something to silently ignore.
- Upload the file the prompt actually asked for -- not every file sitting in
  `/output`.
- This host is public and unauthenticated: anyone with the URL can read the
  file, and it is not access-controlled. Fine for public-repo analysis
  output; do not use it for anything sensitive or proprietary without
  flagging that explicitly in your summary.
- Always state the returned URL plainly in your final response so it can be
  used directly (e.g. copied into a follow-up prompt) -- don't bury it in
  prose.
