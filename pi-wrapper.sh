#!/usr/bin/env bash
# `pi` in this image. With a prompt -- `pi [--provider NAME] [--model ID] "<prompt>"` -- the task runs through
# pi-agent-task.sh, so a hand-started run behaves like a Prefect run (all skills loaded, today's EPISERVE API token
# fetched, the same delivery rules). Without a prompt, or with any other option, the real pi starts as usual
# (interactive session). Installed as /usr/local/sbin/pi, which comes before the real binary in /usr/local/bin in
# PATH; pi-agent-task.sh calls the real one by its full path.
#
# Provider and model default to $PI_PROVIDER / $PI_MODEL, then $LLM_PROVIDER_NAME / $LLM_MODEL (first entry of a
# comma-separated list), then zib / zib/konrad-1. RAW=1 shows pi's unfiltered event stream.
set -euo pipefail

REAL_PI="${PI_BIN:-/usr/local/bin/pi}"
PROVIDER="${PI_PROVIDER:-${LLM_PROVIDER_NAME:-zib}}"
MODEL="${PI_MODEL:-${LLM_MODEL:-zib/konrad-1}}"
MODEL="${MODEL%%,*}"
PROMPT=()
ARGS=("$@")
while [ $# -gt 0 ]; do
    case "$1" in
        --provider) [ $# -ge 2 ] || exec "$REAL_PI" "${ARGS[@]}"; PROVIDER="$2"; shift 2 ;;
        --model) [ $# -ge 2 ] || exec "$REAL_PI" "${ARGS[@]}"; MODEL="$2"; shift 2 ;;
        -*) exec "$REAL_PI" "${ARGS[@]}" ;;  # any other option: the real pi, as before
        *) PROMPT+=("$1"); shift ;;
    esac
done
if [ ${#PROMPT[@]} -eq 0 ]; then
    exec "$REAL_PI" "${ARGS[@]}"
fi

if [ -z "${RAW:-}" ] && [ -f /opt/pretty.py ]; then
    pi-agent-task.sh "$PROVIDER" "$MODEL" "${PROMPT[*]}" | python3 /opt/pretty.py
else
    pi-agent-task.sh "$PROVIDER" "$MODEL" "${PROMPT[*]}"
fi
