# workflow-prefect__run-ai-task

Docker harness for the [pi coding agent](https://pi.dev) that runs a single
prompt headlessly against an LLM provider and collects the resulting files,
plus the Prefect flow (`flow/agent_task_flow.py`) that triggers it as a
one-shot Kubernetes Job per request.

The idea: give it a one-off task ("clone this repo, analyse it, write a PDF
report", or anything else `pi` can do unattended) and it runs in a
disposable container — no interactive session, no manual babysitting. The
Prefect flow lives in this same repo rather than a separate one: it just
shells out to `pi-agent-task.sh` inside this same image, so there's nothing
external to orchestrate. Producing a code analysis report is one supported
task (via the `code-analysis-report` skill) among others, not the only one.

## Build

```bash
docker build -t pi-agent .
```

## Run locally

```bash
LLM_PROVIDER=zib \
ZIB_API_KEY=sk-... \
./run-prompt.sh "Clone <repo-url>, analyse the content and write a report to /output/report.pdf" \
  ./run-output
```

`LLM_PROVIDER` selects the provider: `zib` (default choice), `ollama`, or
`openrouter`. See `.env.example` for the environment variables each one
needs. Only `/output` (the given output directory) is written to the host;
everything else stays inside the container and is discarded after the run.

## Run via Prefect

Named tasks (a fixed, real prompt each, no placeholders) live in
`deploy/tasks.yaml`. Each gets its own daily-scheduled Prefect deployment
unless `run_daily: false`.

```bash
# deploy everything in deploy/tasks.yaml (+ the 'manual' deployment):
PREFECT_API_URL=https://your.prefect.server/api python deploy.py

# ...or just one task, or just the 'manual' deployment:
PREFECT_API_URL=https://your.prefect.server/api python -m deploy timesfm-code-analysis
PREFECT_API_URL=https://your.prefect.server/api python -m deploy --manual

# trigger every enabled task right now, in addition to its daily schedule:
PREFECT_API_URL=https://your.prefect.server/api python run.py

# or trigger just one:
prefect deployment run 'agent-task-pipeline/run-ai-task-timesfm-code-analysis'

# one-off custom prompt, no registry entry needed -- prompt is required here,
# there is deliberately no default (a task with no prompt doesn't make sense):
prefect deployment run 'agent-task-pipeline/manual' \
  -p prompt="Clone <repo-url>, analyse the content and write a report to /output/report.pdf"
```

Adding a new task never needs code changes — add an entry to
`deploy/tasks.yaml` (see the file for the shape) and redeploy it.

The Kubernetes Job's env needs `LLM_PROVIDER` + the matching provider API
key (e.g. `ZIB_API_KEY`) — see the harness notes (Appendix A and G) for how
that's wired in via a sealed secret and the work pool's base job template,
independent of the `provider` flow parameter above.
