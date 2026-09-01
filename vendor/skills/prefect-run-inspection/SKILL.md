---
name: prefect-run-inspection
description: Use only when the prompt explicitly asks to inspect / check / review / scan Prefect flow runs, deployments, task runs, or their logs (e.g. "check last night's Prefect runs for problems", "did the blackboard-orchestrator flow fail overnight", "summarise the failed flow runs today"). Not triggered just because PREFECT_API_URL happens to be set. Read-only: never trigger, cancel, retry, pause, or delete anything.
---

# Prefect run inspection

Only act if the prompt you were given explicitly asks you to look at Prefect
flow runs / deployments / logs. The mere presence of `PREFECT_API_URL` in the
environment is not that instruction -- it may be injected for other reasons
(a Prefect-managed flow run always has it set). If the prompt doesn't mention
Prefect, do nothing in this skill.

**Strictly read-only.** Even though the API token/URL would technically allow
it, this skill must never run `prefect deployment run`, `prefect flow-run
cancel`, `prefect flow-run delete`, `... retry`, `... pause`/`resume`, or any
mutating (`POST`/`PATCH`/`PUT`/`DELETE`, other than the read-only
`.../filter` endpoints) API call. If the prompt asks you to re-run, cancel,
or otherwise change a run, do the inspection part, then state plainly in your
final summary that the mutating part was **not** performed because this
harness only permits read access to Prefect.

## Setup

1. Check `PREFECT_API_URL` is set (`echo "$PREFECT_API_URL"`). If it's unset
   or empty, this is a real failure of what was asked -- say so clearly in
   your final summary; don't fabricate results. `PREFECT_API_KEY` may also be
   set (not required for the ZIB server today) -- the `prefect` CLI picks
   both up from the environment automatically, no login step.
2. The `prefect` CLI is already on `PATH` in this image.

## Reading runs

Quick listing (most recent first, newest 15 by default):

```bash
prefect flow-run ls --limit 50
prefect flow-run ls --flow-name blackboard-orchestrator --state-type FAILED
prefect flow-run ls --state-type CRASHED --state-type FAILED
```

Time-windowed queries ("last night", "today", "since <time>") -- compute
explicit **UTC** ISO-8601 bounds yourself (don't eyeball a relative phrase),
then use the read-only filter endpoint:

```bash
prefect api POST /flow_runs/filter --data '{
  "flow_runs": {
    "start_time": {"after_": "2026-08-31T20:00:00Z", "before_": "2026-09-01T06:00:00Z"}
  },
  "sort": "START_TIME_DESC",
  "limit": 200
}'
```

Add a state filter to narrow to problems, e.g.:

```json
"state": {"type": {"any_": ["FAILED", "CRASHED"]}}
```

Details and logs for a specific run (id from the listings above):

```bash
prefect flow-run inspect <flow-run-id>
prefect flow-run logs <flow-run-id>          # all logs
prefect flow-run logs <flow-run-id> --tail -n 50
```

For task-run-level detail use `prefect api POST /task_runs/filter --data
'{...}'` with a `flow_run_id` filter, same read-only pattern.

## Scanning for problems

When asked to "scan for problems", go past the state label: pull the logs of
each `FAILED`/`CRASHED` run (and any `COMPLETED` run whose logs contain
`ERROR`/`Traceback`/`WARNING` worth surfacing), and report per run: flow
name, run name, id, state, start time (UTC), and the specific error line(s)
or exception -- not just "it failed". If nothing is wrong in the window, say
so explicitly rather than padding.

Producing a written report file, a PDF, or sending the result anywhere
(Discord, blackboard, a scratch URL) is **not** part of this skill -- that is
driven by the prompt via `harness-conventions` and the delivery skills. This
skill only gets you the Prefect data.
