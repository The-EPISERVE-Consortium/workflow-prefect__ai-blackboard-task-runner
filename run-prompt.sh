#!/usr/bin/env bash
# Headless single-prompt run, mirroring what a future Prefect Job would do:
# start pi-agent, hand it one prompt, stream progress, collect result files
# from a mount separate from the scratch workspace.
#
# Provider is chosen manually via LLM_PROVIDER -- no automatic fallback.
# If a run fails (e.g. Ollama's non-deterministic tool-call HTTP 500, see
# "known issue" in the harness notes), just re-run this script with
# LLM_PROVIDER=openrouter yourself.
#
# /workspace (scratch area -- clones, intermediate files) lives entirely
# inside the container's own filesystem, not bind-mounted. It never touches
# the host and is discarded automatically when the container exits (--rm),
# including anything git/pi wrote as root -- no leftover files to clean up
# manually. Only /output (the actual deliverables) is bind-mounted.
#
# Usage:
#   LLM_PROVIDER=ollama     ./run-prompt.sh "<prompt>" [output_dir]
#   LLM_PROVIDER=openrouter ./run-prompt.sh "<prompt>" [output_dir]
#   LLM_PROVIDER=zib        ./run-prompt.sh "<prompt>" [output_dir]
#
# ollama:     requires OLLAMA_HOST / OLLAMA_API_BASE / OLLAMA_API_KEY.
#             Model via OLLAMA_MODEL (default qwen3.5:35b).
# openrouter: requires OPENROUTER_API_KEY.
#             Model via OPENROUTER_MODEL (default anthropic/claude-sonnet-4.5).
# zib:        requires ZIB_API_KEY. Genuine OpenAI-compatible endpoint
#             (LiteLLM in front of vLLM at tllm.science-berlin.de) -- unlike
#             ollama.zib.de's OpenAI-compat facade, this one has no known
#             num_ctx truncation issue, so the generic "custom" provider path
#             is used directly rather than a native workaround.
#             Model via ZIB_MODEL (default zib/konrad-1).
#
# Console output is filtered through pretty.py, which merges streaming
# thinking/text deltas into one line per block instead of a flood of
# per-token JSON lines. The full unfiltered stream is always saved to
# run.jsonl regardless; set RAW=1 to also print it unfiltered to the console.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PROMPT="${1:?Usage: $0 \"<prompt>\" [output_dir]}"
OUTPUT_DIR="${2:-./run-output}"

LLM_PROVIDER="${LLM_PROVIDER:?Set LLM_PROVIDER to 'ollama', 'openrouter', or 'zib'}"

mkdir -p "$OUTPUT_DIR"
OUTPUT_ABS="$(realpath "$OUTPUT_DIR")"

# Provider shorthand (LLM_PROVIDER=zib -> LLM_BASE_URL=https://tllm.science-berlin.de
# etc.) is expanded by entrypoint.sh itself now, not here -- this only picks
# the MODEL default/override and does an early fail-fast check so a missing
# key is caught before spinning up a container, not after. entrypoint.sh
# re-validates the same env vars regardless (it has to, for the K8s/Prefect
# path that bypasses this script entirely), so the checks here are a faster
# local UX, not the source of truth.
case "$LLM_PROVIDER" in
  ollama)
    MODEL="${OLLAMA_MODEL:-qwen3.5:35b}"
    : "${OLLAMA_HOST:?Set OLLAMA_HOST (e.g. https://ollama.zib.de/ollama)}"
    : "${OLLAMA_API_KEY:?Set OLLAMA_API_KEY}"
    ENV_ARGS=(
      -e LLM_PROVIDER=ollama
      -e OLLAMA_HOST="$OLLAMA_HOST"
      -e OLLAMA_API_KEY="$OLLAMA_API_KEY"
    )
    ;;
  openrouter)
    MODEL="${OPENROUTER_MODEL:-anthropic/claude-sonnet-4.5}"
    : "${OPENROUTER_API_KEY:?Set OPENROUTER_API_KEY}"
    ENV_ARGS=(-e LLM_PROVIDER=openrouter -e OPENROUTER_API_KEY="$OPENROUTER_API_KEY")
    ;;
  zib)
    MODEL="${ZIB_MODEL:-zib/konrad-1}"
    : "${ZIB_API_KEY:?Set ZIB_API_KEY}"
    ENV_ARGS=(-e LLM_PROVIDER=zib -e ZIB_API_KEY="$ZIB_API_KEY" -e LLM_MODEL="$MODEL")
    ;;
  *)
    echo "Unknown LLM_PROVIDER '$LLM_PROVIDER' -- expected 'ollama', 'openrouter', or 'zib'" >&2
    exit 1
    ;;
esac

echo "=== running with provider='$LLM_PROVIDER' model='$MODEL' ==="

# Pass DISCORD_WEBHOOK_URL through if set, so local runs can exercise the
# same delivery path the eventual K8s Job uses. Unset it and pi-agent-task.sh
# just skips that step.
if [ -n "${DISCORD_WEBHOOK_URL:-}" ]; then
  ENV_ARGS+=(-e DISCORD_WEBHOOK_URL="$DISCORD_WEBHOOK_URL")
fi

# Same reasoning for the connection vars of the blackboard-communication,
# episerve-platform-access and doip-fdo-access skills -- pass through
# whichever of these happen to be set; partial sets just mean the skill's own
# env-var check reports a real failure inside the session, the same way it
# would in the K8s job.
for var in MARIADB_HOST BLACKBOARD_DB BLACKBOARD_USER BLACKBOARD_PASSWORD \
           EPISERVE_API_URL EPISERVE_CKAN_URL EPISERVE_DOIP_URL EPISERVE_API_KEY \
           DOIP_HOST DOIP_PORT DOIP_UPDATE_TOKEN; do
  if [ -n "${!var:-}" ]; then
    ENV_ARGS+=(-e "$var=${!var}")
  fi
done

# pi-agent-task.sh (baked into the image at /usr/local/bin/pi-agent-task.sh)
# is the single place that runs pi, concatenates all skills into the prompt,
# writes trace.html, and delivers the result (agent-decided, e.g. a file ->
# Discord webhook, a scratch URL -> stdout between markers). It's shared with
# the eventual K8s Job's container command, so local runs here exercise the
# exact same code path as the deployed version -- not a separate inline copy
# of the logic.
#
# Full raw JSONL always goes to run.jsonl regardless of console formatting.
# pretty.py merges streaming deltas into one readable line per block for the
# console; set RAW=1 to see the unfiltered event stream instead.
docker run --rm \
  "${ENV_ARGS[@]}" \
  -v "$OUTPUT_ABS":/output \
  pi-agent pi-agent-task.sh "$LLM_PROVIDER" "$MODEL" "$PROMPT" \
  | tee "$OUTPUT_DIR/run.jsonl" \
  | if [ -n "${RAW:-}" ]; then cat; else python3 "$SCRIPT_DIR/pretty.py"; fi

echo
echo "--- files in $OUTPUT_DIR ---"
ls -la "$OUTPUT_DIR"
