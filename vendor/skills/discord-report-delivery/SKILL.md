---
name: discord-report-delivery
description: Use only when the prompt explicitly asks to send/post/deliver something to Discord -- a file, or a plain message such as a link (or similar wording naming Discord specifically). Not triggered just because DISCORD_WEBHOOK_URL happens to be set -- that env var being present does not by itself mean this run should post anything.
---

# Discord delivery

Only act if the prompt you were given explicitly asks for something to be
sent to Discord (e.g. "post the report to Discord", "send the URL to
Discord"). The mere presence of `DISCORD_WEBHOOK_URL` in the environment is
not that instruction -- it may be configured for other runs that do ask for
it, or left set as a default. If the prompt doesn't mention Discord, do
nothing in this skill and don't second-guess it.

If the prompt does ask for Discord delivery:

1. Check whether `DISCORD_WEBHOOK_URL` is actually set (e.g. `echo
   "$DISCORD_WEBHOOK_URL"`). If it's unset or empty, this is a real failure
   of what was asked -- report clearly in your final summary that Discord
   delivery was requested but no webhook was configured; don't silently skip
   it and don't fabricate success.
2. Two things can be sent, depending on what the prompt asks for -- use
   whichever applies, or both if asked for both:

   **A file** (e.g. "post the report to Discord"): once you have finished
   producing and verifying the deliverable (per harness-conventions -- never
   deliver a file you haven't confirmed exists and looks right), post it
   with a `content` field giving a one-to-two-sentence, human-readable
   explanation of what the file is -- never post a bare attachment with no
   context:

   ```bash
   curl -sS -f \
     -F "content=Code analysis report for <repo-name>: <one-line summary of what was found, e.g. severity/count of the top findings>." \
     -F "file1=@/output/report.pdf" \
     "$DISCORD_WEBHOOK_URL"
   ```

   The `content` text should be specific to this run -- name the repo/subject
   and the gist of the result (e.g. "3 medium-severity findings, no
   high-severity bugs"), not a generic placeholder like "Here is the report."
   Post the file the task actually asked for -- not every intermediate file
   sitting in `/output`.

   **A plain message with no file** (e.g. "send the URL to Discord" after a
   scratch upload): post `content` alone, no file field, still with enough
   context to be useful on its own -- not just the bare URL/value with no
   explanation of what it is:

   ```bash
   curl -sS -f \
     -F "content=Report for <repo-name> (markdown source): <the URL>" \
     "$DISCORD_WEBHOOK_URL"
   ```
3. Verify the `curl` call actually succeeded (its exit code, and that it
   didn't return an error body) before reporting the task as done. A failed
   Discord post is a real failure of the task, not something to silently
   swallow -- say so explicitly in your final summary if it fails, and never
   claim delivery succeeded when it didn't.
4. Discord's webhook attachment limit is 10 MB on a non-boosted server. If a
   file deliverable exceeds that, say so explicitly rather than attempting
   (and silently failing) the upload.
