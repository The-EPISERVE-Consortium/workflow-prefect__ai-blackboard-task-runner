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

case "$LLM_PROVIDER" in
  ollama)
    MODEL="${OLLAMA_MODEL:-qwen3.5:35b}"
    : "${OLLAMA_HOST:?Set OLLAMA_HOST (e.g. https://ollama.zib.de/ollama)}"
    : "${OLLAMA_API_BASE:?Set OLLAMA_API_BASE (same value as OLLAMA_HOST)}"
    : "${OLLAMA_API_KEY:?Set OLLAMA_API_KEY}"
    ENV_ARGS=(
      -e OLLAMA_HOST="$OLLAMA_HOST"
      -e OLLAMA_API_BASE="$OLLAMA_API_BASE"
      -e OLLAMA_API_KEY="$OLLAMA_API_KEY"
    )
    ;;
  openrouter)
    MODEL="${OPENROUTER_MODEL:-anthropic/claude-sonnet-4.5}"
    : "${OPENROUTER_API_KEY:?Set OPENROUTER_API_KEY}"
    ENV_ARGS=(-e OPENROUTER_API_KEY="$OPENROUTER_API_KEY")
    ;;
  zib)
    MODEL="${ZIB_MODEL:-zib/konrad-1}"
    : "${ZIB_API_KEY:?Set ZIB_API_KEY}"
    # Registered via the generic "custom" OpenAI-compatible provider path in
    # entrypoint.sh (LLM_BASE_URL/LLM_API_KEY/...), named "zib" here so
    # --provider zib below matches what gets registered.
    ENV_ARGS=(
      -e LLM_BASE_URL="https://tllm.science-berlin.de"
      -e LLM_API_KEY="$ZIB_API_KEY"
      -e LLM_MODEL="$MODEL"
      -e LLM_PROVIDER_NAME=zib
      -e LLM_API_TYPE=openai-completions
    )
    ;;
  *)
    echo "Unknown LLM_PROVIDER '$LLM_PROVIDER' -- expected 'ollama', 'openrouter', or 'zib'" >&2
    exit 1
    ;;
esac

echo "=== running with provider='$LLM_PROVIDER' model='$MODEL' ==="

# Both skills (harness-conventions, code-analysis-report) are force-loaded
# every run by concatenating their full SKILL.md content directly into the
# prompt -- not via pi's /skill:name command, which only parses one name per
# message and would leave a second skill to the model's own (unreliable)
# on-demand discovery. --skill flags are also passed so they're registered
# as proper skills too (harmless, mainly for /model-style introspection).
#
# $0 inside stays literal here (escaped) -- it's filled in by the "$PROMPT"
# arg passed to `bash -c "$INNER_SCRIPT" "$PROMPT"` below, which is how the
# prompt text reaches -p without needing to embed/escape it in this string.
# No --no-session: pi-trace-extension only writes events.jsonl for a real
# session, so the run is intentionally session-backed (ephemeral either way
# since the container is --rm'd after).
INNER_SCRIPT="FULL_PROMPT=\"\$(cat /opt/skills/harness-conventions/SKILL.md)

\$(cat /opt/skills/code-analysis-report/SKILL.md)

---

\$0\"
pi --provider '$LLM_PROVIDER' --model '$MODEL' --skill /opt/skills/harness-conventions --skill /opt/skills/code-analysis-report --mode json -p \"\$FULL_PROMPT\"
python3 /opt/pi-trace-extension/extensions/trace/trace_to_html.py >&2 || true
HTML=\$(ls -t /root/.pi/agent/traces/*/trace.html 2>/dev/null | head -1)
[ -n \"\$HTML\" ] && cp \"\$HTML\" /output/trace.html"

# Full raw JSONL always goes to run.jsonl regardless of console formatting.
# pretty.py merges streaming deltas into one readable line per block for the
# console; set RAW=1 to see the unfiltered event stream instead.
docker run --rm \
  "${ENV_ARGS[@]}" \
  -v "$OUTPUT_ABS":/output \
  pi-agent bash -c "$INNER_SCRIPT" "$PROMPT" \
  | tee "$OUTPUT_DIR/run.jsonl" \
  | if [ -n "${RAW:-}" ]; then cat; else python3 "$SCRIPT_DIR/pretty.py"; fi

echo
echo "--- files in $OUTPUT_DIR ---"
ls -la "$OUTPUT_DIR"
