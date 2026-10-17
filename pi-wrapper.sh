#!/usr/bin/env bash
# `pi` in this image: runs the task through pi-agent-task.sh instead of starting the interactive harness, so a
# hand-started run behaves like a Prefect run (all skills loaded, today's EPISERVE API token fetched, the same
# delivery rules). Installed as /usr/local/sbin/pi, which comes before the real binary in /usr/local/bin in PATH;
# pi-agent-task.sh calls the real one by its full path.
#
# Usage: pi [--provider NAME] [--model ID] "<prompt>"
# Provider and model default to $PI_PROVIDER / $PI_MODEL, then $LLM_PROVIDER_NAME / $LLM_MODEL (first entry of a
# comma-separated list), then zib / zib/konrad-1. RAW=1 shows pi's unfiltered event stream.
set -euo pipefail

usage() {
    echo 'usage: pi [--provider NAME] [--model ID] "<prompt>"' >&2
    echo "pi runs one task headlessly through pi-agent-task.sh; an interactive session is not available here." >&2
}

PROVIDER="${PI_PROVIDER:-${LLM_PROVIDER_NAME:-zib}}"
MODEL="${PI_MODEL:-${LLM_MODEL:-zib/konrad-1}}"
MODEL="${MODEL%%,*}"
PROMPT=()
while [ $# -gt 0 ]; do
    case "$1" in
        --provider) PROVIDER="${2:?--provider needs a value}"; shift 2 ;;
        --model) MODEL="${2:?--model needs a value}"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        -*) echo "pi: option '$1' is not supported here" >&2; usage; exit 2 ;;
        *) PROMPT+=("$1"); shift ;;
    esac
done
if [ ${#PROMPT[@]} -eq 0 ]; then
    usage
    exit 2
fi

if [ -z "${RAW:-}" ] && [ -f /opt/pretty.py ]; then
    pi-agent-task.sh "$PROVIDER" "$MODEL" "${PROMPT[*]}" | python3 /opt/pretty.py
else
    pi-agent-task.sh "$PROVIDER" "$MODEL" "${PROMPT[*]}"
fi
