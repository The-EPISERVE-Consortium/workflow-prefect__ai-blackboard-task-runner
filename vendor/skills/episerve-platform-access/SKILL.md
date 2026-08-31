---
name: episerve-platform-access
description: Use only when the prompt explicitly asks to reach the live EPISERVE platform -- check platform health, list datasets / models / model-runs, look up an item's catalog record by QID, download a component of a registered FDO, or trigger a model run. Not triggered by default and not implied by EPISERVE_* env vars being present -- most runs never contact the platform.
---

# EPISERVE platform access

This harness can query a running EPISERVE deployment through the bundled
`episerve` CLI binary (`/usr/local/bin/episerve`), which fronts three
backends: the **API server** (health, catalog listings, triggering model
runs), the **CKAN catalog** (an item's registered metadata record), and the
**DOIP server's HTTP gateway** (listing and downloading an FDO's components,
latest version only).

Only act if the prompt explicitly asks for one of these things (wording like
"list the available datasets", "download the predictions for run Q...",
"trigger a model run for ..."). The mere presence of `EPISERVE_API_URL` etc.
in the environment is not that instruction -- most runs are standalone
code-analysis tasks that never touch the platform. If the prompt doesn't ask,
do nothing in this skill.

## Which skill -- this one or `doip-fdo-access`

Use **this** skill for everything that is not a native-DOIP-protocol
operation:

| You want to... | Skill |
|---|---|
| Check platform health; list datasets-raw / datasets / models / model-runs | **this skill** (only option) |
| Trigger a model run | **this skill** (only option) |
| Get an item's **CKAN catalog record** | **this skill** (only option) |
| List an FDO's components / download a component **at its latest version** | **this skill** -- HTTP, streamed, handles large files |
| Download a component **at a specific commit**; list an object's **version history**; **write/replace** a component; **invoke** a server-side workflow; `hello`/`list_ops`; purge the manifest cache | **`doip-fdo-access`** -- those exist only over the native DOIP protocol |

If a task needs both (e.g. "list the runs, then fetch run Q...'s output at
commit abc123"), use this skill for the catalog part and `doip-fdo-access`
for the version-pinned fetch.

## Connection

Already in the environment -- don't ask for credentials, don't guess a host.
The `episerve` binary reads all of these itself:

| Env var | Meaning |
|---|---|
| `EPISERVE_API_URL` | API-server base URL (`health`, `list`, `trigger-model-run`) |
| `EPISERVE_CKAN_URL` | CKAN base URL (`item show`) |
| `EPISERVE_DOIP_URL` | DOIP **HTTP gateway** base URL (`item list-components`, `item download`) |
| `EPISERVE_API_KEY` | Bearer token for the API server. **Daily-rotating** (the api-server issues a token that expires each day). Unauthenticated reads may still work; `trigger-model-run` needs a valid token. |

If an env var needed for what the prompt asked is unset or empty, that's a
real failure -- say so explicitly in your final summary rather than silently
skipping the call. An `HTTP 401`/`403` on stderr means the token is missing
or expired -- report it verbatim, don't retry in a loop.

## How to call it

`episerve <command>` prints the result as **JSON on stdout**; a banner and a
`  -> <url>` progress line go to **stderr** (ignore them -- parse stdout
only). Add `--raw` for compact single-line JSON.

```bash
episerve health
episerve list runs                 # or: datasets-raw | datasets | models
episerve item show Q1748526042817  # CKAN catalog record
episerve item list-components Q1748526042817
episerve item download Q1748526042817 components/output/predictions.tsv \
  -o /output/predictions.tsv
```

QIDs have the form `Q<unix-ts><3 digits>` -- never invent one; take it from
prior `list` / `item list-components` output or from the prompt.

## Reads

`health`, `list`, `item show`, `item list-components`, `item download` are
safe whenever the prompt asks. `item download` writes the file at the `-o`
path (omit `-o` and it streams to stdout -- always use `-o` and point it
under `/output`). After a download, `ls -la` the file to confirm it arrived
with non-zero size (per harness-conventions). Never report a file as
downloaded without checking.

## The one write -- `trigger-model-run`

Treat this like opening a PR: **only** if the prompt explicitly says to
trigger / start / launch a model run. It consumes real Kubernetes cluster
resources and cannot be undone or dry-run -- never fire one speculatively or
"to test that it works".

```bash
episerve trigger-model-run '{"model_image": "...", "input_path": "lakefs://...", "config": {...}}'
```

(the argument is an inline JSON string or a path to a JSON file). It returns
`202` with a `run_id`. Confirm a real `run_id` came back (not an error)
before claiming success, and state it plainly so a follow-up can track it
with `episerve item show <run_id>`.

## Verifying

Before your final message claims a platform call succeeded: confirm you saw
the actual result on stdout (a non-empty JSON list, a `run_id`, a file on
disk). The `episerve` binary prints `HTTP <code>: <body>` or `Connection
error: ...` to stderr and exits non-zero on failure -- quote that in your
summary, don't fabricate a result and don't silently skip the step.
