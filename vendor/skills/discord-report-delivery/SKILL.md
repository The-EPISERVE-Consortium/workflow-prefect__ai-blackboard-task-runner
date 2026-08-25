---
name: discord-report-delivery
description: Use only when the prompt explicitly asks to send/post/deliver the result to Discord (or similar wording naming Discord specifically). Not triggered just because DISCORD_WEBHOOK_URL happens to be set -- that env var being present does not by itself mean this run should post anything.
---

# Discord delivery

Only act if the prompt you were given explicitly asks for the result to be
sent to Discord (e.g. "post the report to Discord", "send it to the Discord
channel"). The mere presence of `DISCORD_WEBHOOK_URL` in the environment is
not that instruction -- it may be configured for other runs that do ask for
it, or left set as a default. If the prompt doesn't mention Discord, do
nothing in this skill and don't second-guess it.

If the prompt does ask for Discord delivery:

1. Check whether `DISCORD_WEBHOOK_URL` is actually set (e.g. `echo
   "$DISCORD_WEBHOOK_URL"`). If it's unset or empty, this is a real failure
   of what was asked -- report clearly in your final summary that Discord
   delivery was requested but no webhook was configured; don't silently skip
   it and don't fabricate success.
2. Once you have finished producing and verifying the task's deliverable
   (per harness-conventions -- never deliver a file you haven't confirmed
   exists and looks right), post it to that webhook yourself:

   ```bash
   curl -sS -f -F "file1=@/output/report.pdf" "$DISCORD_WEBHOOK_URL"
   ```

   Post the file the task actually asked for -- not every intermediate file
   sitting in `/output`.
3. Verify the `curl` call actually succeeded (its exit code, and that it
   didn't return an error body) before reporting the task as done. A failed
   Discord post is a real failure of the task, not something to silently
   swallow -- say so explicitly in your final summary if it fails, and never
   claim delivery succeeded when it didn't.
4. Discord's webhook attachment limit is 10 MB on a non-boosted server. If
   the deliverable exceeds that, say so explicitly rather than attempting
   (and silently failing) the upload.
