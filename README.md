# pi-llm-server

Docker harness for the [pi coding agent](https://pi.dev) that runs a single
prompt headlessly against an LLM provider and collects the resulting files.

The idea: give it a one-off task ("clone this repo, analyse it, write a PDF
report") and it runs unattended in a disposable container — no interactive
session, no manual babysitting. Meant to eventually run as a one-shot
Kubernetes Job, triggered per-request by a Prefect flow.

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
