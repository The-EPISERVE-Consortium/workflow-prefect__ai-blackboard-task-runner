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

There is exactly one Prefect deployment, `manual` — no baked-in prompt,
ever. Every run supplies its own prompt at trigger time: a human via
`prefect deployment run`, or
[`workflow-prefect__generate-ai-task-from-blackboard`](https://github.com/The-EPISERVE-Consortium/workflow-prefect__generate-ai-task-from-blackboard)'s
orchestrator acting on a `kind='initial'` row in the shared blackboard table
(`agent_blackboard.task_runs`) — including recurring tasks, which are
periodic blackboard rows rather than scheduled deployments in this repo.

```bash
# register/update the 'manual' deployment:
PREFECT_API_URL=https://your.prefect.server/api python deploy.py

# one-off custom prompt -- prompt is required here, there is deliberately no
# default (a task with no prompt doesn't make sense):
PREFECT_API_URL=https://your.prefect.server/api \
prefect deployment run 'agent-task-pipeline/manual' \
  -p prompt="Clone <repo-url>, analyse the content and write a report to /output/report.pdf"
```

A recurring task is added by inserting a `kind='initial'` row into the
blackboard table (see that repo's README), not by adding code or
deployments here.

The Kubernetes Job's env needs `LLM_PROVIDER` + the matching provider API
key (e.g. `ZIB_API_KEY`) — these are wired in via a sealed secret and the
`kubernetes-pool` work pool's base job template, independent of the
`provider` flow parameter above.
