# workflow-prefect__run-ai-task

Docker harness for the [pi coding agent](https://pi.dev) that runs a single
prompt headlessly against an LLM provider and collects the resulting files,
plus (not yet built) the Prefect flow that triggers it as a one-shot
Kubernetes Job per request.

The idea: give it a one-off task ("clone this repo, analyse it, write a PDF
report") and it runs unattended in a disposable container — no interactive
session, no manual babysitting. The Prefect flow lives in this same repo
rather than a separate one (`flow/report_flow.py`, not yet built): it just
shells out to `pi-report.sh` inside this same image, so there's nothing
external to orchestrate.

## Build

```bash
docker build -t pi-agent .
```

## Run

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
