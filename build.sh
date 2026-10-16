#!/usr/bin/env bash
# Build the image with the latest pi harness and the latest episerve /
# episerve-doip-cli release binaries (the skills from episerve_skills are always
# re-resolved by the Dockerfile itself). Extra args go to `docker build`.
set -euo pipefail
cd "$(dirname "$0")"
exec docker build --build-arg PI_BUILD_EPOCH="$(date +%s)" -t "${IMAGE:-pi-agent}" "$@" .
