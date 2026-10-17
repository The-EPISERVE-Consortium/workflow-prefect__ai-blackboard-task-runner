#!/usr/bin/env bash
# Runs pi once against a prompt for whatever task it describes -- a code
# analysis report is one use case this harness supports via the
# code-analysis-report skill, not the only one, so this script makes no
# assumption about what the task produces or where.
#
# Delivery and platform access are the agent's own decision, driven by skills
# force-loaded below (discord-delivery, scratch-url-upload,
# blackboard-communication, episerve-data-access, episerve-model-runs,
# episerve-benchmarks, doip-fdo-access) -- e.g.
# if the prompt asks for Discord delivery, pi itself posts the file as one of
# its own tool calls, not this script. This script only handles what's
# generic across every task: propagating pi's own exit code (via `set -e`,
# no per-file check --
# what "success" means depends on the task), writing trace.html, and -- if
# the task happened to produce a report.md (the code-analysis-report skill's
# own convention, not a requirement imposed here) -- surfacing it to stderr
# so it ends up wherever this process's output is already being collected --
# a K8s Job's pod logs in the Prefect deployment, the console locally.
#
# Usage: pi-agent-task.sh <provider> <model> "<prompt>"
# (provider/model are passed straight to `pi --provider --model`; the
# provider's own env vars, e.g. LLM_BASE_URL/LLM_API_KEY, must already be set
# by the caller -- entrypoint.sh turns those into pi's provider config.)
set -euo pipefail

PROVIDER="${1:?Usage: pi-agent-task.sh <provider> <model> \"<prompt>\"}"
MODEL="${2:?Usage: pi-agent-task.sh <provider> <model> \"<prompt>\"}"
PROMPT="${3:?Usage: pi-agent-task.sh <provider> <model> \"<prompt>\"}"
OUTPUT_DIR="${OUTPUT_DIR:-/output}"

mkdir -p "$OUTPUT_DIR"

# Every skill under /opt/skills is force-loaded: the two core ones first (in
# this order), then the rest alphabetically. Adding or removing a skill (in
# vendor/skills or in the episerve_skills repo) needs no change here.
CORE_SKILLS=(harness-conventions code-analysis-report)
SKILL_DIRS=()
for name in "${CORE_SKILLS[@]}"; do SKILL_DIRS+=("/opt/skills/$name"); done
for dir in /opt/skills/*/; do
    dir="${dir%/}"
    case " ${CORE_SKILLS[*]} " in *" $(basename "$dir") "*) continue ;; esac
    [ -f "$dir/SKILL.md" ] && SKILL_DIRS+=("$dir")
done

FULL_PROMPT=""
SKILL_FLAGS=()
for dir in "${SKILL_DIRS[@]}"; do
    FULL_PROMPT+="$(cat "$dir/SKILL.md")"$'\n\n'
    SKILL_FLAGS+=(--skill "$dir")
done
FULL_PROMPT+="---"$'\n\n'"$PROMPT"

# EPISERVE access: the API token is valid for one day, so it cannot be a static secret. If the run has
# the credentials of the agent's service user (EPISERVE_USERNAME / EPISERVE_PASSWORD, from the sealed secret
# episerve-agent-credentials) and no token yet, fetch today's token for the skills. Best-effort: without it
# reads still work and the skills report the 401 on a write.
if [ -z "${EPISERVE_API_KEY:-}" ] && [ -n "${EPISERVE_USERNAME:-}" ] && [ -n "${EPISERVE_PASSWORD:-}" ]; then
    EPISERVE_API_KEY=$(jq -n --arg u "$EPISERVE_USERNAME" --arg p "$EPISERVE_PASSWORD" '{username:$u,password:$p}' \
        | curl -fsS -m 20 -X POST "${EPISERVE_API_URL:-https://api.episerve.zib.de}/auth/token" \
              -H "Content-Type: application/json" -d @- | jq -r .token) || EPISERVE_API_KEY=""
    if [ -n "$EPISERVE_API_KEY" ] && [ "$EPISERVE_API_KEY" != "null" ]; then
        export EPISERVE_API_KEY
        echo "episerve: fetched today's API token for $EPISERVE_USERNAME" >&2
    else
        unset EPISERVE_API_KEY
        echo "episerve: could not fetch an API token (writes to the platform will fail)" >&2
    fi
fi

# stdin explicitly closed: -p/--print is documented as non-interactive
# ("process prompt and exit"), so pi should never need stdin -- but nothing
# upstream of this script (subprocess.Popen in the Prefect flow, this
# script itself) redirects it, so it inherits whatever fd the K8s/Prefect
# exec chain leaves connected. If that's an open, never-written, never-closed
# pipe (observed under the Prefect Kubernetes worker, unlike a plain local
# `docker run`), and pi reads stdin for any reason despite -p, it hangs
# forever waiting for input/EOF that never arrives -- with no network
# activity and no error, indistinguishable from progress from the outside.
pi --provider "$PROVIDER" --model "$MODEL" \
   "${SKILL_FLAGS[@]}" \
   --mode json -p "$FULL_PROMPT" < /dev/null

python3 /opt/pi-trace-extension/extensions/trace/trace_to_html.py >&2 || true
HTML=$(ls -t /root/.pi/agent/traces/*/trace.html 2>/dev/null | head -1)
[ -n "$HTML" ] && cp "$HTML" "$OUTPUT_DIR/trace.html"

# Attaching this session's trace.html to its own blackboard row, if the
# blackboard-communication skill published one: the row itself was
# necessarily written *before* trace.html exists (pi is still running at
# that point), so this can't happen inline as part of the INSERT -- the
# skill instead drops the new row's id in a marker file, and this step
# closes the loop deterministically once the trace is actually available.
# Best-effort: a task that didn't publish (no marker file) or whose
# publish failed for its own reasons just skips this, same `|| true`
# philosophy as trace_to_html.py above.
if [ -f "$OUTPUT_DIR/.blackboard_row_id" ] && [ -f "$OUTPUT_DIR/trace.html" ]; then
  python3 - <<'PY' >&2 || true
import os
import pymysql

with open("/output/.blackboard_row_id", encoding="utf-8") as f:
    row_id = int(f.read().strip())
with open("/output/trace.html", encoding="utf-8") as f:
    trace_html = f.read()

conn = pymysql.connect(
    host=os.environ["MARIADB_HOST"],
    user=os.environ["BLACKBOARD_USER"],
    password=os.environ["BLACKBOARD_PASSWORD"],
    database=os.environ["BLACKBOARD_DB"],
    charset="utf8mb4",  # server default connection charset is utf8mb3;
                        # trace.html routinely contains 4-byte characters
                        # (pi-trace-extension's UI uses emoji)
)
try:
    with conn.cursor() as cur:
        cur.execute("UPDATE task_runs SET trace=%s WHERE id=%s", (trace_html, row_id))
        conn.commit()
    print(f"blackboard: attached trace.html to task_runs.id={row_id}")
finally:
    conn.close()
PY
  rm -f "$OUTPUT_DIR/.blackboard_row_id"
fi

# Surfacing report.md if the task produced one -- not part of pi's own event
# stream, goes to stderr, same convention as trace_to_html.py above, so it
# never lands in run.jsonl (which run-prompt.sh's stdout pipeline treats as
# pure JSONL). Still reaches the console locally (stderr isn't suppressed)
# and still lands in K8s pod logs (stdout+stderr are captured combined
# there), so nothing is lost by keeping it off stdout. Best-effort, not a
# hard requirement -- tasks that aren't producing a report don't have one.
if [ -f "$OUTPUT_DIR/report.md" ]; then
  {
    echo "===OUTPUT_MD_BEGIN==="
    cat "$OUTPUT_DIR/report.md"
    echo "===OUTPUT_MD_END==="
  } >&2
fi
