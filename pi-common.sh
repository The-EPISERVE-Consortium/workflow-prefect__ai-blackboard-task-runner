#!/usr/bin/env bash
# Shared by pi-agent-task.sh (headless runs) and pi-wrapper.sh (interactive `pi`): which skills are loaded and how
# the EPISERVE API token gets into the environment. Sourced, not run.

SKILLS_DIR="${SKILLS_DIR:-/opt/skills}"

# Fills SKILL_DIRS with every skill under $SKILLS_DIR: the two core ones first (in this order), then the rest
# alphabetically. Adding or removing a skill (in vendor/skills or in the episerve_skills repo) needs no change here.
collect_skill_dirs() {
    local core=(harness-conventions code-analysis-report) name dir
    SKILL_DIRS=()
    for name in "${core[@]}"; do SKILL_DIRS+=("$SKILLS_DIR/$name"); done
    for dir in "$SKILLS_DIR"/*/; do
        dir="${dir%/}"
        case " ${core[*]} " in *" $(basename "$dir") "*) continue ;; esac
        [ -f "$dir/SKILL.md" ] && SKILL_DIRS+=("$dir")
    done
    return 0
}

# EPISERVE access: the API token is valid for one day, so it cannot be a static secret. If the run has the
# credentials of a user (EPISERVE_USERNAME / EPISERVE_PASSWORD; for Prefect runs the sealed secret
# episerve-agent-credentials) and no token yet, fetch today's token for the skills. Best-effort: without it reads
# still work and the skills report the 401 on a write.
fetch_episerve_token() {
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
    return 0
}
