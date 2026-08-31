---
name: doip-fdo-access
description: Use only when the prompt explicitly asks for a native DOIP-protocol operation on an FDO -- list an object's version history, retrieve a component at a specific commit, write/replace a component, invoke a server-side DOIP workflow, or purge the server's manifest cache. For platform catalog queries, CKAN records, and latest-version component downloads, use episerve-platform-access instead. Not triggered by default.
---

# DOIP FDO access

This harness can drive the running EPISERVE **DOIP server** (a pod in the
cluster) over its native binary DOIP 2.0 protocol, using the bundled
`episerve-doip-cli` binary (`/usr/local/bin/episerve-doip-cli`). The server
is already running -- this skill only sends it requests.

Only act if the prompt explicitly asks for one of the operations below. If it
doesn't, do nothing in this skill.

## Which skill -- this one or `episerve-platform-access`

This skill is **only** for operations that exist solely over the native DOIP
protocol. Everything else goes to `episerve-platform-access`.

| You want to... | Skill |
|---|---|
| List an object's **version history** (`versions`) | **this skill** (only option) |
| Retrieve a component **at a specific commit** (`--version`) | **this skill** (only option) |
| **Write / replace** a component on an existing FDO (`update`) | **this skill** (only option) |
| **Invoke** a server-side workflow (e.g. `equation_extraction`) | **this skill** (only option) |
| `hello` / `list_ops`; purge the manifest cache | **this skill** (only option) |
| List components / download a component **at latest version** | **`episerve-platform-access`** -- HTTP gateway, streamed, better for large files. Only fall back to this skill's `retrieve` if that gateway is unreachable. |
| Catalog listings, CKAN record, `health`, trigger a model run | **`episerve-platform-access`** -- none of those are DOIP operations |

Rule of thumb: if you don't need a **version**, a **write**, or an
**invoke / purge / hello**, you don't need this skill -- use
`episerve-platform-access`.

## Connection

Already in the environment -- don't guess a host, and don't use the public
hostname (this runs in-cluster):

| Env var | Meaning |
|---|---|
| `DOIP_HOST` | Service DNS of the DOIP server pod (e.g. `doip-server.default.svc.cluster.local`) |
| `DOIP_PORT` | Native DOIP port -- `3567` |
| `DOIP_UPDATE_TOKEN` | Shared secret required **only** for `update`. Read directly by the CLI. Absent for read-only tasks -- that's fine. |

The server speaks **TLS-wrapped** DOIP frames with a self-signed certificate,
so use the CLI's default: **do not pass `--no-tls`** (the handshake fails with
"Socket closed before receiving expected bytes") and **do not pass `--secure`**
(the cert's hostname won't match the in-cluster Service DNS). No TLS flag at
all = TLS on, verification off, which is what works here.
If an env var needed for what the prompt asked is unset, that's a real
failure -- say so explicitly rather than skipping the call.

## How to call it

Always pass `--force-json-output`. In that mode the CLI prints **exactly one
JSON envelope on stdout and nothing else** (no banner, no debug logging):

```
{"action": "<action>", "object_id": "<qid|null>", "ok": true, "result": <payload>}
```

on failure:

```
{"action": "<action>", "object_id": "<qid|null>", "ok": false, "error": "<message>"}
```

and the exit code is `0` on `ok:true`, `1` on `ok:false`. Parse it with `jq`;
check `.ok` before trusting `.result`.

```bash
DOIP="episerve-doip-cli --host $DOIP_HOST --port $DOIP_PORT --force-json-output"

# metadata (all kernel blocks)
$DOIP --action retrieve --object-id Q1748526042817

# version history
$DOIP --action versions --object-id Q1748526042817

# a component at a specific commit  (--output is REQUIRED in --force-json-output mode)
$DOIP --action retrieve --object-id Q1748526042817 \
  --component components/output/predictions.tsv \
  --version <commit-id> --output /output/predictions.tsv
```

`result` payloads: `retrieve` (metadata) -> `{"metadata_blocks": [...]}`;
`versions` -> `{"versions": [...]}`; component `retrieve` -> `{"saved_to",
"media_type", "bytes"}`; `update` / `invoke` -> `{"metadata_blocks": [...]}`;
`hello` / `list_ops` / `purge` -> the raw response object.

Component IDs are **exact storage names -- no extension is added
automatically**. A component `retrieve` here requires `--output` (binary
content can't share stdout with the envelope); for a plain latest-version
download prefer `episerve-platform-access` (it streams).

## Reads

`hello`, `list_ops`, `retrieve` (metadata), `retrieve --component --version`,
and `versions` are safe whenever the prompt asks. After saving a component to
`/output`, `ls -la` it to confirm non-zero size (per harness-conventions).

## `update` -- the write

Treat this like opening a PR: **only** if the prompt explicitly says to
update / replace / write back a component. It mutates a component on a live
FDO in lakeFS -- there is no dry-run.

```bash
$DOIP --action update --object-id Q1748526042817 \
  --component components/output/predictions.tsv \
  --input /output/predictions.tsv --media-type text/tab-separated-values
```

- Requires `DOIP_UPDATE_TOKEN` (picked up from the env by the CLI). If it's
  unset the envelope comes back `ok:false` with an authorization error --
  report that plainly, don't skip silently and don't fabricate success.
- Pass a correct `--media-type`; the default is `application/octet-stream`.
- Confirm the returned envelope is `ok:true` before claiming success.

## `invoke` and `purge`

- `--action invoke --object-id <QID> --workflow <name> --params '<json>'`
  runs compute **on the server** -- only if the prompt asks for it.
- `--action purge --object-id <QID>` evicts the server's manifest-cache
  entry for that object. Low risk, but still only run it if the prompt asks.

## Verifying

Before your final message claims a DOIP call succeeded: confirm the envelope
on stdout was `ok:true` and carried the `result` you expected (metadata
blocks, a versions list, a saved file, an update ack). An `ok:false`
envelope, a non-zero exit, or a `ConnectionError` in `.error` is a real
failure -- quote it in your summary rather than reporting the operation as
done.
