#!/usr/bin/env bash
# Runs pi once against a prompt. Delivery is the agent's own decision, driven
# by the discord-report-delivery skill (force-loaded below, same mechanism as
# the other two skills) -- if DISCORD_WEBHOOK_URL is set, pi itself posts
# report.pdf to that webhook as one of its own tool calls, not this script.
# This script only handles what the harness itself must guarantee: both
# deliverables exist afterward, and report.md is surfaced to stderr so it
# ends up wherever this process's output is already being collected -- a
# K8s Job's pod logs in the Prefect deployment, the console locally. No
# separate storage service (lakeFS, Prefect artifact, etc.) for what is a
# disposable, non-cataloged report.
#
# Both files are required at fixed paths so this script doesn't have to guess
# what the prompt asked for -- the prompt passed in is wrapped with an
# instruction to always produce both.
#
# Usage: pi-report.sh <provider> <model> "<prompt>"
# (provider/model are passed straight to `pi --provider --model`; the
# provider's own env vars, e.g. LLM_BASE_URL/LLM_API_KEY, must already be set
# by the caller -- entrypoint.sh turns those into pi's provider config.)
set -euo pipefail

PROVIDER="${1:?Usage: pi-report.sh <provider> <model> \"<prompt>\"}"
MODEL="${2:?Usage: pi-report.sh <provider> <model> \"<prompt>\"}"
PROMPT="${3:?Usage: pi-report.sh <provider> <model> \"<prompt>\"}"
OUTPUT_DIR="${OUTPUT_DIR:-/output}"

mkdir -p "$OUTPUT_DIR"

FULL_PROMPT="$(cat /opt/skills/harness-conventions/SKILL.md)

$(cat /opt/skills/code-analysis-report/SKILL.md)

$(cat /opt/skills/discord-report-delivery/SKILL.md)

$(cat /opt/skills/scratch-url-upload/SKILL.md)

---

Always write the report to both ${OUTPUT_DIR}/report.pdf and ${OUTPUT_DIR}/report.md (the PDF per the report template above, report.md as its untouched Markdown source) -- both files are required, not just one.

$PROMPT"

pi --provider "$PROVIDER" --model "$MODEL" \
   --skill /opt/skills/harness-conventions --skill /opt/skills/code-analysis-report \
   --skill /opt/skills/discord-report-delivery --skill /opt/skills/scratch-url-upload \
   --mode json -p "$FULL_PROMPT"

python3 /opt/pi-trace-extension/extensions/trace/trace_to_html.py >&2 || true
HTML=$(ls -t /root/.pi/agent/traces/*/trace.html 2>/dev/null | head -1)
[ -n "$HTML" ] && cp "$HTML" "$OUTPUT_DIR/trace.html"

if [ ! -f "$OUTPUT_DIR/report.pdf" ] || [ ! -f "$OUTPUT_DIR/report.md" ]; then
  echo "pi-report: ERROR - expected both ${OUTPUT_DIR}/report.pdf and ${OUTPUT_DIR}/report.md, at least one is missing" >&2
  ls -la "$OUTPUT_DIR" >&2
  exit 1
fi

# Surfacing report.md, not part of pi's own event stream -- goes to stderr,
# same convention as trace_to_html.py above, so it never lands in run.jsonl
# (which run-prompt.sh's stdout pipeline treats as pure JSONL). Still reaches
# the console locally (stderr isn't suppressed) and still lands in K8s pod
# logs (stdout+stderr are captured combined there), so nothing is lost by
# keeping it off stdout. Discord delivery already happened (or was skipped)
# inside the pi session above, per discord-report-delivery.
{
  echo "===REPORT_MD_BEGIN==="
  cat "$OUTPUT_DIR/report.md"
  echo "===REPORT_MD_END==="
} >&2
