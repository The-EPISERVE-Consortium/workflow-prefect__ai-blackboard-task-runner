---
name: forecast-model-run
description: Use only when the prompt explicitly asks to run / execute / launch a forecast (prediction) model end to end -- trigger the model-runner, wait for the Kubernetes job, and fetch the resulting predictions (e.g. "run the timesfm model on the COVID incidence dataset and give me the forecast", "launch model__prediction__grippeweb__baseline-nullmodel for a 4-week horizon and download predictions.tsv"). Not triggered by default and not implied by EPISERVE_* env vars being present. For a bare one-shot `trigger-model-run` with no wait/fetch, or for catalog listings, use episerve-platform-access; for read-only inspection of runs that already exist, use prefect-run-inspection.
---

# Running a forecast model

The EPISERVE platform runs each forecast model as a self-contained Docker
container on Kubernetes, orchestrated by the **model-runner** Prefect flow
(`model-pipeline`). This skill drives one full run: pick a model and its
input, trigger the flow, wait for the Kubernetes Job to finish, then
download the predictions.

Only act if the prompt explicitly asks for a model to be run / executed /
launched (and usually for its output). If it doesn't, do nothing in this
skill -- most runs never touch the platform.

It works for **any** model that follows the platform's container contract,
not just one -- `model__prediction__generic__timesfm` is the reference
implementation. The contract:

- reads `/work/input/config.json` (run parameters, keys are model-specific)
  and its input data file(s) -- `input.parquet` for the current models, but
  the filename is whatever the run asked for, not fixed
- writes its output under `/work/output/` -- `predictions.tsv` by convention
- exits non-zero on failure, printing `ERROR: <message>` for a line that
  surfaces in the flow's error
- every run is pinned to a lakeFS commit, gets a **QID**
  (`Q<unix-ts><3 digits>`), and has RO-Crate + FDO provenance written next
  to its output

## Which skill

| You want to... | Skill |
|---|---|
| Run a model and get its predictions (trigger + wait + download) | **this skill** |
| Just fire `trigger-model-run` and return the `run_id`, or list datasets / models / runs, or download a component of an existing run | **episerve-platform-access** |
| Look at runs that already happened (states, logs) without starting anything | **prefect-run-inspection** |
| Download a component **at a specific commit**, or an object's version history | **doip-fdo-access** |

This skill *starts* a run (through `episerve trigger-model-run`, the same
one write `episerve-platform-access` documents) and then uses **read-only**
Prefect calls to wait. It must never mutate anything via Prefect
(`prefect deployment run`, `... flow-run cancel/retry/delete`) -- the only
way it launches a run is the `episerve` trigger.

## Connection

Already in the environment -- don't ask for credentials or guess a host.
The `episerve` and `prefect` CLIs read these themselves:

| Env var | Used for |
|---|---|
| `EPISERVE_API_URL` | triggering the run |
| `EPISERVE_API_KEY` | **required** for the trigger -- daily-rotating api-server token; an `HTTP 401`/`403` means it is missing or expired |
| `EPISERVE_DOIP_URL` | listing / downloading the run's output components |
| `PREFECT_API_URL` | polling the flow-run state and reading its logs (auto-injected when this container runs as a Prefect flow run) |

If an env var needed for what the prompt asked is unset or empty, that is a
real failure -- say so explicitly in your final summary rather than
silently skipping the step. On a `401`/`403` from the trigger, report it
verbatim and stop -- do not retry in a loop.

## Step 1 -- choose the model

```bash
episerve list models
```

Each entry has `docker_image` (the full `ghcr.io/the-episerve-consortium/
model__...` string -> `model_image`), `docker_tag` (-> `model_tag`), and
`git_repo`. Take these from the prompt or this list -- never invent an
image name.

**Config keys are model-specific -- never guess them.** Get them from:
- the model repo (`git_repo`)'s `fdo.json` -- `additionalProperty` lists
  each parameter, whether it is required, and its default -- or its
  `README.md`
- the platform's model notes

Known models:
- `model__prediction__generic__timesfm` -- `history_length` (req),
  `prediction_length` (req, max 512), `prediction_offset` (opt, default 0);
  values must be integers
- `model__prediction__grippeweb__baseline-nullmodel` -- `horizon_weeks`
  (default 4), `n_reference_weeks` (default 4)

## Step 2 -- choose the input data

```bash
episerve list datasets
```

Copy the `data_path` of the dataset you want -- it is a DOIP retrieve URL
and is used as the input source. A previous run's output
(`lakefs://model-runs/...` or a DOIP retrieve URL) works as an input too.

Two supported source forms (anything else is rejected by the pull step):
- `lakefs://<repo>/<branch>/<path>`
- `https://<doip-host>/doip/retrieve/<QID>/<component>`

The container sees the file under the **target filename** you give it in
`input_data_files` -- use the name the model expects (`input.parquet` for
the current models).

**`data_transformation_sql`** (optional): a DuckDB SQL string applied to the
downloaded file in place, run against a table called `df`. It is a parallel
list -- one entry per `input_data_files` entry (use `""` to skip one).
Needed when the source carries several series and the model forecasts every
non-x column independently: filter or pivot down to the one series you want
first, e.g.
`SELECT "Meldedatum", "Inzidenz_7-Tage" FROM df WHERE "Altersgruppe" = '15-34' ORDER BY "Meldedatum"`.

## Step 3 -- trigger the run

Treat this like opening a PR: **only** if the prompt explicitly asks for the
model to be run. It consumes real Kubernetes resources and cannot be undone
or dry-run -- never fire one speculatively or "to check that it works".

```bash
episerve trigger-model-run '{
  "model_image": "ghcr.io/the-episerve-consortium/model__prediction__generic__timesfm",
  "model_tag": "latest",
  "input_data_files": [["<data_path from list datasets>", "input.parquet"]],
  "config": {"history_length": 512, "prediction_length": 182},
  "data_transformation_sql": ["SELECT ... FROM df WHERE ..."]
}'
```

`model_image`, `input_data_files` (a list of `[source_uri, target_filename]`
pairs), and `config` (a JSON object) are required; `model_tag` (default
`latest`) and `data_transformation_sql` are optional. The argument is an
inline JSON string or a path to a JSON file.

It returns `202` with a `run_id` -- the **Prefect flow-run UUID**, not a
QID. Confirm a real `run_id` came back (not an error) before continuing,
and state it plainly.

## Step 4 -- wait for the run

The flow submits a Kubernetes Job (`lakefs-pull` -> `model` ->
`lakefs-push`). Expect minutes, and up to ~10-15 min the first time a given
model image runs (e.g. timesfm downloads ~800 MB of weights on first use).

Poll the flow-run state, read-only, every 20-30 s -- the response is JSON:

```bash
prefect api GET /flow_runs/<run_id> | jq -r '.state.type'
```

Stop when the state type is terminal: `COMPLETED`, `FAILED`, `CRASHED`, or
`CANCELLED`. Anything else (`SCHEDULED`, `PENDING`, `RUNNING`, `PAUSED`) is
still in progress. (`prefect flow-run inspect <run_id>` shows the same
thing in human-readable form.)

Cap the wait (~30 min). If it is still non-terminal at the cap, stop
polling and report that the run is still in progress, quoting the `run_id`
and the QID (Step 5) so a follow-up can pick it up -- do not hang
indefinitely, and do not call it failed.

## Step 5 -- get the run's QID

The QID is minted inside the flow and is **not** in the trigger response.
Read it from the flow-run logs via the Kubernetes Job name, which is
`model-runner-q<qid>` and is unambiguous (a bare `Q...` also matches the
*input* dataset's QID in the same logs, so don't grep for that):

```bash
prefect flow-run logs <run_id> \
  | grep -oiE 'model-runner-q[0-9]{13,}' | head -1 \
  | sed 's/model-runner-//I' | tr 'a-z' 'A-Z'
```

(Once the catalog sync catches up the run also shows in `episerve list
runs`; the DOIP calls in Step 6 work as soon as the flow commits its
metadata, independent of that sync, so prefer the QID from the logs.)

If no QID appears in the logs, treat that as a real failure -- report it
with the run's final state rather than guessing an identifier.

## Step 6 -- fetch the result

**On `COMPLETED`:**

```bash
episerve item list-components <qid>
```

`list-components` returns each file's `id` already in the form `item
download` expects -- the `components/` prefix stripped, so an output file
`predictions.tsv` comes back as `output/predictions.tsv`. Pass that string
verbatim:

```bash
episerve item download <qid> output/predictions.tsv -o /output/predictions.tsv
```

Then `ls -la /output/predictions.tsv` and confirm it exists with non-zero
size (per harness-conventions). Always take the id from the
`list-components` output -- do not hand-build it, and don't assume the
model wrote exactly `output/predictions.tsv`.

**On `FAILED` / `CRASHED` / `CANCELLED`:** this is a real failure -- report
it, don't retry blindly. Get the reason from the flow-run logs:

```bash
prefect flow-run logs <run_id>
```

On a job failure the flow logs the full per-container pod output and raises
with the model's first `ERROR:` line appended -- everything you need is
there. (A `run.log` is also written to lakeFS, but on a failed run the FDO
does not list the output components, so `episerve item download` will not
serve it -- use the flow logs.)

## Verifying

Before your final message says the forecast ran: confirm you actually saw a
terminal `COMPLETED` state **and** downloaded a non-empty predictions file.
A non-`COMPLETED` terminal state, a `401`/`403` on the trigger, a missing
QID, a non-zero exit or `HTTP <code>` error from any `episerve` call, or a
zero-byte download is a real failure -- quote it in your summary. Never
fabricate predictions, a `run_id`, or a QID, and never report the run as
done on the assumption that a step "probably" worked.

## What not to do

- Never trigger a run speculatively, "to test", or when the prompt did not
  ask for one.
- Never invent a model image, a config key, or a QID -- read them from
  `episerve list` output, the model's `fdo.json`/README, or the prompt.
- Never launch or change a run through Prefect directly (`prefect
  deployment run`, `... flow-run cancel/retry/delete`) -- trigger only via
  `episerve trigger-model-run`, and use Prefect read-only.
- Never loop retrying on an auth error -- report the `401`/`403` and stop.
