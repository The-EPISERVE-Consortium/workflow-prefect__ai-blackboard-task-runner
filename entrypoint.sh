#!/usr/bin/env bash
set -euo pipefail

CONFIG_DIR="$HOME/.pi/agent"
mkdir -p "$CONFIG_DIR"
mkdir -p /output

# LLM_PROVIDER shorthand -- expands to the generic custom-provider vars
# (LLM_BASE_URL/LLM_API_KEY/...) or the native-Ollama vars (OLLAMA_*) below,
# whichever haven't already been set explicitly. This used to live only in
# run-prompt.sh's bash `case` statement, which meant any invocation path
# that bypassed run-prompt.sh (a Prefect-triggered K8s Job calling
# pi-agent-task.sh directly) never got the shorthand -- moved here so it's
# one implementation shared by every path, not two that can drift apart.
case "${LLM_PROVIDER:-}" in
  zib)
    : "${ZIB_API_KEY:?Set ZIB_API_KEY for LLM_PROVIDER=zib}"
    LLM_BASE_URL="${LLM_BASE_URL:-https://tllm.science-berlin.de}"
    LLM_API_KEY="${LLM_API_KEY:-$ZIB_API_KEY}"
    LLM_MODEL="${LLM_MODEL:-zib/konrad-1}"
    LLM_PROVIDER_NAME="${LLM_PROVIDER_NAME:-zib}"
    LLM_API_TYPE="${LLM_API_TYPE:-openai-completions}"
    ;;
  ollama)
    : "${OLLAMA_HOST:?Set OLLAMA_HOST for LLM_PROVIDER=ollama (e.g. https://ollama.zib.de/ollama)}"
    : "${OLLAMA_API_KEY:?Set OLLAMA_API_KEY for LLM_PROVIDER=ollama}"
    OLLAMA_API_BASE="${OLLAMA_API_BASE:-$OLLAMA_HOST}"
    ;;
  openrouter)
    : "${OPENROUTER_API_KEY:?Set OPENROUTER_API_KEY for LLM_PROVIDER=openrouter}"
    # No further setup needed -- OpenRouter is built into pi natively.
    ;;
  custom|"")
    ;;  # generic path below handles LLM_BASE_URL/LLM_API_KEY directly if set
  *)
    echo "pi: unknown LLM_PROVIDER '${LLM_PROVIDER}' -- expected 'zib', 'ollama', 'openrouter', or 'custom'" >&2
    exit 1
    ;;
esac

if [ -n "${LLM_BASE_URL:-}" ] && [ -n "${LLM_API_KEY:-}" ]; then
  API_TYPE="${LLM_API_TYPE:-openai-completions}"
  PROVIDER_NAME="${LLM_PROVIDER_NAME:-custom}"
  BASE_TRIMMED="${LLM_BASE_URL%/}"

  if [ -n "${LLM_MODEL:-}" ]; then
    # comma-separated list -> one entry per model
    MODELS_JSON=$(echo "$LLM_MODEL" | tr ',' '\n' | sed '/^\s*$/d' | jq -R '{id: .}' | jq -s '.')
  else
    echo "pi: LLM_MODEL not set - discovering available models from ${BASE_TRIMMED}"

    # try OpenAI-style /models (returns {"data":[{"id":...}]})
    DISCOVERED=$(curl -sf --max-time 10 -H "Authorization: Bearer ${LLM_API_KEY}" "${BASE_TRIMMED}/models" 2>/dev/null || true)
    MODELS_JSON=$(echo "$DISCOVERED" | jq '[.data[]? | {id: .id}]' 2>/dev/null || true)

    # fall back to Ollama-native /tags (returns {"models":[{"name":...}]})
    if [ -z "${MODELS_JSON:-}" ] || [ "$MODELS_JSON" = "null" ] || [ "$MODELS_JSON" = "[]" ]; then
      DISCOVERED=$(curl -sf --max-time 10 -H "Authorization: Bearer ${LLM_API_KEY}" "${BASE_TRIMMED}/tags" 2>/dev/null || true)
      MODELS_JSON=$(echo "$DISCOVERED" | jq '[.models[]? | {id: .name}]' 2>/dev/null || true)
    fi

    if [ -z "${MODELS_JSON:-}" ] || [ "$MODELS_JSON" = "null" ] || [ "$MODELS_JSON" = "[]" ]; then
      echo "pi: model discovery failed - falling back to default model 'qwen3.5:35b' (set LLM_MODEL to override)"
      MODELS_JSON='[{"id":"qwen3.5:35b"}]'
    else
      echo "pi: discovered $(echo "$MODELS_JSON" | jq length) model(s)"
    fi
  fi

  # Ollama's default context window (often 2048-8192) truncates agent runs that
  # read many files before they can respond. samplingParams is merged verbatim
  # into every request body for openai-completions APIs, so this forwards
  # Ollama's native "options.num_ctx" even through the OpenAI-compatible route.
  if [ -n "${LLM_NUM_CTX:-}" ] && [ "$API_TYPE" = "openai-completions" ]; then
    MODELS_JSON=$(echo "$MODELS_JSON" | jq --argjson ctx "$LLM_NUM_CTX" \
      'map(. + {samplingParams: {options: {num_ctx: $ctx}}})')
    echo "pi: setting num_ctx=${LLM_NUM_CTX} via samplingParams for all models"
  fi

  jq -n \
    --arg name "$PROVIDER_NAME" \
    --arg baseUrl "$LLM_BASE_URL" \
    --arg api "$API_TYPE" \
    --arg apiKey "$LLM_API_KEY" \
    --argjson models "$MODELS_JSON" \
    '{providers: {($name): {baseUrl: $baseUrl, api: $api, apiKey: $apiKey, models: $models}}}' \
    > "$CONFIG_DIR/models.json"

  echo "pi: wrote custom provider '${PROVIDER_NAME}' (${API_TYPE}) -> ${LLM_BASE_URL} with $(echo "$MODELS_JSON" | jq length) model(s) to ${CONFIG_DIR}/models.json"
else
  echo "pi: LLM_BASE_URL / LLM_API_KEY not set - skipping custom provider config (set them to auto-configure pi)."
fi

# Always load pi-trace-extension (renders events.jsonl -> trace.html, no
# server/DB needed). Requires a real session (not --no-session) to write
# anything -- see run-prompt.sh.
PACKAGES='["/opt/pi-trace-extension"]'

# Native Ollama route (respects num_ctx; the OpenAI-compat route above does
# not, on deployments like ollama.zib.de). Registers the vendored
# pi-ollama-provider extension as provider "ollama" -- use with
# --provider ollama --model <id>.
if [ -n "${OLLAMA_API_BASE:-}" ] && [ -n "${OLLAMA_API_KEY:-}" ]; then
  PACKAGES=$(echo "$PACKAGES" | jq '. + ["/opt/pi-ollama-provider"]')
  echo "pi: registered native Ollama provider 'ollama' -> ${OLLAMA_API_BASE} (use --provider ollama --model <id>)"
fi

jq -n --argjson pkgs "$PACKAGES" '{packages: $pkgs}' > "$CONFIG_DIR/settings.json"

# github-pr skill support: authenticate `gh`/`git` as the episerve-ai-bot
# identity, once, here -- not per-skill-invocation, same reasoning as the
# LLM_PROVIDER shorthand above (one implementation shared by every path,
# rather than something the skill's own instructions would have to repeat
# and could drift from).
#
# No `gh auth login` step -- `gh` already authenticates every command
# directly off GITHUB_TOKEN when it's present in the environment (a login
# step would only store credentials on disk for when the env var *isn't*
# set, which doesn't apply here, and actively logs a confusing warning
# since the env var takes precedence over it anyway). `gh auth setup-git`
# alone is what's actually needed: it registers `gh` as git's credential
# helper for github.com, so a plain `git clone`/`git push` also
# authenticates via GITHUB_TOKEN -- no token ever gets embedded in a
# remote URL. `gh auth status` then gives a real, live validity check
# (it calls the GitHub API), logged here so an invalid/expired token is
# visible immediately rather than only failing later mid-task.
if [ -n "${GITHUB_TOKEN:-}" ]; then
  gh auth setup-git 2>&1
  git config --global user.name "${GITHUB_USER:-episerve-ai-bot}"
  git config --global user.email "${GITHUB_EMAIL:-episerve-ai-bot@users.noreply.github.com}"
  if gh auth status 2>&1; then
    echo "pi: gh/git authenticated as '${GITHUB_USER:-episerve-ai-bot}'"
  else
    echo "pi: GITHUB_TOKEN appears invalid -- github-pr skill won't be able to push/open a PR this run" >&2
  fi
fi

exec "$@"
