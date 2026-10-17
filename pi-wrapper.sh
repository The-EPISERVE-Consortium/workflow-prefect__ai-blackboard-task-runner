#!/usr/bin/env bash
# `pi` in this image. With a prompt -- `pi [--provider NAME] [--model ID] "<prompt>"` -- the task runs through
# pi-agent-task.sh, so a hand-started run behaves like a Prefect run (all skills loaded, today's EPISERVE API token
# fetched, the same delivery rules). Without a prompt, or with any other option, the real pi starts as usual
# (interactive session) -- with the same skills registered (--skill per skill) and the API token in the environment. Installed as /usr/local/sbin/pi, which comes before the real binary in /usr/local/bin in
# PATH; pi-agent-task.sh calls the real one by its full path.
#
# Provider and model default to $PI_PROVIDER / $PI_MODEL, then $LLM_PROVIDER_NAME / $LLM_MODEL (first entry of a
# comma-separated list), then zib / zib/konrad-1. RAW=1 shows pi's unfiltered event stream.
set -euo pipefail

. "${PI_COMMON:-/usr/local/lib/pi-common.sh}"

REAL_PI="${PI_BIN:-/usr/local/bin/pi}"
PROVIDER="${PI_PROVIDER:-${LLM_PROVIDER_NAME:-zib}}"
MODEL="${PI_MODEL:-${LLM_MODEL:-zib/konrad-1}}"
MODEL="${MODEL%%,*}"
PROMPT=()
ARGS=("$@")

# The real pi, with every skill registered (descriptions up front, bodies read on demand) and today's API token.
interactive() {
    local flags=() dir
    case " ${ARGS[*]} " in *" --no-skills "*|*" -ns "*) ;; *)
        collect_skill_dirs
        for dir in "${SKILL_DIRS[@]}"; do flags+=(--skill "$dir"); done ;;
    esac
    fetch_episerve_token
    exec "$REAL_PI" "${flags[@]}" "${ARGS[@]}"
}
while [ $# -gt 0 ]; do
    case "$1" in
        --provider) [ $# -ge 2 ] || interactive; PROVIDER="$2"; shift 2 ;;
        --model) [ $# -ge 2 ] || interactive; MODEL="$2"; shift 2 ;;
        -*) interactive ;;  # any other option: the real pi
        *) PROMPT+=("$1"); shift ;;
    esac
done
if [ ${#PROMPT[@]} -eq 0 ]; then
    interactive
fi

if [ -z "${RAW:-}" ] && [ -f /opt/pretty.py ]; then
    pi-agent-task.sh "$PROVIDER" "$MODEL" "${PROMPT[*]}" | python3 /opt/pretty.py
else
    pi-agent-task.sh "$PROVIDER" "$MODEL" "${PROMPT[*]}"
fi
