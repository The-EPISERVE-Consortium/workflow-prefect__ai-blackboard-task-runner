---
name: blackboard-communication
description: Use only when the prompt explicitly asks to publish/write/share results to the blackboard for other agents to pick up (e.g. "publish your findings to the blackboard", "write this result to the blackboard so a follow-up task can act on it"). Not triggered by default -- most runs are one-off and should not write anything to this table.
---

# Blackboard communication

This harness is one participant in a loosely-coupled, multi-agent pipeline.
Independent one-shot agent runs (each its own container, its own prompt, no
shared memory) hand work to each other indirectly through a shared MariaDB
table, `task_runs` -- a "blackboard" a separate periodic orchestrator process
polls for new rows, decides what's actionable, and triggers new one-shot runs
of its own. This skill is only the *write* side of that: how this run
publishes a result so the orchestrator can find it later.

Only act if the prompt explicitly asks for this (wording like "publish to
the blackboard", "write your result to the blackboard", "make this available
for a follow-up task"). If it doesn't, do nothing in this skill -- most runs
are standalone and have no downstream consumer.

## Connection

The container already has everything needed in its environment -- don't ask
for credentials, don't guess a hostname:

| Env var | Meaning |
|---|---|
| `MARIADB_HOST` | Database host (same MariaDB instance other platform workflows use) |
| `BLACKBOARD_DB` | Database name (`agent_blackboard`) |
| `BLACKBOARD_USER` | DB user -- scoped to `BLACKBOARD_DB` only, nothing else on this instance |
| `BLACKBOARD_PASSWORD` | Password for that user |

If any of these are unset or empty, this is a real failure of what was
asked -- say so explicitly in your final summary rather than silently
skipping the write.

## Table shape (`task_runs`)

| Column | Who writes it | Meaning |
|---|---|---|
| `id` | auto | Primary key |
| `topic` | **you** | Short, stable label for what kind of result this is (see below) |
| `post_type` | **you** | Always `'someone_take_over'` for a row this skill writes -- see below |
| `prompt` | **you** | The exact task prompt you were given -- see below |
| `state` | orchestrator only | `waiting` \| `dispatching_run` \| `waiting_for_next_periodic_run` \| `resolved` -- always starts `waiting`; never set this yourself |
| `finding` | **you** | The actual payload -- markdown, JSON, or plain text, whatever the result naturally is |
| `trace` | `pi-agent-task.sh`, automatic | This session's `trace.html`, attached to your row after you finish -- see below. Never set this yourself; it doesn't exist yet while you're running (see below). |
| `created_at` | auto | |
| `periodic_interval_minutes` / `periodic_last_triggered_at` | n/a | Only meaningful on `post_type='run_me'` rows (seeded directly, not written by this skill) -- leave these unset |
| `last_state_change` | orchestrator only, automatic | Never set this yourself -- it tracks the orchestrator's claim lifecycle |

You only ever **insert one new row** with your own result. You have DB
privileges to `UPDATE`, but that's reserved for the orchestrator claiming and
completing rows -- don't touch a row you didn't just insert, and never
`DELETE` anything.

`post_type` distinguishes a row you write (`'someone_take_over'` -- an
output with a `finding` payload, matched by the orchestrator against its
`routing_rules` table to build a follow-up prompt) from a
`post_type='run_me'` row (seeded directly with its own `prompt`, no
`finding`, sometimes recurring) -- this skill only ever produces the
former. Set it explicitly to `'someone_take_over'` on your `INSERT` rather
than relying on the column default.

`topic` is the field the orchestrator pattern-matches on to decide what
happens next, so get it right:
- If the prompt names a specific value to use, use exactly that string,
  verbatim -- don't paraphrase or reformat it.
- Otherwise, pick a short, stable, kebab-case label describing the *kind* of
  result (e.g. `bug-report`, `fix-summary`), not a one-off description of
  this specific run -- state whatever you chose plainly in your final
  summary so it's visible.

`prompt` is the literal task prompt you were given -- everything after the
`---` separator in your own instructions, not the skill text above it
(the harness-conventions/code-analysis-report/etc. content, or this skill's
own instructions, is never part of `prompt`). Store it verbatim, exactly as
you received it, with no summarizing or rewording -- this is what lets
anyone reading a row later answer "what was this run actually asked to do."

## Writing the row

Use `pymysql` (already installed) with a parameterized query -- **never**
build a SQL string yourself by interpolating the result content into a
shell command or an f-string. Report content is often long, multi-line
markdown/JSON full of quotes, backticks, and semicolons; hand-escaping that
for a shell heredoc is exactly the kind of thing that silently corrupts data
or breaks the query. Read the content from the file you already wrote and
pass it as a bound parameter:

```python
import os
import pymysql

with open("/output/report.md", encoding="utf-8") as f:
    result_text = f.read()

# The literal task prompt you were given, verbatim -- write out the actual
# text here yourself (everything after the "---" separator in your own
# instructions), don't read it from a file, it isn't one.
task_prompt = "..."

conn = pymysql.connect(
    host=os.environ["MARIADB_HOST"],
    user=os.environ["BLACKBOARD_USER"],
    password=os.environ["BLACKBOARD_PASSWORD"],
    database=os.environ["BLACKBOARD_DB"],
    charset="utf8mb4",  # server's default connection charset is utf8mb3 --
                        # without this, any 4-byte character (many emoji,
                        # some CJK) in your result gets silently mangled or
                        # rejected outright, even though the column itself
                        # is utf8mb4
)
try:
    with conn.cursor() as cur:
        cur.execute(
            "INSERT INTO task_runs (topic, post_type, prompt, finding) VALUES (%s, %s, %s, %s)",
            ("bug-report", "someone_take_over", task_prompt, result_text),
        )
        conn.commit()
        new_id = cur.lastrowid
finally:
    conn.close()

with open("/output/.blackboard_row_id", "w", encoding="utf-8") as f:
    f.write(str(new_id))

print(f"blackboard: wrote task_runs.id={new_id}")
```

Run this as `python3 - <<'PY' ... PY` (or a short `.py` file) rather than
`python3 -c "..."` if the snippet needs editing -- keeps quoting simple.

Never pass `trace` in this `INSERT` -- your own session's `trace.html`
doesn't exist yet while you're still running (it's generated by
`pi-agent-task.sh` after you finish). Writing `new_id` to
`/output/.blackboard_row_id` (exactly as shown above -- that path and
filename are load-bearing) is how `pi-agent-task.sh` finds your row
afterward to attach the trace automatically. Skipping that file just means
your row is published without a trace; it does not fail the publish.

## Verifying

Before your final message claims the blackboard write succeeded: confirm
`cur.lastrowid` is a real, non-zero id and that `conn.commit()` ran without
raising. A `pymysql` exception (bad credentials, connection refused, a
constraint violation) is a real failure -- report it plainly in your final
summary, including the actual error message, rather than reporting the
publish as done. Never claim a row was written without having actually seen
the insert succeed.
