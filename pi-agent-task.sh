#!/usr/bin/env bash
# Runs pi once against a prompt for whatever task it describes -- a code
# analysis report is one use case this harness supports via the
# code-analysis-report skill, not the only one, so this script makes no
# assumption about what the task produces or where.
#
# Delivery is the agent's own decision, driven by skills force-loaded below
# (discord-delivery, scratch-url-upload) -- e.g. if the prompt asks for
# Discord delivery, pi itself posts the file as one of its own tool calls,
# not this script. This script only handles what's generic across every
# task: propagating pi's own exit code (via `set -e`, no per-file check --
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

FULL_PROMPT="$(cat /opt/skills/harness-conventions/SKILL.md)

$(cat /opt/skills/code-analysis-report/SKILL.md)

$(cat /opt/skills/discord-delivery/SKILL.md)

$(cat /opt/skills/scratch-url-upload/SKILL.md)

---

$PROMPT"

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
   --skill /opt/skills/harness-conventions --skill /opt/skills/code-analysis-report \
   --skill /opt/skills/discord-delivery --skill /opt/skills/scratch-url-upload \
   --mode json -p "$FULL_PROMPT" < /dev/null

python3 /opt/pi-trace-extension/extensions/trace/trace_to_html.py >&2 || true
HTML=$(ls -t /root/.pi/agent/traces/*/trace.html 2>/dev/null | head -1)
[ -n "$HTML" ] && cp "$HTML" "$OUTPUT_DIR/trace.html"

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
