---
name: github-pr
description: Use only when the prompt explicitly asks to fix code and open a pull request (e.g. "fix these bugs and open a PR", "open a PR with your changes"). Not triggered by default -- most runs never touch git remotes or GitHub.
---

# Opening a pull request

This harness can push commits and open real pull requests against GitHub
repositories, authenticated as a dedicated bot identity (`episerve-ai-bot`),
never as you personally.

Only act if the prompt explicitly asks for this (wording like "open a PR",
"fix these bugs and open a pull request", "push your changes and open a
PR"). If it doesn't, do nothing in this skill -- most runs never push
anything.

## Authentication

`entrypoint.sh` already ran `gh auth setup-git` (so `git clone`/`git push`
authenticate via `GITHUB_TOKEN` automatically, same as every `gh` command
does) and set `git config --global user.name` / `user.email` from
`GITHUB_USER`/`GITHUB_EMAIL` before you started -- don't run any of that
yourself, don't ask for credentials, and never put a token in a remote URL.

If `gh auth status` reports not logged in, that means `GITHUB_TOKEN` was
unset or invalid for this run -- a real failure of what was asked. Say so
explicitly in your final summary rather than silently skipping the push/PR,
and don't fabricate a PR URL.

## Workflow

1. **Clone the target repository.** The URL comes from the prompt itself
   (or, if this run was triggered from a blackboard row, from that row's
   original `prompt`) -- never guess a repository from general knowledge.
2. **Create a new branch.** Never commit to the repository's default
   branch directly. `git checkout -b fix/<short-kebab-case-description>`.
3. **Fix only what you've verified.** If you're working from a findings
   list (e.g. a code analysis report) rather than doing your own
   investigation from scratch, verify each finding against the actual
   current code before changing anything -- a report can be stale or wrong.
   Only touch what you've confirmed is a real bug; leave `[Consider]`-style
   judgment calls alone unless the prompt asks you to make them.
4. **Commit with a specific message.** Describe what was wrong and what the
   fix does (e.g. "Guard against empty `input_files` in `run_model`" not
   "fix bugs") -- one commit per logically distinct fix if there are
   several, not one giant commit.
5. **Push the branch:** `git push -u origin <branch-name>`.
6. **Open the PR:** `gh pr create --title "..." --body "..."`. Don't assume
   the default branch is `main` -- `gh pr create` targets it automatically
   when `--base` is omitted, so only pass `--base` if the prompt names a
   specific target branch.
7. **Verify before claiming success.** `gh pr create` prints the new PR's
   URL on success -- confirm you actually got one (not an error message) and
   include the real URL in your final summary. Never report a PR as opened
   without having seen that URL.

## What not to do

- Never push directly to the default branch, and never force-push.
- Never fix something you haven't personally verified against the current
  code -- a stale or speculative finding is not a license to change
  unrelated code "while you're in there."
- If `gh pr create` fails (auth error, branch protection, nothing to
  commit, etc.), that's a real failure -- report the actual error message
  plainly, don't claim the PR was opened anyway.
